"""Tests for scripts/build_acex.sh against a stub docker (no image is built)."""

# pylint: disable=missing-function-docstring

import hashlib
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "build_acex.sh"
TAG = hashlib.sha256(
    (ROOT / "docker/quartus90/Dockerfile").read_bytes()
    + (ROOT / "scripts/isx_unpack.py").read_bytes()
).hexdigest()[:12]
IMAGE = f"c0neify/quartus90:{TAG}"

# The "run" branch fakes Quartus outputs for the revision ($9) unless STUB_FAIL.
DOCKER = r"""#!/usr/bin/env bash
a="$*"
printf '%s\n' "${a//$'\n'/;}" >>"$STUB_LOG"
case $1 in
image) exit "$STUB_INSPECT" ;;
build) exit 0 ;;
run)
	d=$(mktemp -d)
	tar -C "$d" -x
	ls "$d" >"$STUB_LOG.in"
	rev=$9
	printf 'Fitter Status : Successful\nTotal logic elements : 7\nTiming Models : Final\n' >"$d/$rev.fit.summary"
	if [[ -n $STUB_FAIL ]]; then tar -C "$d" -c .; exit 1; fi
	printf 'RBF' >"$d/$rev.rbf"
	printf 'Type : Worst-case tsu\nSlack : 1.0 ns\n' >"$d/$rev.tan.summary"
	tar -C "$d" -c .
	;;
esac
"""


@pytest.fixture(name="env")
def fixture_env(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    (bindir / "docker").write_text(DOCKER)
    (bindir / "docker").chmod(0o755)
    (tmp_path / "ref").mkdir()
    proj = tmp_path / "proj"
    (proj / "db").mkdir(parents=True)
    (proj / "db" / "stale.cdb").write_text("x")
    (proj / "top.qsf").write_text("set_global_assignment -name FAMILY ACEX1K\n")
    (proj / "top.vhd").write_text("-- design\n")
    return {
        **os.environ,
        "PATH": f"{bindir}:{os.environ['PATH']}",
        "REFERENCE_DIR": str(tmp_path / "ref"),
        "STUB_LOG": str(tmp_path / "docker.log"),
        "STUB_INSPECT": "0",
    }


def run(env, *args):
    return subprocess.run(
        [str(SCRIPT), *map(str, args)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def calls(env):
    log = Path(env["STUB_LOG"])
    return log.read_text(encoding="utf-8").splitlines() if log.exists() else []


@pytest.mark.parametrize(
    "args",
    [
        (),
        ("proj",),
        ("a", "b", "c"),
        ("--image-only", "proj"),
        ("--bogus",),
    ],
)
def test_usage(env, args):
    res = run(env, *args)
    assert res.returncode == 2 and "Usage" in res.stderr
    assert not calls(env)


def test_option_needs_value(env):
    res = run(env, "--compare")
    assert res.returncode == 1 and "--compare needs FILE" in res.stderr


def test_missing_qsf(env, tmp_path):
    res = run(env, tmp_path / "proj", "other")
    assert res.returncode == 1 and "no other.qsf" in res.stderr
    assert not calls(env)


def test_compile_into_out(env, tmp_path):
    out = tmp_path / "out"
    out.mkdir()
    (out / "top.tan.summary").write_text("Slack : stale\n")
    ref = tmp_path / "ref.rbf"
    ref.write_bytes(b"RXFZ")
    res = run(env, "--out", out, "--compare", ref, tmp_path / "proj", "top")
    assert res.returncode == 0, res.stderr
    assert calls(env)[0] == f"image inspect {IMAGE}"
    assert calls(env)[1].startswith(f"run -i --rm {IMAGE} sh -c ")
    assert calls(env)[1].endswith(" sh top map fit asm tan")
    assert Path(env["STUB_LOG"] + ".in").read_text(encoding="utf-8").split() == [
        "top.qsf",
        "top.vhd",
    ]
    assert (out / "top.rbf").read_bytes() == b"RBF"
    assert "Total logic elements : 7" in res.stdout
    assert "Slack : 1.0 ns" in res.stdout and "stale" not in res.stdout
    assert "Timing Models" not in res.stdout
    assert f"{out}/top.rbf: 3 bytes" in res.stdout
    assert f"vs {ref} (4 bytes): 1 bytes differ" in res.stdout


def test_failed_compile_leaves_no_stale_image(env, tmp_path):
    proj = tmp_path / "proj"
    (proj / "top.rbf").write_bytes(b"OLD")
    res = run({**env, "STUB_FAIL": "1"}, proj, "top")
    assert res.returncode == 1
    assert not (proj / "top.rbf").exists()
    assert "Total logic elements : 7" in res.stdout and "bytes" not in res.stdout


def test_image_build_needs_installer(env):
    res = run({**env, "STUB_INSPECT": "1"}, "--image-only")
    assert res.returncode == 1 and "90_quartus_free.exe" in res.stderr
    assert calls(env) == [f"image inspect {IMAGE}"]


def test_image_build_from_symlinked_installer(env, tmp_path):
    dist = tmp_path / "dist"
    dist.mkdir()
    (dist / "q90.exe").write_bytes(b"MZ\x90\x00")
    (tmp_path / "ref" / "90_quartus_free.exe").symlink_to(dist / "q90.exe")
    res = run(env, "--image-only", "--rebuild-image")
    assert res.returncode == 0, res.stderr
    (build,) = calls(env)
    assert build.startswith("build --progress=plain -f ")
    assert f"--build-context installer={dist} " in build
    assert "--build-arg INSTALLER=q90.exe " in build
    assert build.endswith(f"-t {IMAGE} {ROOT}")
