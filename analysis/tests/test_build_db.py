"""The build: row counts, exact min_amount, no nulls from bridge_data, the
reference tables and where they are read from (the repository), the
sample query, the runner and the missing-file message. The view
transfers_priced has its own tests in test_transfers_priced.py.

Expected figures come from analysis/notebooks/00_explore.ipynb: 124,858 transfer rows and 40,754 price
rows; the largest minAmount 20,273,815,112,416,660,413,525,450 with 14,864
rows above int64 and no zero; 2 empty integrator strings; first and
last block_time 2026-10-13 00:00:00 and 2026-10-19 23:59:49 UTC; base is
the busiest chain with 34,908 rows; 381 unpriced rows and a
$307,935,992.59 total under the first USD column, ethereum first.
"""

from __future__ import annotations

import shutil
from datetime import datetime
from pathlib import Path

import duckdb
import pandas as pd
import pytest

from lifi import load, paths, query
from lifi.build_db import build
from lifi.build_db import main as build_main
from lifi.query import main as query_main
from lifi.query import run, run_sql

TRANSFER_ROWS = 124_858
PRICE_ROWS = 40_754
MAX_MIN_AMOUNT = 20_273_815_112_416_660_413_525_450
ROWS_ABOVE_INT64 = 14_864
INT64_MAX = 2**63 - 1
EMPTY_INTEGRATOR_ROWS = 2
FIRST_BLOCK_TIME = datetime(2026, 10, 13, 0, 0, 0)
LAST_BLOCK_TIME = datetime(2026, 10, 19, 23, 59, 49)
BASE_ROWS = 34_908
UNPRICED_ROWS = 381
TOTAL_USD = 307_935_992.59

# A sample query: transfers joined to prices, USD by chain.
SAMPLE_QUERY = """
SELECT t.chain,
       count(*)                                                AS rows,
       count(*) FILTER (WHERE p.price_usd IS NULL)             AS unpriced_rows,
       sum(t.min_amount / power(10, p.decimals) * p.price_usd) AS usd
FROM transfers t
LEFT JOIN prices p
       ON p.chain = t.chain
      AND p.token_address = t.sending_asset_id
      AND p.hour = date_trunc('hour', t.block_time)
GROUP BY t.chain
ORDER BY usd DESC
"""


def count(con, table: str) -> int:
    # fetchall, never fetchone: a result left open on the shared session connection breaks a later con.sql().
    [(n,)] = con.execute(f'SELECT count(*) FROM "{table}"').fetchall()
    return n


def column_types(con, table: str) -> dict[str, str]:
    rows = con.execute(
        "SELECT column_name, data_type FROM information_schema.columns "
        "WHERE table_name = ? ORDER BY ordinal_position",
        [table],
    ).fetchall()
    return dict(rows)


def tables_and_totals(con) -> tuple[dict[str, int], list[tuple]]:
    """Every table and view with its row count, and transfers_priced's two USD totals to the cent."""
    names = con.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'main'").fetchall()
    counts = {name: con.execute(f'SELECT count(*) FROM "{name}"').fetchall()[0][0] for (name,) in names}
    totals = con.execute(
        "SELECT CAST(sum(amount_usd_provided) AS DECIMAL(18, 2)), CAST(sum(amount_usd) AS DECIMAL(18, 2)) "
        "FROM transfers_priced"
    ).fetchall()
    return counts, totals


def link_or_copy(source: Path, link: Path) -> None:
    """A symbolic link to `source`, or a copy where the file system refuses links."""
    try:
        link.symlink_to(source)
    except OSError:
        shutil.copyfile(source, link)


# --- the tables -------------------------------------------------------------


def test_row_counts(con):
    assert count(con, "transfers") == TRANSFER_ROWS
    assert count(con, "prices") == PRICE_ROWS


def test_column_names_and_types(con):
    transfers = column_types(con, "transfers")
    assert list(transfers) == load.TRANSFER_COLUMNS
    assert transfers["min_amount"] == "HUGEINT"
    assert transfers["block_time"] == "TIMESTAMP"
    assert transfers["block_number"] == transfers["log_index"] == "BIGINT"
    assert transfers["destination_chain_id"] == "BIGINT"
    assert transfers["has_source_swaps"] == transfers["has_destination_call"] == "BOOLEAN"
    prices = column_types(con, "prices")
    assert list(prices) == load.PRICE_COLUMNS
    assert prices["decimals"] == "BIGINT"
    assert prices["hour"] == "TIMESTAMP"
    assert prices["price_usd"] == "DOUBLE"


def test_min_amount_is_exact_and_exceeds_int64(con):
    [(largest, above_int64, zero)] = con.execute(
        "SELECT max(min_amount), count(*) FILTER (WHERE min_amount > ?), "
        "count(*) FILTER (WHERE min_amount <= 0) FROM transfers",
        [INT64_MAX],
    ).fetchall()
    assert isinstance(largest, int)
    assert largest > INT64_MAX
    assert largest == MAX_MIN_AMOUNT
    assert above_int64 == ROWS_ABOVE_INT64
    assert zero == 0


@pytest.mark.parametrize("column", list(load.BRIDGE_DATA_COLUMNS.values()))
def test_bridge_data_columns_have_no_nulls(con, column):
    assert con.execute(f'SELECT count(*) FROM transfers WHERE "{column}" IS NULL').fetchall() == [(0,)]


def test_empty_integrator_strings_stay_strings(con):
    assert con.execute("SELECT count(*) FROM transfers WHERE integrator = ''").fetchall() == [(EMPTY_INTEGRATOR_ROWS,)]


def test_block_time_is_utc(con):
    assert con.execute("SELECT min(block_time), max(block_time) FROM transfers").fetchall() == [
        (FIRST_BLOCK_TIME, LAST_BLOCK_TIME)
    ]
    assert con.execute("SELECT count(DISTINCT hour) FROM prices").fetchall() == [(168,)]


def test_reference_tables_mirror_reference_files(con):
    # The repository's data/reference/, not a reference/ folder under the data directory.
    expected = {load.reference_table_name(p): len(load.load_reference(p)) for p in load.reference_files()}
    tables = con.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = 'main' AND table_type = 'BASE TABLE'"
    ).fetchall()
    found = {name: count(con, name) for (name,) in tables if name.startswith("ref_")}
    assert found == expected


def test_reference_integer_columns_with_a_gap_load_as_bigint(con):
    # The four integer columns of the registry with an empty cell; api_chain_id is empty only for Aptos
    # (data/reference/README.md), 728126428 for Tron's contract id, and Sui's id is above 2^53.
    registry = column_types(con, "ref_lifi_chain_id_registry")
    for column in ("api_chain_id", "connections_code", "connections_to_tokens", "quote_onchain_destination_chain_id"):
        assert registry[column] == "BIGINT", column
    missing = con.execute(
        "SELECT chain_id, name FROM ref_lifi_chain_id_registry WHERE api_chain_id IS NULL"
    ).fetchall()
    assert missing == [(9_271_000_000_000_010, "APTOS")]
    api_ids = dict(
        con.execute(
            "SELECT chain_id, api_chain_id FROM ref_lifi_chain_id_registry "
            "WHERE chain_id IN (1885080386571452, 9270000000000000)"
        ).fetchall()
    )
    assert api_ids == {1_885_080_386_571_452: 728_126_428, 9_270_000_000_000_000: 9_270_000_000_000_000}


def test_a_data_directory_holding_only_the_two_csvs_builds_with_the_committed_snapshots(
    con, data_dir, tmp_path, monkeypatch
):
    # LIFI_DATA_DIR names a folder holding links to the two provided CSVs and no reference/.
    # lifi-build-db reads every snapshot from the repository's data/reference/, each as its ref_ table,
    # and gives the session database's tables, row counts and transfers_priced totals (the totals
    # are pinned in test_transfers_priced.py).
    only_csvs = tmp_path / "only_csvs"
    only_csvs.mkdir()
    for name in (paths.TRANSFERS_FILE, paths.PRICES_FILE):
        link_or_copy(data_dir / name, only_csvs / name)
    monkeypatch.setenv("LIFI_DATA_DIR", str(only_csvs))
    target = tmp_path / "only_csvs.duckdb"
    assert build_main(["--db", str(target)]) == 0

    built = duckdb.connect(str(target), read_only=True)
    try:
        counts, totals = tables_and_totals(built)
    finally:
        built.close()
    committed = {load.reference_table_name(p): len(load.load_reference(p)) for p in load.reference_files()}
    assert {name: n for name, n in counts.items() if name.startswith("ref_")} == committed
    assert (counts, totals) == tables_and_totals(con)


# --- the sample query (the view's tests are in test_transfers_priced.py) --------


def test_sample_query_joins_transfers_to_prices(db_path):
    frame = run_sql(SAMPLE_QUERY, db_path)
    assert list(frame.columns) == ["chain", "rows", "unpriced_rows", "usd"]
    assert len(frame) == 6
    assert frame["rows"].sum() == TRANSFER_ROWS
    assert frame["unpriced_rows"].sum() == UNPRICED_ROWS
    assert frame["usd"].sum() == pytest.approx(TOTAL_USD, abs=0.01)
    assert frame["chain"].iloc[0] == "ethereum"


# --- the runner ---------------------------------------------------------------


def test_run_accepts_a_path_and_keeps_hugeint_exact(db_path, tmp_path):
    sql_file = tmp_path / "largest_by_chain.sql"
    sql_file.write_text("SELECT chain, max(min_amount) AS largest FROM transfers GROUP BY chain ORDER BY largest DESC")
    frame = run(sql_file, db_path)
    assert isinstance(frame, pd.DataFrame)
    assert len(frame) == 6
    assert frame["largest"].iloc[0] == MAX_MIN_AMOUNT
    assert isinstance(frame["largest"].iloc[0], int)


def test_run_names_the_missing_query(db_path):
    with pytest.raises(query.QueryNotFound, match="no_such_query"):
        run("no_such_query", db_path)


def test_cli_prints_a_table_and_csv(db_path, tmp_path, capsys):
    sql_file = tmp_path / "rows_by_chain.sql"
    sql_file.write_text("SELECT chain, count(*) AS rows FROM transfers GROUP BY chain ORDER BY rows DESC")

    assert query_main([str(sql_file), "--db", str(db_path)]) == 0
    table = capsys.readouterr().out.splitlines()
    assert table[0].split() == ["chain", "rows"]
    assert table[1].split() == ["base", str(BASE_ROWS)]
    assert len(table) == 7

    assert query_main([str(sql_file), "--db", str(db_path), "--csv"]) == 0
    csv = capsys.readouterr().out.splitlines()
    assert csv[0] == "chain,rows"
    assert csv[1] == f"base,{BASE_ROWS}"
    assert len(csv) == 7


def test_build_replaces_an_existing_file_and_connect_builds_a_missing_one(data_dir, tmp_path, capsys):
    target = tmp_path / "rebuilt.duckdb"
    target.write_bytes(b"not a database")
    counts = build(target, data_dir, out=None)
    assert counts["transfers"] == TRANSFER_ROWS
    assert counts["prices"] == PRICE_ROWS
    assert counts["transfers_priced"] == TRANSFER_ROWS

    target.unlink()
    con = query.connect(target, data_dir)
    try:
        assert con.execute("SELECT count(*) FROM transfers").fetchone()[0] == TRANSFER_ROWS
    finally:
        con.close()
    captured = capsys.readouterr()
    assert captured.out == ""
    assert "transfers" in captured.err and f"{TRANSFER_ROWS:,}" in captured.err


# --- without the data files (these run on a clone without data) --------------


def test_paths_honour_environment_overrides(monkeypatch, tmp_path):
    monkeypatch.setenv("LIFI_DATA_DIR", str(tmp_path / "d"))
    monkeypatch.setenv("LIFI_DB_PATH", str(tmp_path / "x.duckdb"))
    assert paths.data_dir() == tmp_path / "d"
    assert paths.db_path() == tmp_path / "x.duckdb"
    assert paths.data_dir(tmp_path) == tmp_path
    # The snapshots stay in the repository whatever LIFI_DATA_DIR says; only an explicit argument moves them.
    assert paths.reference_dir() == paths.REPO_ROOT / "data" / "reference"
    assert paths.reference_dir(tmp_path) == tmp_path
    monkeypatch.delenv("LIFI_DATA_DIR")
    monkeypatch.delenv("LIFI_DB_PATH")
    assert paths.data_dir() == paths.REPO_ROOT / "data"
    assert paths.db_path() == paths.REPO_ROOT / "analysis" / "lifi.duckdb"
    assert paths.reference_dir() == paths.REPO_ROOT / "data" / "reference"
    assert (paths.REPO_ROOT / "analysis" / "lifi").is_dir()


def test_missing_data_file_names_the_file_and_the_readme(tmp_path):
    with pytest.raises(load.MissingDataFile) as info:
        load.load_transfers(tmp_path)
    message = str(info.value)
    assert "transfers_started.csv" in message
    assert str(tmp_path / "transfers_started.csv") in message
    assert "analysis/README.md" in message
    with pytest.raises(load.MissingDataFile, match="prices.csv"):
        load.load_prices(tmp_path)
    assert load.missing_data_files(tmp_path) == [tmp_path / "transfers_started.csv", tmp_path / "prices.csv"]
    assert load.reference_files(tmp_path / "absent") == []


def test_build_cli_reports_a_missing_file_without_a_traceback(tmp_path, capsys):
    target = tmp_path / "never.duckdb"
    assert build_main(["--data-dir", str(tmp_path), "--db", str(target)]) == 2
    captured = capsys.readouterr()
    assert "transfers_started.csv is missing" in captured.err
    assert "analysis/README.md" in captured.err
    assert "Traceback" not in captured.err
    assert not target.exists()


def test_query_cli_reports_a_missing_file_when_it_has_to_build(tmp_path, capsys, monkeypatch):
    monkeypatch.setenv("LIFI_DATA_DIR", str(tmp_path))
    sql_file = tmp_path / "one.sql"
    sql_file.write_text("SELECT 1")
    assert query_main([str(sql_file), "--db", str(tmp_path / "none.duckdb")]) == 2
    captured = capsys.readouterr()
    assert "transfers_started.csv is missing" in captured.err
    assert "analysis/README.md" in captured.err
    assert captured.out == ""


def test_load_reference_keeps_integer_columns_with_a_gap_integer(tmp_path):
    snapshot = tmp_path / "snapshot.csv"
    snapshot.write_text(
        "id,id_gap,big_id_gap,float_gap,float_text_gap,empty,label\n"
        "1,1,9271000000000010,1.5,1.0,,a\n"
        "2,,,,,,b\n"
        "3,-3,9270000000000001,2,2.0,,c\n"
    )
    frame = load.load_reference(snapshot)
    assert str(frame["id"].dtype) == "int64"
    assert str(frame["id_gap"].dtype) == str(frame["big_id_gap"].dtype) == "Int64"
    assert frame["id_gap"].tolist() == [1, pd.NA, -3]
    # 9270000000000001 is above 2^53: converted from the text, not through float64.
    assert frame["big_id_gap"].tolist() == [9_271_000_000_000_010, pd.NA, 9_270_000_000_000_001]
    # Not integer columns in the file: a decimal value, integers written as floats, no value at all.
    assert str(frame["float_gap"].dtype) == str(frame["float_text_gap"].dtype) == str(frame["empty"].dtype) == "float64"
    assert frame["label"].tolist() == ["a", "b", "c"]


def test_reference_table_names_are_identifiers():
    assert load.reference_table_name(Path("chains.csv")) == "ref_chains"
    assert load.reference_table_name(Path("prices_coingecko.partial.csv")) == "ref_prices_coingecko_partial"
    assert load.reference_table_name(Path("a b-c.csv")) == "ref_a_b_c"
