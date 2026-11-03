"""Helpers for the tests that pin the figures a task document cites.

Each pin reads one cell of one query's output. Rows are found by their label and never by position, and
a figure the query rounds gets a tolerance of one step of that rounding; counts are exact. The `result`
fixture these tests read from is in conftest.py.
"""

from __future__ import annotations

import pandas as pd
import pytest


def rounded(value: float, places: int):
    """Equal to `value` as a query rounds to `places` decimals. The tolerance is one step of that
    rounding, a little over so a float difference of exactly one step passes: DuckDB's float sums can
    land either side of a rounding boundary between runs (query 158's Trustware-prod-routing does)."""
    return pytest.approx(value, abs=1.01 * 10**-places)


def usd0(value: float):
    """A figure the query rounds to whole dollars."""
    return rounded(value, 0)


def d1(value: float):
    """A figure the query rounds to one decimal: some percentages, seconds and bps."""
    return rounded(value, 1)


def d2(value: float):
    """A figure the query rounds to two decimals: USD to the cent, percentages, some rates."""
    return rounded(value, 2)


def d3(value: float):
    """A rate the query rounds to three decimals."""
    return rounded(value, 3)


def d4(value: float):
    """A share the query rounds to four decimals."""
    return rounded(value, 4)


def pin(query: str, where: dict[str, object], **cells: object) -> list:
    """One test case per cell: the row of `query` that `where` selects, column = expected."""
    label = "-".join(str(value) for value in where.values())
    number = query.split("_", 1)[0]
    return [
        pytest.param(query, where, column, expected, id=f"{number}-{label}-{column}")
        for column, expected in cells.items()
    ]


def row_of(frame: pd.DataFrame, where: dict[str, object]) -> pd.Series:
    """The single row `where` selects; zero or several means a label changed, and says so."""
    selected = frame
    for column, value in where.items():
        selected = selected[selected[column] == value]
    assert len(selected) == 1, f"{where} selects {len(selected)} rows"
    return selected.iloc[0]


def cell(result, query: str, where: dict[str, object], column: str) -> float:
    return float(row_of(result(query), where)[column])
