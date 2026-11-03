"""Every analysis/queries/*.sql executes against the database.

One test per query file, so a broken file fails under its own name with
DuckDB's error. The query examples
in analysis/README.md name files that exist, so the README's example runs.
"""

from __future__ import annotations

import re
from pathlib import Path

import duckdb
import pytest

from lifi import paths
from lifi.query import to_frame

QUERY_FILES = sorted(paths.queries_dir().glob("*.sql"))
# `lifi-query <stem>` and `run("<stem>")` as analysis/README.md writes its examples.
README_QUERY_EXAMPLE = re.compile(r'lifi-query ([0-9A-Za-z_]+)|run\("([^"]+)"\)')


@pytest.mark.parametrize(
    "query_file",
    QUERY_FILES or [None],
    ids=lambda p: p.stem if p else "no-query-files-yet",
)
def test_query_file_executes(query_file: Path | None, request: pytest.FixtureRequest):
    if query_file is None:
        return  # no query files
    con = request.getfixturevalue("con")
    sql = query_file.read_text(encoding="utf-8")
    # Own cursor: an earlier test may leave an unfinished result on the shared connection.
    cursor = con.cursor()
    try:
        frame = to_frame(cursor.sql(sql))
    except duckdb.Error as exc:
        pytest.fail(f"{query_file.relative_to(paths.REPO_ROOT)}: {exc}")
    finally:
        cursor.close()
    assert frame is not None


def test_readme_query_examples_name_files_that_exist():
    # Runs without the data; test_query_file_executes above runs each named file with it.
    readme = (paths.REPO_ROOT / paths.README).read_text(encoding="utf-8")
    names = sorted({cli or python for cli, python in README_QUERY_EXAMPLE.findall(readme)})
    assert names, f"{paths.README} shows no query example"
    missing = [name for name in names if not (paths.queries_dir() / f"{name}.sql").is_file()]
    assert missing == [], f"{paths.README} names queries not under analysis/queries/: {missing}"
