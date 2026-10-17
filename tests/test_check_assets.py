"""Tests for scripts/check_assets.sh."""

# pylint: disable=missing-function-docstring

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "check_assets.sh"
MANIFEST = [
    line.split("\t")
    for line in (ROOT / "scripts" / "assets.tsv").read_text().splitlines()[1:]
]
NAMES = [row[0] for row in MANIFEST]


def run(ref, *args):
    env = dict(os.environ, REFERENCE_DIR=str(ref))
    return subprocess.run(
        [str(SCRIPT), *args], env=env, capture_output=True, text=True, check=False
    )


def status(stdout):
    return {
        f[3]: (f[0], f[2])
        for f in (line.split() for line in stdout.splitlines())
        if len(f) > 3 and f[0] in ("present", "missing", "invalid")
    }


def test_manifest_covers_expected_assets():
    assert len(NAMES) == len(set(NAMES))
    assert all(len(row) == 5 and all(row) for row in MANIFEST)
    assert {row[1] for row in MANIFEST} <= {"text", "pdf", "zip", "elf", "exe", "deb"}
    assert {row[2] for row in MANIFEST} == {"required", "optional", "vendored"}
    for name in (
        "C1schematics.pdf",
        "C1_extender.pin",
        "C1minimigV201_build.zip",
        "QuartusSetupWeb-13.1.0.162.run",
        "cyclone_web-13.1.0.162.qdz",
        "QuartusSetupWeb-13.0.1.232.run",
        "cyclone_web-13.0.1.232.qdz",
        "90_quartus_free.exe",
    ):
        assert name in NAMES


def test_empty_dir_all_missing(tmp_path):
    res = run(tmp_path)
    assert res.returncode == 0
    assert status(res.stdout) == {n: ("missing", "-") for n in NAMES}
    assert f"0/{len(NAMES)} present" in res.stdout


def test_present_files_report_size(tmp_path):
    (tmp_path / "A1k30.pin").write_bytes(b"x" * 7)
    (tmp_path / "Gbridge.tdf").write_bytes(b"")
    (tmp_path / "unrelated.txt").write_bytes(b"y")
    res = run(tmp_path)
    got = status(res.stdout)
    assert res.returncode == 0
    assert got.pop("A1k30.pin") == ("present", "7")
    assert got.pop("Gbridge.tdf") == ("present", "0")
    assert set(got) == set(NAMES) - {"A1k30.pin", "Gbridge.tdf"}
    assert all(v == ("missing", "-") for v in got.values())
    assert f"2/{len(NAMES)} present" in res.stdout


def test_json(tmp_path):
    (tmp_path / "NewbootV201.zip").write_bytes(b"PK\x03\x04")
    res = run(tmp_path, "--json")
    assert res.returncode == 0
    doc = json.loads(res.stdout)
    assert doc["reference_dir"] == str(tmp_path)
    assert [a["name"] for a in doc["assets"]] == NAMES
    for asset, row in zip(doc["assets"], MANIFEST):
        assert [asset["name"], asset["need"], asset["source"], asset["unblocks"]] == [
            row[0],
            *row[2:],
        ]
        hit = asset["name"] == "NewbootV201.zip"
        assert asset["present"] is hit
        assert asset["size"] == (4 if hit else None)
        assert asset["state"] == ("present" if hit else "missing")


def test_require(tmp_path):
    (tmp_path / "C1_extender.pin").write_text("pins")
    assert run(tmp_path, "--require", "C1_extender.pin").returncode == 0
    res = run(tmp_path, "--require", "C1_extender.pin", "--require", "A1k100.pin")
    assert res.returncode == 1
    assert "A1k100.pin" in res.stderr and "C1_extender.pin" not in res.stderr


def test_usage_errors(tmp_path):
    assert run(tmp_path, "--require").returncode == 2
    assert run(tmp_path, "--bogus").returncode == 2


def test_signatures(tmp_path):
    good = {
        "C1_extender_schem.pdf": b"%PDF-1.3\n",
        "C1minimigV201_build.zip": b"PK\x03\x04rest",
        "QuartusSetupWeb-13.1.0.162.run": b"\x7fELF\x01\x01",
        "libpng12-0_1.2.54-1ubuntu1_i386.deb": b"!<arch>\n",
        "90_quartus_free.exe": b"MZ\x90\x00",
        "C1_extender.pin": b"-- Copyright",
    }
    bad = {
        "NewbootV201.zip": b"<!DOCTYPE html>\n<html>",
        "C1schematics.pdf": b"PK\x03\x04",
        "A1k30.pin": b"<html><body>",
        "cyclone_web-13.1.0.162.qdz": b"%PDF",
    }
    for name, data in {**good, **bad}.items():
        (tmp_path / name).write_bytes(data)
    got = status(run(tmp_path).stdout)
    assert {n for n, v in got.items() if v[0] == "present"} == set(good)
    assert {n for n, v in got.items() if v[0] == "invalid"} == set(bad)
    res = run(tmp_path, "--require", "NewbootV201.zip")
    assert res.returncode == 1 and "missing or invalid" in res.stderr
