"""Run a named query against the database file: `uv run lifi-query <name>`.

`<name>` is the stem of `analysis/queries/<name>.sql`, or a path to any .sql
file. The result prints as a table, or as CSV with `--csv`; `--db` points at
another database file. When the file is missing it is built first (the
summary goes to stderr so `--csv` output stays clean).

From a notebook: `from lifi.query import run` then `run("65_started_volume")`
gives the result as a DataFrame; `run_sql("select ...")` runs inline SQL.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import duckdb
import pandas as pd

from lifi import checksums, paths
from lifi.build_db import build
from lifi.load import MissingDataFile

EXACT_INTEGER_TYPES = {"HUGEINT", "UHUGEINT"}


class QueryNotFound(FileNotFoundError):
    """No query file matches the name given; the message says where one was expected."""


def resolve_query(name: str | os.PathLike[str]) -> Path:
    """The .sql file for `name`: a path that exists, else analysis/queries/<name>.sql."""
    given = Path(name)
    if given.is_file():
        return given
    stem = given.name[:-4] if given.name.endswith(".sql") else given.name
    candidate = paths.queries_dir() / f"{stem}.sql"
    if candidate.is_file():
        return candidate
    available = sorted(p.stem for p in paths.queries_dir().glob("*.sql"))
    listing = ", ".join(available) if available else "none yet"
    raise QueryNotFound(f"no query named {name!r}: expected {candidate} (available: {listing})")


def connect(
    db: str | os.PathLike[str] | None = None,
    directory: str | os.PathLike[str] | None = None,
) -> duckdb.DuckDBPyConnection:
    """A read-only connection to the database file, building it first when it is missing.

    Before such a build, a provided CSV that differs from the recorded copy is
    reported on stderr, as `lifi-build-db` does (`lifi.checksums`).
    """
    target = paths.db_path(db)
    if not target.is_file():
        checksums.report(directory, out=sys.stderr)
        build(target, directory, out=sys.stderr)
    return duckdb.connect(str(target), read_only=True)


def to_frame(relation: duckdb.DuckDBPyRelation | None) -> pd.DataFrame:
    """A relation as a DataFrame; HUGEINT columns stay exact Python ints instead of float64."""
    if relation is None:
        return pd.DataFrame()
    if any(str(t) in EXACT_INTEGER_TYPES for t in relation.types):
        return pd.DataFrame.from_records(relation.fetchall(), columns=relation.columns)
    return relation.df()


def run_sql(sql: str, db: str | os.PathLike[str] | None = None) -> pd.DataFrame:
    """Execute `sql` against the database file and return the result."""
    con = connect(db)
    try:
        return to_frame(con.sql(sql))
    finally:
        con.close()


def run(name: str | os.PathLike[str], db: str | os.PathLike[str] | None = None) -> pd.DataFrame:
    """Execute the named query file (stem under analysis/queries/, or a path) and return the result."""
    return run_sql(resolve_query(name).read_text(encoding="utf-8"), db)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="lifi-query",
        description="Run analysis/queries/<name>.sql against the DuckDB file and print the result.",
    )
    parser.add_argument("name", help="query name (file stem under analysis/queries/) or a path to a .sql file")
    parser.add_argument("--csv", action="store_true", help="print CSV instead of a table")
    parser.add_argument("--db", type=Path, help="database file (default: LIFI_DB_PATH or analysis/lifi.duckdb)")
    args = parser.parse_args(argv)
    try:
        frame = run(args.name, args.db)
    except (MissingDataFile, QueryNotFound) as exc:
        print(f"lifi-query: {exc}", file=sys.stderr)
        return 2
    if args.csv:
        frame.to_csv(sys.stdout, index=False)
    else:
        print(frame.to_string(index=False, float_format=lambda x: f"{x:.12g}"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
