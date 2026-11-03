"""Read the provided CSVs into pandas frames.

The files are not committed; a missing one raises `MissingDataFile`
with a message naming the file, where it was expected and the README that
explains where to put it, before pandas or DuckDB ever see the path. The
reference snapshots are committed under data/reference/ and read from
the repository whatever LIFI_DATA_DIR says; one that is absent raises
`MissingReferenceSnapshot`, a `MissingDataFile` whose message says how to
restore it.

`bridge_data` is parsed with `json.loads`, so `minAmount` stays an exact
Python int (14,864 rows exceed int64) and `destinationChainId` an integer.
This is the parsing proven in `analysis/notebooks/00_explore.ipynb` §1.
Timestamps come back as naive UTC (`datetime64[us]`): the files are UTC, and
DuckDB needs `pytz` (not a dependency) to hand tz-aware values back to Python.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

import pandas as pd

from lifi.paths import (
    PRICES_FILE,
    PRICING_SNAPSHOTS,
    README,
    REFERENCE_README,
    REPO_ROOT,
    TRANSFERS_FILE,
    data_dir,
    reference_dir,
)

# Keys of the bridge_data JSON and the snake_case column each becomes.
BRIDGE_DATA_COLUMNS: dict[str, str] = {
    "transactionId": "transaction_id",
    "bridge": "bridge",
    "integrator": "integrator",
    "referrer": "referrer",
    "sendingAssetId": "sending_asset_id",
    "receiver": "receiver",
    "minAmount": "min_amount",
    "destinationChainId": "destination_chain_id",
    "hasSourceSwaps": "has_source_swaps",
    "hasDestinationCall": "has_destination_call",
}

EVENT_COLUMNS = [
    "chain",
    "block_time",
    "block_number",
    "tx_hash",
    "log_index",
    "contract_address",
    "tx_from",
]
TRANSFER_COLUMNS = EVENT_COLUMNS + list(BRIDGE_DATA_COLUMNS.values())
PRICE_COLUMNS = ["chain", "token_address", "symbol", "decimals", "hour", "price_usd"]


class MissingDataFile(FileNotFoundError):
    """A provided data file is absent. The message says which and where to put it."""


class MissingReferenceSnapshot(MissingDataFile):
    """A committed reference snapshot is absent from the repository's data/reference/."""


def require_file(path: Path) -> Path:
    """Return `path` if it is a file, else raise MissingDataFile naming it and the README."""
    if path.is_file():
        return path
    raise MissingDataFile(
        f"{path.name} is missing: expected it at {path}. "
        f"Drop the provided CSV into the data directory "
        f"(LIFI_DATA_DIR, default {REPO_ROOT / 'data'}); see {README}."
    )


def require_snapshot(path: Path) -> Path:
    """Return `path` if it is a file, else raise MissingReferenceSnapshot naming it and where it belongs."""
    if path.is_file():
        return path
    raise MissingReferenceSnapshot(
        f"{path.name} is missing: expected it at {path}. "
        f"It is a reference snapshot committed under data/reference/, read from the repository "
        f"whatever LIFI_DATA_DIR says: restore it with "
        f"`git checkout -- data/reference/{path.name}`; see {REFERENCE_README}."
    )


def pricing_snapshots(reference: str | os.PathLike[str] | None = None) -> list[Path]:
    """The snapshots the headline USD column of transfers_priced reads: the CoinGecko
    hourly prices and LI.FI's token list, in the repository's data/reference/ unless `reference`
    names another folder. Raises MissingReferenceSnapshot for the first one absent."""
    folder = reference_dir(reference)
    return [require_snapshot(folder / name) for name in PRICING_SNAPSHOTS]


def missing_data_files(directory: str | os.PathLike[str] | None = None) -> list[Path]:
    """The provided files that are absent from the data directory; empty when both are there."""
    base = data_dir(directory)
    return [p for p in (base / TRANSFERS_FILE, base / PRICES_FILE) if not p.is_file()]


def load_transfers(directory: str | os.PathLike[str] | None = None) -> pd.DataFrame:
    """transfers_started.csv with bridge_data parsed into typed columns.

    Columns, in order: chain, block_time (naive UTC), block_number, tx_hash,
    log_index, contract_address, tx_from, then the ten bridge_data keys in
    snake_case. `min_amount` is an object column of exact Python ints.
    """
    path = require_file(data_dir(directory) / TRANSFERS_FILE)
    raw = pd.read_csv(path)
    # json.loads keeps minAmount an exact int; pandas' own JSON path would go through float64.
    bridge = pd.DataFrame([json.loads(s) for s in raw["bridge_data"]])
    frame = pd.concat([raw.drop(columns="bridge_data"), bridge], axis=1)
    frame = frame.rename(columns=BRIDGE_DATA_COLUMNS)
    frame["block_time"] = pd.to_datetime(frame["block_time"], utc=True).dt.tz_convert(None)
    return frame[TRANSFER_COLUMNS]


def load_prices(directory: str | os.PathLike[str] | None = None) -> pd.DataFrame:
    """prices.csv: chain, token_address, symbol, decimals, hour (naive UTC), price_usd."""
    path = require_file(data_dir(directory) / PRICES_FILE)
    frame = pd.read_csv(path)
    frame["hour"] = pd.to_datetime(frame["hour"], utc=True).dt.tz_convert(None)
    return frame[PRICE_COLUMNS]


def reference_files(reference: str | os.PathLike[str] | None = None) -> list[Path]:
    """Every CSV snapshot in the repository's data/reference/, or in `reference` when
    given, sorted; empty when the folder is absent."""
    folder = reference_dir(reference)
    return sorted(folder.glob("*.csv")) if folder.is_dir() else []


def reference_table_name(path: Path) -> str:
    """`ref_<file stem>`, with anything that is not a letter, digit or underscore replaced by `_`."""
    return "ref_" + re.sub(r"[^0-9A-Za-z_]+", "_", path.stem)


def load_reference(path: Path) -> pd.DataFrame:
    """A reference snapshot as pandas reads it: all columns, types inferred, no schema assumed,
    except that an integer column with a missing value stays an integer column.

    pandas reads such a column as float64, which DuckDB stores as DOUBLE
    (`lifi_chain_id_registry.csv` `api_chain_id`, empty for Aptos). A float64
    column with a missing value whose every non-empty cell is an integer
    literal in the file becomes nullable Int64 (DuckDB BIGINT with NULL),
    converted from the file's text so ids above 2^53 stay exact. A cell
    written as `1.0` is a float in the file and keeps the float type.
    """
    frame = pd.read_csv(require_snapshot(path))
    gapped = [c for c in frame.columns if frame[c].dtype.kind == "f" and frame[c].isna().any()]
    if gapped:
        text = pd.read_csv(path, usecols=gapped, dtype=str)
        for column in gapped:
            integers = integer_column(text[column])
            if integers is not None:
                frame[column] = integers
    return frame


INT64_MIN, INT64_MAX = -(2**63), 2**63 - 1


def integer_column(text: pd.Series) -> pd.api.extensions.ExtensionArray | None:
    """Nullable Int64 from a column read as text, or None unless every non-empty cell is an int64 literal."""
    present = text.dropna()
    if present.empty or not present.str.fullmatch(r"[+-]?\d+").all():
        return None
    values = [int(v) if isinstance(v, str) else None for v in text]
    if any(v is not None and not INT64_MIN <= v <= INT64_MAX for v in values):
        return None
    return pd.array(values, dtype="Int64")
