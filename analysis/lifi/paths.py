"""Where the provided CSVs, the reference snapshots, the database file and the
query files live.

The two provided CSVs and the database file can each be moved by an environment
variable, so a clone whose CSVs sit elsewhere, or a test building into a
temporary directory, needs no code change:

    LIFI_DATA_DIR   directory holding transfers_started.csv and prices.csv;
                    default <repo root>/data. Only those two files are
                    read from it
    LIFI_DB_PATH    the DuckDB file lifi-build-db writes and lifi-query reads;
                    default <repo root>/analysis/lifi.duckdb (gitignored)

The reference snapshots are committed, and the build always reads them from
<repo root>/data/reference/, whatever LIFI_DATA_DIR says: a copy outside
the repository could drift from the committed files unnoticed. No environment
variable moves them; only the tests point the build at another folder, through
the `reference` argument of `lifi.build_db.build`.

The repository root is found from this file, which works because uv installs
the package in editable mode (`uv sync`).
"""

from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
README = "analysis/README.md"

TRANSFERS_FILE = "transfers_started.csv"
PRICES_FILE = "prices.csv"
REFERENCE_DIR = "reference"
REFERENCE_README = "data/reference/README.md"

# The two reference snapshots the headline USD column of transfers_priced reads.
COINGECKO_PRICES_FILE = "coingecko_hourly_prices_2026-10-13_to_2026-10-19.csv"
LIFI_TOKENS_FILE = "lifi_api_tokens_by_chain.csv"
PRICING_SNAPSHOTS = (COINGECKO_PRICES_FILE, LIFI_TOKENS_FILE)


def data_dir(override: str | os.PathLike[str] | None = None) -> Path:
    """The data directory: an explicit override, else LIFI_DATA_DIR, else <repo>/data."""
    if override is not None:
        return Path(override)
    env = os.environ.get("LIFI_DATA_DIR")
    return Path(env) if env else REPO_ROOT / "data"


def reference_dir(override: str | os.PathLike[str] | None = None) -> Path:
    """The reference snapshots: an explicit override (the tests' synthetic folders), else
    <repo>/data/reference. LIFI_DATA_DIR does not move them."""
    if override is not None:
        return Path(override)
    return REPO_ROOT / "data" / REFERENCE_DIR


def db_path(override: str | os.PathLike[str] | None = None) -> Path:
    """The DuckDB file: an explicit override, else LIFI_DB_PATH, else analysis/lifi.duckdb."""
    if override is not None:
        return Path(override)
    env = os.environ.get("LIFI_DB_PATH")
    return Path(env) if env else REPO_ROOT / "analysis" / "lifi.duckdb"


def queries_dir() -> Path:
    """The named queries, `analysis/queries/<name>.sql`."""
    return REPO_ROOT / "analysis" / "queries"
