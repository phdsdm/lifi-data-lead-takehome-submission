"""Shared fixtures: one database built into a temporary directory per test session.

Without the provided CSVs every test that needs them skips with a
message naming the missing files and where to put them; nothing fails.
"""

from __future__ import annotations

from pathlib import Path

import duckdb
import pandas as pd
import pytest

from lifi import load, paths
from lifi.build_db import build
from lifi.query import to_frame


@pytest.fixture(scope="session")
def data_dir() -> Path:
    """The data directory (LIFI_DATA_DIR or data/), or a skip naming what is missing."""
    missing = load.missing_data_files()
    if missing:
        pytest.skip(
            "data files missing: "
            + ", ".join(str(p) for p in missing)
            + f". Drop the provided CSVs into {paths.data_dir()} (see {paths.README})"
        )
    return paths.data_dir()


@pytest.fixture(scope="session")
def db_path(data_dir: Path, tmp_path_factory: pytest.TempPathFactory) -> Path:
    """A database built once per session into a temporary directory."""
    target = tmp_path_factory.mktemp("lifi") / "lifi.duckdb"
    build(target, data_dir, out=None)
    return target


@pytest.fixture(scope="session")
def con(db_path: Path):
    """A read-only connection to the session database."""
    connection = duckdb.connect(str(db_path), read_only=True)
    yield connection
    connection.close()


@pytest.fixture(scope="session")
def result(con):
    """A function from query name to its output, each query run once per test session."""
    frames: dict[str, pd.DataFrame] = {}

    def run_once(name: str) -> pd.DataFrame:
        if name not in frames:
            # Own cursor, as test_queries.py: an earlier test may leave a result on the shared connection.
            cursor = con.cursor()
            try:
                frames[name] = to_frame(cursor.sql((paths.queries_dir() / f"{name}.sql").read_text(encoding="utf-8")))
            finally:
                cursor.close()
        return frames[name]

    return run_once
