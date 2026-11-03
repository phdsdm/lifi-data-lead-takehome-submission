"""The analysis package behind the task documents.

    uv run lifi-build-db          build analysis/lifi.duckdb from the CSVs
    uv run lifi-query <name>      run analysis/queries/<name>.sql against it

In Python: `from lifi import run` gives a named query's result as a DataFrame;
`run_sql` runs inline SQL; `build` rebuilds the file; `connect` opens it read-only.
"""

from lifi.build_db import build
from lifi.load import MissingDataFile
from lifi.query import QueryNotFound, connect, run, run_sql

__all__ = ["MissingDataFile", "QueryNotFound", "build", "connect", "run", "run_sql"]
