"""Provenance and licence checks for third_party/."""

# pylint: disable=missing-function-docstring

import hashlib
import re
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TP = ROOT / "third_party"
ROWS = re.findall(
    r"^\| `([^`]+)/` \| `([^`]+\.zip)`[^|]*\| `([0-9a-f]{64})` \|",
    (TP / "README.md").read_text(),
    re.M,
)
GRANT = re.compile(r"General Public License|Altera Corporation")
CLAIM = re.compile(r"copyright|\(c\)", re.I)


def files(d):
    return sorted(p for p in (TP / d).rglob("*") if p.is_file())


def test_readme_lists_every_directory():
    assert sorted(r[0] for r in ROWS) == sorted(
        p.name for p in TP.iterdir() if p.is_dir()
    )


@pytest.mark.parametrize("d,_zip,_sha", ROWS)
def test_licence_texts_shipped(d, _zip, _sha):
    names = {p.name for p in files(d)}
    assert "gpl.txt" in names or "lgpl.txt" in names


@pytest.mark.parametrize("d,_zip,_sha", ROWS)
def test_every_claimed_file_grants_gpl_or_is_tool_output(d, _zip, _sha):
    for p in files(d):
        if p.suffix in (".txt", ".rbf", ".hex"):
            continue
        head = p.read_bytes()[:3000].decode("latin-1")
        assert not CLAIM.search(head) or GRANT.search(head), p


@pytest.mark.parametrize("d,archive,sha", ROWS)
def test_files_match_archive(d, archive, sha):
    z = ROOT / "reference" / archive
    if not z.is_file():
        pytest.skip(f"reference/{archive} absent")
    assert hashlib.sha256(z.read_bytes()).hexdigest() == sha
    with zipfile.ZipFile(z) as zf:
        for p in files(d):
            assert zf.read(p.relative_to(TP / d).as_posix()) == p.read_bytes(), p
