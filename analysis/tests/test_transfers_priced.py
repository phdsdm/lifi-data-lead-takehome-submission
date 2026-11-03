"""The view transfers_priced and its headline USD column.

Expected figures come from analysis/notebooks/02_activity_and_prices.ipynb §8:
$307,935,992.59 over
124,477 rows priced by the provided feed (policy A), $307,969,358.59 over
124,854 rows with the CoinGecko fill (policy B), 377 rows filled by CoinGecko,
4 rows priced by neither, 124,470 rows priced by both feeds, and decimals from
prices.csv for 124,478 rows and from LI.FI's token list for 380. The 381 rows
without a provided price are the profile's (00_explore.ipynb).

The tests at the end build from a small synthetic data directory, so the
policy, the missing-snapshot failure and where the snapshots are read from
(the repository) are checked without the provided CSVs.
"""

from __future__ import annotations

import csv
import json
from decimal import Decimal
from pathlib import Path

import duckdb
import pytest

from lifi import build_db, load, paths
from lifi.build_db import SOURCE_CHAIN_IDS, build
from lifi.build_db import main as build_main

TRANSFER_ROWS = 124_858
TOTAL_USD_PROVIDED = Decimal("307935992.59")
TOTAL_USD = Decimal("307969358.59")
PROVIDED_ROWS = 124_477
COINGECKO_ROWS = 377
UNPRICED_ROWS = 4
NO_PROVIDED_PRICE_ROWS = 381
BOTH_FEEDS_ROWS = 124_470
PROVIDED_DECIMALS_ROWS = 124_478
LIFI_DECIMALS_ROWS = 380

VIEW_COLUMNS = load.TRANSFER_COLUMNS + [
    "hour",
    "symbol",
    "decimals",
    "decimals_source",
    "price_usd_provided",
    "price_usd_coingecko",
    "price_usd",
    "price_source",
    "amount_token",
    "amount_usd_provided",
    "amount_usd",
]


def column_types(con, table: str) -> dict[str, str]:
    rows = con.execute(
        "SELECT column_name, data_type FROM information_schema.columns "
        "WHERE table_name = ? ORDER BY ordinal_position",
        [table],
    ).fetchall()
    return dict(rows)


def notebook_amount_token(min_amount: int, decimals: int) -> float:
    """amount_token as notebook 02 §1 computes it (`token_amount`)."""
    return float(Decimal(int(min_amount)) / Decimal(10) ** int(decimals))


# --- against the provided data (skip without the CSVs) -------------------------


def test_view_columns_and_types(con):
    columns = column_types(con, "transfers_priced")
    assert list(columns) == VIEW_COLUMNS
    assert columns["min_amount"] == "HUGEINT"
    assert columns["hour"] == "TIMESTAMP"
    assert columns["decimals"] == "BIGINT"
    for name in ("symbol", "decimals_source", "price_source"):
        assert columns[name] == "VARCHAR", name
    for name in ("price_usd_provided", "price_usd_coingecko", "price_usd", "amount_token", "amount_usd_provided", "amount_usd"):
        assert columns[name] == "DOUBLE", name


def test_view_keeps_every_transfer_row(con):
    [(total, no_provided, no_usd)] = con.execute(
        "SELECT count(*), count(*) FILTER (WHERE amount_usd_provided IS NULL), "
        "count(*) FILTER (WHERE amount_usd IS NULL) FROM transfers_priced"
    ).fetchall()
    assert total == TRANSFER_ROWS
    assert no_provided == NO_PROVIDED_PRICE_ROWS
    assert no_usd == UNPRICED_ROWS


def test_totals_match_notebook_02_s8_to_the_cent(con):
    [(provided, headline)] = con.execute(
        "SELECT CAST(sum(amount_usd_provided) AS DECIMAL(18, 2)), CAST(sum(amount_usd) AS DECIMAL(18, 2)) "
        "FROM transfers_priced"
    ).fetchall()
    assert provided == TOTAL_USD_PROVIDED
    assert headline == TOTAL_USD


def test_row_counts_by_source_match_notebook_02_s8(con):
    by_price = dict(con.execute("SELECT price_source, count(*) FROM transfers_priced GROUP BY ALL").fetchall())
    assert by_price == {"provided": PROVIDED_ROWS, "coingecko": COINGECKO_ROWS, None: UNPRICED_ROWS}
    by_decimals = dict(con.execute("SELECT decimals_source, count(*) FROM transfers_priced GROUP BY ALL").fetchall())
    assert by_decimals == {"provided": PROVIDED_DECIMALS_ROWS, "lifi": LIFI_DECIMALS_ROWS}
    both = con.execute(
        "SELECT count(*) FROM transfers_priced "
        "WHERE price_usd_provided IS NOT NULL AND price_usd_coingecko IS NOT NULL"
    ).fetchall()
    assert both == [(BOTH_FEEDS_ROWS,)]


def test_price_source_follows_the_policy(con):
    # Every row: the provided price when there is one, else CoinGecko's, else NULL; amount_usd_provided
    # is set exactly on the provided rows and equals amount_usd there.
    violations = con.execute(
        """
        SELECT count(*) FROM transfers_priced
        WHERE NOT CASE price_source
            WHEN 'provided'  THEN price_usd = price_usd_provided
                                  AND amount_usd_provided IS NOT NULL AND amount_usd = amount_usd_provided
            WHEN 'coingecko' THEN price_usd_provided IS NULL AND price_usd = price_usd_coingecko
                                  AND amount_usd_provided IS NULL AND amount_usd IS NOT NULL
            ELSE price_source IS NULL AND price_usd_provided IS NULL AND price_usd_coingecko IS NULL
                 AND price_usd IS NULL AND amount_usd IS NULL AND amount_usd_provided IS NULL
        END
        """
    ).fetchall()
    assert violations == [(0,)]


def test_amount_token_is_the_exact_decimal_shift(con):
    # Every row equals the notebook's Decimal arithmetic bit for bit, including the 14,864
    # min_amount values above int64: min_amount never passes through a float before the shift.
    rows = con.execute("SELECT min_amount, decimals, amount_token FROM transfers_priced").fetchall()
    assert len(rows) == TRANSFER_ROWS
    mismatches = [row for row in rows if row[2] != notebook_amount_token(row[0], row[1])]
    assert mismatches == []


def test_source_chain_ids_are_lifi_chain_ids(con):
    chains = {chain for (chain,) in con.execute("SELECT DISTINCT chain FROM transfers").fetchall()}
    assert chains == set(SOURCE_CHAIN_IDS)
    names = dict(
        con.execute(
            "SELECT id, name FROM ref_lifi_api_chains WHERE id IN (SELECT unnest(?))",
            [list(SOURCE_CHAIN_IDS.values())],
        ).fetchall()
    )
    assert names == {1: "Ethereum", 10: "OP Mainnet", 56: "BSC", 137: "Polygon", 8453: "Base", 42161: "Arbitrum"}


# --- a synthetic data directory (these run without the provided data) ----------

USDC_POLYGON = "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359"
NATIVE = "0x0000000000000000000000000000000000000000"
WETH_ARBITRUM = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"
WETH_ARBITRUM_CHECKSUMMED = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
UNKNOWN_TOKEN = "0x00000000000000000000000000000000000000aa"
ABOVE_INT64 = 20_273_815_112_416_660_413_525_450

# (tx_hash, chain, block_time, sending_asset_id, min_amount)
SYNTHETIC_TRANSFERS = [
    ("0x01", "polygon", "2026-10-13 10:15:00Z", USDC_POLYGON, 2_500_000),  # both feeds: provided wins
    ("0x02", "polygon", "2026-10-13 11:20:00Z", USDC_POLYGON, 1_000_000),  # provided hour missing: CoinGecko
    ("0x03", "polygon", "2026-10-13 10:30:00Z", NATIVE, ABOVE_INT64),  # decimals from LI.FI, CoinGecko price
    ("0x04", "arbitrum", "2026-10-13 10:45:00Z", WETH_ARBITRUM, 500_000_000_000_000_000),  # checksummed in LI.FI
    ("0x05", "arbitrum", "2026-10-13 10:50:00Z", UNKNOWN_TOKEN, 7),  # nothing prices it
]
SYNTHETIC_PRICES = [("polygon", USDC_POLYGON, "USDC", 6, "2026-10-13 10:00:00Z", 1.0)]
SYNTHETIC_COINGECKO = [
    ("polygon", USDC_POLYGON, "2026-10-13 10:00:00+00:00", 0.99),
    ("polygon", USDC_POLYGON, "2026-10-13 11:00:00+00:00", 0.98),
    ("polygon", NATIVE, "2026-10-13 10:00:00+00:00", 0.1),
    ("arbitrum", WETH_ARBITRUM, "2026-10-13 10:00:00+00:00", 2000.0),
]
# (chainId, address, symbol, decimals); the WETH address on chain 1 must not match the arbitrum row.
SYNTHETIC_TOKENS = [
    (137, NATIVE, "POL", 18),
    (137, USDC_POLYGON, "USDC-lifi", 9),
    (42161, WETH_ARBITRUM_CHECKSUMMED, "WETH", 18),
    (1, WETH_ARBITRUM_CHECKSUMMED, "OTHER", 6),
]


def write_csv(path: Path, header: list[str], rows: list[tuple]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def write_synthetic_data(data: Path, reference: Path, without: str | None = None) -> None:
    """The two provided CSVs into `data` and the two pricing snapshots into `reference`, in their real
    formats; `without` names a file left out."""
    transfers = []
    for i, (tx_hash, chain, block_time, asset, amount) in enumerate(SYNTHETIC_TRANSFERS):
        bridge_data = {
            "transactionId": f"0xid{i}",
            "bridge": "across",
            "integrator": "test",
            "referrer": NATIVE,
            "sendingAssetId": asset,
            "receiver": "0xreceiver",
            "minAmount": amount,
            "destinationChainId": 1,
            "hasSourceSwaps": False,
            "hasDestinationCall": False,
        }
        transfers.append((chain, block_time, 100 + i, tx_hash, i, "0xdiamond", "0xsender", json.dumps(bridge_data)))
    files = {
        data / paths.TRANSFERS_FILE: (
            ["chain", "block_time", "block_number", "tx_hash", "log_index", "contract_address", "tx_from", "bridge_data"],
            transfers,
        ),
        data / paths.PRICES_FILE: (load.PRICE_COLUMNS, SYNTHETIC_PRICES),
        reference / paths.COINGECKO_PRICES_FILE: (
            ["chain", "token_address", "hour", "price_usd", "n_points"],
            [row + (1,) for row in SYNTHETIC_COINGECKO],
        ),
        reference / paths.LIFI_TOKENS_FILE: (["chainId", "address", "symbol", "decimals"], SYNTHETIC_TOKENS),
    }
    for path, (header, rows) in files.items():
        if path.name != without:
            write_csv(path, header, rows)


def test_fill_policy_on_synthetic_data(tmp_path):
    data, reference = tmp_path / "data", tmp_path / "reference"
    write_synthetic_data(data, reference)
    target = tmp_path / "synthetic.duckdb"
    build(target, data, reference=reference, out=None)
    con = duckdb.connect(str(target), read_only=True)
    try:
        rows = con.execute(
            "SELECT tx_hash, symbol, decimals, decimals_source, price_usd_provided, price_usd_coingecko, "
            "price_usd, price_source, amount_token, amount_usd_provided, amount_usd "
            "FROM transfers_priced ORDER BY tx_hash"
        ).fetchall()
    finally:
        con.close()
    native_tokens = notebook_amount_token(ABOVE_INT64, 18)
    assert native_tokens != float(ABOVE_INT64) / 1e18  # the float route would give a different value
    assert rows == [
        ("0x01", "USDC", 6, "provided", 1.0, 0.99, 1.0, "provided", 2.5, 2.5, 2.5),
        ("0x02", "USDC", 6, "provided", None, 0.98, 0.98, "coingecko", 1.0, None, 0.98),
        ("0x03", "POL", 18, "lifi", None, 0.1, 0.1, "coingecko", native_tokens, None, native_tokens * 0.1),
        ("0x04", "WETH", 18, "lifi", None, 2000.0, 2000.0, "coingecko", 0.5, None, 1000.0),
        ("0x05", None, None, None, None, None, None, None, None, None, None),
    ]


@pytest.mark.parametrize("snapshot", paths.PRICING_SNAPSHOTS)
def test_build_stops_when_a_pricing_snapshot_is_missing(tmp_path, snapshot):
    data, reference = tmp_path / "data", tmp_path / "reference"
    write_synthetic_data(data, reference, without=snapshot)
    target = tmp_path / "existing.duckdb"
    target.write_bytes(b"an existing database")
    with pytest.raises(load.MissingReferenceSnapshot) as info:
        build(target, data, reference=reference, out=None)
    message = str(info.value)
    assert f"{snapshot} is missing" in message
    assert str(reference / snapshot) in message
    assert f"git checkout -- data/reference/{snapshot}" in message
    assert paths.REFERENCE_README in message
    assert target.read_bytes() == b"an existing database"


def test_build_cli_reports_a_missing_snapshot_without_a_traceback(tmp_path, capsys, monkeypatch):
    data, reference = tmp_path / "data", tmp_path / "reference"
    write_synthetic_data(data, reference, without=paths.COINGECKO_PRICES_FILE)
    # The CLI has no reference option; the test hands main a build that reads the synthetic folder.
    monkeypatch.setattr(build_db, "build", lambda db, directory: build(db, directory, reference=reference))
    target = tmp_path / "never.duckdb"
    assert build_main(["--data-dir", str(data), "--db", str(target)]) == 2
    captured = capsys.readouterr()
    assert f"{paths.COINGECKO_PRICES_FILE} is missing" in captured.err
    assert paths.REFERENCE_README in captured.err
    assert "Traceback" not in captured.err
    assert not target.exists()


def test_build_reads_the_snapshots_from_the_repository_whatever_the_data_directory_holds(tmp_path, monkeypatch):
    # LIFI_DATA_DIR locates the two CSVs only. A reference/ folder beside them, here with
    # synthetic pricing snapshots and a stray file, is ignored; every committed snapshot in the
    # repository's data/reference/ loads as its ref_ table.
    data = tmp_path / "data"
    write_synthetic_data(data, data / paths.REFERENCE_DIR)
    write_csv(data / paths.REFERENCE_DIR / "stray.csv", ["a"], [(1,)])
    monkeypatch.setenv("LIFI_DATA_DIR", str(data))
    target = tmp_path / "synthetic.duckdb"
    assert build_main(["--db", str(target)]) == 0

    committed = paths.REPO_ROOT / "data" / paths.REFERENCE_DIR
    snapshots = load.reference_files()
    assert {p.parent for p in snapshots} == {committed}
    expected = {load.reference_table_name(p): len(load.load_reference(p)) for p in snapshots}
    con = duckdb.connect(str(target), read_only=True)
    try:
        tables = con.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'main'").fetchall()
        found = {
            name: con.execute(f'SELECT count(*) FROM "{name}"').fetchall()[0][0]
            for (name,) in tables
            if name.startswith("ref_")
        }
    finally:
        con.close()
    assert found == expected
    assert "ref_stray" not in found
    assert found[load.reference_table_name(Path(paths.COINGECKO_PRICES_FILE))] != len(SYNTHETIC_COINGECKO)
