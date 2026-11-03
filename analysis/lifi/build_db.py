"""Build the DuckDB file every query reads: `uv run lifi-build-db`.

Deletes the file and rebuilds it in a few seconds from the two provided CSVs,
found in LIFI_DATA_DIR (default data/), and the reference snapshots, always
read from data/reference/ in the repository whatever LIFI_DATA_DIR says:

    transfers         one row per LiFiTransferStarted event, bridge_data as typed
                      columns, min_amount HUGEINT (exact; 14,864 rows exceed int64)
    prices            one row per (chain, token_address, hour)
    ref_<stem>        one table per data/reference/*.csv present, columns as
                      pandas reads them except that an integer column with a
                      missing value stays BIGINT
    transfers_priced  view, one row per transfer, carrying the headline USD
                      column (the policy of notebook 02 §8):
                      price_usd_provided   prices.csv for (chain, sending_asset_id
                                           = token_address, hour of block_time)
                      price_usd_coingecko  the CoinGecko snapshot for the same key
                      price_usd            the provided price, else CoinGecko's
                      price_source         'provided', 'coingecko', or NULL when
                                           neither feed prices the row
                      symbol, decimals     prices.csv for the (chain, token) pair,
                                           else LI.FI's token list for the
                                           source chain's id; decimals_source is
                                           'provided', 'lifi' or NULL
                      amount_token         min_amount / 10^decimals, shifted on
                                           min_amount's exact digits
                      amount_usd           amount_token * price_usd (the headline)
                      amount_usd_provided  amount_token * price_usd_provided
                      A row nothing prices keeps NULLs.

The build needs the two snapshots that view reads (`paths.PRICING_SNAPSHOTS`)
and stops with MissingReferenceSnapshot when one is absent, so `amount_usd`
can never quietly fall back to the provided feed alone.

Before building, `lifi-build-db` checks the two CSVs against their recorded
SHA-256 checksums (`lifi.checksums`) and prints a warning to stderr for each
that differs, naming the file and both checksums; the build goes ahead.
`build()` itself does not check, so the tests' synthetic data builds silently.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import TextIO

import duckdb

from lifi import checksums, paths
from lifi.load import (
    MissingDataFile,
    load_prices,
    load_reference,
    load_transfers,
    pricing_snapshots,
    reference_files,
    reference_table_name,
)

TRANSFERS_DDL = """
CREATE TABLE transfers (
    chain                VARCHAR,
    block_time           TIMESTAMP,   -- UTC
    block_number         BIGINT,
    tx_hash              VARCHAR,
    log_index            BIGINT,
    contract_address     VARCHAR,
    tx_from              VARCHAR,
    transaction_id       VARCHAR,
    bridge               VARCHAR,
    integrator           VARCHAR,
    referrer             VARCHAR,
    sending_asset_id     VARCHAR,
    receiver             VARCHAR,
    min_amount           HUGEINT,     -- smallest unit, exact; never float
    destination_chain_id BIGINT,
    has_source_swaps     BOOLEAN,
    has_destination_call BOOLEAN
)
"""

TRANSFERS_INSERT = """
INSERT INTO transfers
SELECT chain, block_time, block_number, tx_hash, log_index, contract_address, tx_from,
       transaction_id, bridge, integrator, referrer, sending_asset_id, receiver,
       CAST(min_amount AS HUGEINT), CAST(destination_chain_id AS BIGINT),
       has_source_swaps, has_destination_call
FROM transfers_df
"""

PRICES_DDL = """
CREATE TABLE prices (
    chain         VARCHAR,
    token_address VARCHAR,
    symbol        VARCHAR,
    decimals      BIGINT,
    hour          TIMESTAMP,   -- UTC, start of hour
    price_usd     DOUBLE
)
"""

PRICES_INSERT = """
INSERT INTO prices
SELECT chain, token_address, symbol, CAST(decimals AS BIGINT), hour, CAST(price_usd AS DOUBLE)
FROM prices_df
"""

# The data names source chains; LI.FI's token list keys them by chain id. The
# same map as notebook 02 §1, checked against lifi_api_chains.csv in 01 §2.
SOURCE_CHAIN_IDS = {"ethereum": 1, "optimism": 10, "bnb": 56, "polygon": 137, "base": 8453, "arbitrum": 42161}

TRANSFERS_PRICED_DDL = """
CREATE VIEW transfers_priced AS
WITH source_chains (chain, chain_id) AS (
    VALUES {source_chains}
),
provided_tokens AS (            -- one symbol and one decimals per (chain, token) in prices.csv
    SELECT DISTINCT chain, token_address, symbol, decimals FROM prices
),
lifi_tokens AS (                -- addresses are checksummed in the token list, lowercase in the data
    SELECT chainId AS chain_id, lower(address) AS token_address, symbol, decimals
    FROM {lifi_tokens}
),
coingecko AS (                  -- hour is text ending in +00:00; another offset fails the parse
    SELECT chain, token_address, strptime(hour, '%Y-%m-%d %H:%M:%S+00:00') AS hour, price_usd
    FROM {coingecko_prices}
),
joined AS (
    SELECT t.*,
           date_trunc('hour', t.block_time)        AS hour,
           coalesce(pt.symbol, lt.symbol)          AS symbol,
           coalesce(pt.decimals, lt.decimals)      AS decimals,
           CASE WHEN pt.decimals IS NOT NULL THEN 'provided'
                WHEN lt.decimals IS NOT NULL THEN 'lifi' END AS decimals_source,
           p.price_usd                             AS price_usd_provided,
           cg.price_usd                            AS price_usd_coingecko
    FROM transfers t
    LEFT JOIN prices p
           ON p.chain = t.chain
          AND p.token_address = t.sending_asset_id
          AND p.hour = date_trunc('hour', t.block_time)
    LEFT JOIN coingecko cg
           ON cg.chain = t.chain
          AND cg.token_address = t.sending_asset_id
          AND cg.hour = date_trunc('hour', t.block_time)
    LEFT JOIN provided_tokens pt
           ON pt.chain = t.chain
          AND pt.token_address = t.sending_asset_id
    LEFT JOIN source_chains sc
           ON sc.chain = t.chain
    LEFT JOIN lifi_tokens lt
           ON lt.chain_id = sc.chain_id
          AND lt.token_address = t.sending_asset_id
),
headline AS (
    SELECT *,
           coalesce(price_usd_provided, price_usd_coingecko) AS price_usd,
           CASE WHEN price_usd_provided IS NOT NULL THEN 'provided'
                WHEN price_usd_coingecko IS NOT NULL THEN 'coingecko' END AS price_source,
           -- The decimal shift on min_amount's exact digits: '<min_amount>e-<decimals>' read as
           -- DOUBLE is one correctly rounded conversion, the value of
           -- float(Decimal(min_amount) / 10**decimals) in the notebooks. min_amount never
           -- passes through a float first (HUGEINT / power(10, d) would round it to 53 bits).
           CAST(CAST(min_amount AS VARCHAR) || 'e-' || CAST(decimals AS VARCHAR) AS DOUBLE) AS amount_token
    FROM joined
)
SELECT *,
       amount_token * price_usd_provided AS amount_usd_provided,
       amount_token * price_usd          AS amount_usd
FROM headline
"""


def transfers_priced_ddl() -> str:
    """The view's DDL with the source-chain map and the two snapshot table names filled in."""
    return TRANSFERS_PRICED_DDL.format(
        source_chains=", ".join(f"('{chain}', {chain_id})" for chain, chain_id in SOURCE_CHAIN_IDS.items()),
        coingecko_prices=reference_table_name(Path(paths.COINGECKO_PRICES_FILE)),
        lifi_tokens=reference_table_name(Path(paths.LIFI_TOKENS_FILE)),
    )


def build(
    db: str | os.PathLike[str] | None = None,
    directory: str | os.PathLike[str] | None = None,
    *,
    reference: str | os.PathLike[str] | None = None,
    out: TextIO | None = sys.stdout,
) -> dict[str, int]:
    """Create the database file from scratch; return {table or view: row count}.

    `db` and `directory` override LIFI_DB_PATH and LIFI_DATA_DIR; `directory`
    needs only the two provided CSVs. The snapshots come from the repository's
    data/reference/; `reference` names another folder, which only the
    tests do. The summary goes to `out` (None for silence). Raises
    MissingDataFile before touching the database when a provided CSV is
    absent, and its subclass MissingReferenceSnapshot when a snapshot
    transfers_priced reads is.
    """
    target = paths.db_path(db)
    # Load everything first so a missing file leaves an existing database untouched.
    transfers = load_transfers(directory)
    prices = load_prices(directory)
    pricing_snapshots(reference)
    references = [(reference_table_name(p), p, load_reference(p)) for p in reference_files(reference)]
    names = [name for name, _, _ in references]
    if len(set(names)) != len(names):
        raise ValueError(f"reference files map to the same table name: {sorted(names)}")

    target.parent.mkdir(parents=True, exist_ok=True)
    for stale in (target, target.with_name(target.name + ".wal")):
        stale.unlink(missing_ok=True)

    con = duckdb.connect(str(target))
    try:
        con.register("transfers_df", transfers)
        con.execute(TRANSFERS_DDL)
        con.execute(TRANSFERS_INSERT)
        con.unregister("transfers_df")
        con.register("prices_df", prices)
        con.execute(PRICES_DDL)
        con.execute(PRICES_INSERT)
        con.unregister("prices_df")
        for name, _, frame in references:
            con.register("reference_df", frame)
            con.execute(f'CREATE TABLE "{name}" AS SELECT * FROM reference_df')
            con.unregister("reference_df")
        con.execute(transfers_priced_ddl())
        counts = row_counts(con)
    finally:
        con.close()

    if out is not None:
        print(summary(target, paths.data_dir(directory), paths.reference_dir(reference), counts), file=out)
    return counts


def row_counts(con: duckdb.DuckDBPyConnection) -> dict[str, int]:
    """Row count of every table and view in the main schema: the two provided tables, then ref_*, then views."""
    rows = con.execute(
        "SELECT table_name, table_type FROM information_schema.tables "
        "WHERE table_schema = 'main' "
        "ORDER BY table_type, table_name NOT IN ('transfers', 'prices'), table_name <> 'transfers', table_name"
    ).fetchall()
    return {name: con.execute(f'SELECT count(*) FROM "{name}"').fetchone()[0] for name, _ in rows}


def summary(target: Path, source: Path, reference: Path, counts: dict[str, int]) -> str:
    width = max(len(name) for name in counts)
    lines = [f"{target} built from the CSVs in {source} and the snapshots in {reference}"]
    lines += [f"  {name:<{width}}  {n:>10,} rows" for name, n in counts.items()]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="lifi-build-db",
        description="Rebuild analysis/lifi.duckdb from the provided CSVs and the reference snapshots.",
    )
    parser.add_argument("--db", type=Path, help="database file to write (default: LIFI_DB_PATH or analysis/lifi.duckdb)")
    parser.add_argument(
        "--data-dir",
        type=Path,
        help="directory holding the two provided CSVs (default: LIFI_DATA_DIR or data/); "
        "the reference snapshots are always read from data/reference/ in the repository",
    )
    args = parser.parse_args(argv)
    # A copy that differs from the recorded one is reported, not refused.
    checksums.report(args.data_dir, prefix="lifi-build-db: ", out=sys.stderr)
    try:
        build(args.db, args.data_dir)
    except MissingDataFile as exc:
        print(f"lifi-build-db: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
