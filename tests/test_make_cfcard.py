"""Tests for scripts/make_cfcard.sh."""

# pylint: disable=missing-function-docstring

import subprocess
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "make_cfcard.sh"
ZIP = "C1minimigV201_build.zip"
TRIO = ("support.rbf", "support.bin", "target.rbf")


def run(*args):
    return subprocess.run(
        [str(SCRIPT), *map(str, args)], capture_output=True, text=True, check=False
    )


def make_zip(ref, members):
    ref.mkdir(exist_ok=True)
    with zipfile.ZipFile(ref / ZIP, "w") as z:
        for name, data in members.items():
            z.writestr(name, data)


def table(stdout):
    return {
        f[0]: (f[1], f[2])
        for f in (line.split(maxsplit=2) for line in stdout.splitlines()[1:])
        if len(f) == 3 and f[1] in ("copied", "placeholder")
    }


def listing(core_dir):
    return {p.name: p.read_bytes() for p in core_dir.iterdir()}


@pytest.fixture(name="paths")
def fixture_paths(tmp_path):
    rbf = tmp_path / "core.rbf"
    rbf.write_bytes(b"EXT")
    return tmp_path / "ref", rbf, tmp_path / "out"


def base(paths, *extra):
    ref, rbf, out = paths
    return run("--core", "bbc", "--rbf", rbf, "--out", out, "--reference", ref, *extra)


def test_full_card_from_zip(paths, tmp_path):
    ref, _, out = paths
    make_zip(
        ref,
        {
            "build/1k100/SUPPORT.RBF": b"SR",
            "build/1k30/Support.bin": b"SB",
            "build/target.rbf": b"TR",
            "build/readme.txt": b"x",
        },
    )
    icon = tmp_path / "icon.raw"
    icon.write_bytes(b"ICON")
    rom = tmp_path / "roms" / "os12.rom"
    rom.parent.mkdir()
    rom.write_bytes(b"ROM")
    res = base(paths, "--icon", icon, "--rom", rom, "--strict")
    assert res.returncode == 0, res.stderr
    assert listing(out / "c1dcores" / "bbc") == {
        "select.raw": b"ICON",
        "extender.rbf": b"EXT",
        "support.rbf": b"SR",
        "support.bin": b"SB",
        "target.rbf": b"TR",
        "os12.rom": b"ROM",
    }
    got = table(res.stdout)
    assert got["support.rbf"] == ("copied", f"{ZIP}:build/1k100/SUPPORT.RBF")
    assert got["os12.rom"] == ("copied", str(rom))
    assert all(status == "copied" for status, _ in got.values())


def test_placeholders_without_zip(paths):
    _, _, out = paths
    res = base(paths)
    assert res.returncode == 0, res.stderr
    assert listing(out / "c1dcores" / "bbc") == {
        "extender.rbf": b"EXT",
        **{f"{n}.MISSING": b"" for n in ("select.raw", *TRIO)},
    }
    got = table(res.stdout)
    assert got["select.raw"] == ("placeholder", "select.raw.MISSING")
    assert sum(s == "placeholder" for s, _ in got.values()) == 4
    assert base(paths, "--strict").returncode == 3


def test_explicit_overrides_zip_and_replaces_placeholder(paths, tmp_path):
    ref, _, out = paths
    base(paths)
    make_zip(ref, {"support.rbf": b"SR", "support.bin": b"ZIPBIN"})
    sbin = tmp_path / "mine.bin"
    sbin.write_bytes(b"MINE")
    res = base(paths, "--support-bin", sbin)
    assert res.returncode == 0, res.stderr
    files = listing(out / "c1dcores" / "bbc")
    assert files["support.bin"] == b"MINE"
    assert files["support.rbf"] == b"SR"
    assert "support.rbf.MISSING" not in files
    assert "support.bin.MISSING" not in files
    assert files["target.rbf.MISSING"] == b""
    assert table(res.stdout)["support.bin"] == ("copied", str(sbin))


def test_ambiguous_member_fails(paths):
    ref, _, out = paths
    make_zip(ref, {"a/target.rbf": b"1", "b/TARGET.RBF": b"2"})
    res = base(paths)
    assert res.returncode != 0
    assert "a/target.rbf" in res.stderr and "b/TARGET.RBF" in res.stderr
    assert not (out / "c1dcores" / "bbc" / "target.rbf").exists()


def test_errors(paths, tmp_path):
    ref, rbf, out = paths
    missing = run("--core", "bbc", "--rbf", tmp_path / "nope.rbf", "--out", out)
    assert missing.returncode == 1 and "nope.rbf" in missing.stderr
    assert run("--core", "bbc", "--out", out).returncode == 2
    assert run("--core", "bbc", "--rbf", rbf, "--out").returncode == 2
    assert run("--core", "x", "--rbf", rbf, "--out", out, "--bad", "1").returncode == 2
    bad_core = run("--core", "../x", "--rbf", rbf, "--out", out, "--reference", ref)
    assert bad_core.returncode == 1
    assert base(paths, "--rom", tmp_path / "absent.rom").returncode == 1
    assert not out.exists()
