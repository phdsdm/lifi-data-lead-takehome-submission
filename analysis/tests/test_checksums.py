"""SHA-256 checksums of the two provided CSVs.

The recorded values in `lifi.checksums` identify the copies as received, the ones
every pinned figure was computed on; analysis/README.md lists the same values.
A present file that differs is a DataChecksumWarning, never a failure: the
run reports which file differs and by which checksums, and a pinned figure
that then fails has that warning beside it in pytest's warnings summary. Without
the files the first three tests skip, as the other data tests do.

The modified copies below are written to temporary directories; the provided
files are only read.
"""

from __future__ import annotations

import hashlib
import re
import warnings

import duckdb
import pytest

from lifi import build_db, checksums, paths, query
from lifi.checksums import DataChecksumWarning, ProvidedFile

RECORDED = {f.name: f for f in checksums.PROVIDED_FILES}
TABLES = {paths.TRANSFERS_FILE: "transfers", paths.PRICES_FILE: "prices"}
NOT_THE_PROVIDED_FILE = b"chain,token_address,symbol,decimals,hour,price_usd\nbase,0x00,ETH,18,2026-10-13 00:00:00Z,1.0\n"


def with_one_digit_changed(content: bytes) -> bytes:
    """The same bytes with the last ASCII digit replaced by another digit: same size, still valid CSV."""
    position = max(content.rfind(digit) for digit in b"0123456789")
    replacement = b"1" if content[position : position + 1] == b"0" else b"0"
    return content[:position] + replacement + content[position + 1 :]


# --- the provided files (skip without them) --------------------------------------


def test_the_provided_files_match_the_recorded_copy_or_warn(data_dir):
    # A differing copy shows up in the warnings summary, naming the file and both checksums;
    # the test passes either way, so only a pinned figure can fail.
    for mismatch in checksums.warn_on_mismatch(data_dir):
        assert mismatch.path.name in RECORDED


def test_a_matching_file_has_the_recorded_size_and_rows(data_dir, con):
    differing = {m.path.name for m in checksums.mismatches(data_dir)}
    matching = [f for f in checksums.PROVIDED_FILES if f.name not in differing]
    if not matching:
        pytest.skip("neither provided file matches its recorded checksum; see the DataChecksumWarning")
    for recorded in matching:
        path = data_dir / recorded.name
        assert path.stat().st_size == recorded.size_bytes, recorded.name
        # fetchall completes the result; fetchone would leave it open on the shared session connection.
        assert con.execute(f"SELECT count(*) FROM {TABLES[recorded.name]}").fetchall() == [(recorded.rows,)]


def test_a_modified_copy_is_reported_with_both_checksums(data_dir, tmp_path, capsys, monkeypatch):
    copy = tmp_path / paths.PRICES_FILE
    copy.write_bytes(with_one_digit_changed((data_dir / paths.PRICES_FILE).read_bytes()))
    actual = hashlib.sha256(copy.read_bytes()).hexdigest()
    recorded = RECORDED[paths.PRICES_FILE]
    assert actual != recorded.sha256

    with pytest.warns(DataChecksumWarning) as record:
        found = checksums.warn_on_mismatch(tmp_path)
    assert [(m.path, m.expected, m.sha256) for m in found] == [(copy, recorded, actual)]
    assert [str(w.message) for w in record] == [found[0].message]
    for text in (paths.PRICES_FILE, recorded.sha256, actual):
        assert text in found[0].message

    built = []
    monkeypatch.setattr(build_db, "build", lambda db, directory: built.append(directory) or {})
    assert build_db.main(["--data-dir", str(tmp_path), "--db", str(tmp_path / "x.duckdb")]) == 0
    assert built == [tmp_path]
    assert capsys.readouterr().err == f"lifi-build-db: warning: {found[0].message}\n"


# --- the mechanism, on files written here (these run without the provided data) ----


def test_sha256_is_the_hex_digest_shasum_prints(tmp_path):
    sample = tmp_path / "abc.txt"
    sample.write_bytes(b"abc")
    # FIPS 180-2's test vector for "abc".
    assert checksums.sha256(sample) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"


def test_a_differing_file_warns_naming_the_file_and_both_checksums(tmp_path):
    differing = tmp_path / paths.PRICES_FILE
    differing.write_bytes(NOT_THE_PROVIDED_FILE)
    actual = hashlib.sha256(NOT_THE_PROVIDED_FILE).hexdigest()
    recorded = RECORDED[paths.PRICES_FILE]

    with pytest.warns(DataChecksumWarning) as record:
        found = checksums.warn_on_mismatch(tmp_path)

    assert len(found) == 1
    mismatch = found[0]
    assert (mismatch.path, mismatch.expected, mismatch.sha256) == (differing, recorded, actual)
    assert mismatch.size_bytes == len(NOT_THE_PROVIDED_FILE)
    assert mismatch.message.startswith(f"{paths.PRICES_FILE} differs from the copy")
    for text in (recorded.sha256, actual, str(differing), f"{recorded.size_bytes:,} bytes expected", paths.README):
        assert text in mismatch.message
    assert [str(w.message) for w in record] == [mismatch.message]
    assert record[0].filename == __file__  # attributed to the caller, not to lifi/checksums.py


def test_a_matching_file_is_not_reported(tmp_path, monkeypatch, capsys):
    (tmp_path / paths.TRANSFERS_FILE).write_bytes(NOT_THE_PROVIDED_FILE)
    as_recorded = ProvidedFile(
        paths.TRANSFERS_FILE, hashlib.sha256(NOT_THE_PROVIDED_FILE).hexdigest(), len(NOT_THE_PROVIDED_FILE), 1
    )
    monkeypatch.setattr(checksums, "PROVIDED_FILES", (as_recorded,))
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        assert checksums.warn_on_mismatch(tmp_path) == []
    assert checksums.report(tmp_path, prefix="lifi-build-db: ") == []
    assert capsys.readouterr().err == ""


def test_absent_files_are_left_to_missing_data_file(tmp_path):
    assert checksums.mismatches(tmp_path) == []


def test_build_cli_warns_on_a_differing_file_and_builds_anyway(tmp_path, capsys, monkeypatch):
    (tmp_path / paths.TRANSFERS_FILE).write_bytes(NOT_THE_PROVIDED_FILE)
    built = []
    monkeypatch.setattr(build_db, "build", lambda db, directory: built.append((db, directory)) or {})
    target = tmp_path / "lifi.duckdb"
    assert build_db.main(["--data-dir", str(tmp_path), "--db", str(target)]) == 0
    assert built == [(target, tmp_path)]
    err = capsys.readouterr().err
    assert err.startswith(f"lifi-build-db: warning: {paths.TRANSFERS_FILE} differs from the copy")
    assert RECORDED[paths.TRANSFERS_FILE].sha256 in err
    assert hashlib.sha256(NOT_THE_PROVIDED_FILE).hexdigest() in err
    assert "Traceback" not in err


def test_query_warns_before_building_a_missing_database(tmp_path, capsys, monkeypatch):
    (tmp_path / paths.PRICES_FILE).write_bytes(NOT_THE_PROVIDED_FILE)

    def build_empty(target, directory, out):
        duckdb.connect(str(target)).close()

    monkeypatch.setattr(query, "build", build_empty)
    query.connect(tmp_path / "lifi.duckdb", tmp_path).close()
    err = capsys.readouterr().err
    assert err.startswith(f"warning: {paths.PRICES_FILE} differs from the copy")
    assert RECORDED[paths.PRICES_FILE].sha256 in err


def test_readme_lists_the_recorded_checksums_sizes_and_rows():
    readme = (paths.REPO_ROOT / paths.README).read_text(encoding="utf-8")
    for recorded in checksums.PROVIDED_FILES:
        rows = [line for line in readme.splitlines() if f"`{recorded.name}`" in line and recorded.sha256 in line]
        assert len(rows) == 1, f"{paths.README} has no single table row for {recorded.name} with its SHA-256"
        assert f"{recorded.size_bytes:,}" in rows[0], recorded.name
        assert f"{recorded.rows:,}" in rows[0], recorded.name
    # No other SHA-256 anywhere in the README, so a stale value cannot survive beside the current one.
    assert set(re.findall(r"\b[0-9a-f]{64}\b", readme)) == {f.sha256 for f in checksums.PROVIDED_FILES}
    assert "shasum -a 256" in readme
