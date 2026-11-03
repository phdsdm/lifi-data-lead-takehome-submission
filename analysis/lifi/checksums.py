"""SHA-256 checksums of the two provided CSVs.

The files are not committed, so the checksums are how anyone tells whether
their copy is the one the submission's figures were computed on: the
copies as received from LI.FI. `analysis/README.md` lists the same values,
with the file sizes and row counts; `tests/test_checksums.py` keeps the two in
agreement.

A present file that differs is reported, never refused: `tests/test_checksums.py`
emits a `DataChecksumWarning`, and `lifi-build-db` (and `lifi-query` when it
builds a missing database) prints a warning to stderr before building. Each
names the file and both checksums, and nothing stops. An absent file is not
this module's concern: loading it raises `MissingDataFile` and the tests skip.
"""

from __future__ import annotations

import hashlib
import os
import sys
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

from lifi.paths import PRICES_FILE, README, TRANSFERS_FILE, data_dir


@dataclass(frozen=True)
class ProvidedFile:
    """The recorded copy of one provided CSV: its SHA-256, its size and its data rows (header excluded)."""

    name: str
    sha256: str
    size_bytes: int
    rows: int


PROVIDED_FILES = (
    ProvidedFile(TRANSFERS_FILE, "362b2fe6c8162a83e434e6b17b8669d52b01e265aac490d48cf36c95ec2c2e60", 80_068_219, 124_858),
    ProvidedFile(PRICES_FILE, "cd9aac497bba6bd05ceec8bc16129bc60202c29547475e4024e9730eee58b0c3", 3_939_766, 40_754),
)


class DataChecksumWarning(UserWarning):
    """A provided CSV differs from the copy the submission's figures were computed on."""


@dataclass(frozen=True)
class Mismatch:
    """A present file whose SHA-256 is not the recorded one."""

    path: Path
    expected: ProvidedFile
    sha256: str
    size_bytes: int

    @property
    def message(self) -> str:
        return (
            f"{self.path.name} differs from the copy the submission's figures were computed on: "
            f"SHA-256 expected {self.expected.sha256}, found {self.sha256} "
            f"({self.path}; {self.expected.size_bytes:,} bytes expected, {self.size_bytes:,} found). "
            f"Any change to the content, line endings included, changes the checksum. "
            f"Figures computed from this copy may differ from those the task documents quote, "
            f"and a test that pins one may fail for that reason alone; see {README}."
        )


def sha256(path: str | os.PathLike[str]) -> str:
    """The file's SHA-256 as lowercase hex, the first column `shasum -a 256` prints."""
    with open(path, "rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def mismatches(directory: str | os.PathLike[str] | None = None) -> list[Mismatch]:
    """The provided files present in the data directory whose SHA-256 is not the recorded one.

    An absent file is left out: `missing_data_files` and `MissingDataFile` report those.
    """
    base = data_dir(directory)
    found = []
    for expected in PROVIDED_FILES:
        path = base / expected.name
        if not path.is_file():
            continue
        actual = sha256(path)
        if actual != expected.sha256:
            found.append(Mismatch(path, expected, actual, path.stat().st_size))
    return found


def warn_on_mismatch(directory: str | os.PathLike[str] | None = None) -> list[Mismatch]:
    """Emit one DataChecksumWarning per differing file, attributed to the caller; return the mismatches."""
    found = mismatches(directory)
    for mismatch in found:
        warnings.warn(mismatch.message, DataChecksumWarning, stacklevel=2)
    return found


def report(
    directory: str | os.PathLike[str] | None = None,
    *,
    prefix: str = "",
    out: TextIO | None = None,
) -> list[Mismatch]:
    """Print `<prefix>warning: <message>` for each differing file to `out` (default stderr); return the mismatches."""
    found = mismatches(directory)
    for mismatch in found:
        print(f"{prefix}warning: {mismatch.message}", file=out if out is not None else sys.stderr)
    return found
