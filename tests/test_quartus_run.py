"""Tests for scripts/quartus_run.sh: the preloaded libtbbmalloc_proxy stub."""

# pylint: disable=missing-function-docstring

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "quartus_run.sh"
SONAME = "libtbbmalloc_proxy.so.2"


def run(tmp_path, *cmd, **env):
    full = {**os.environ, "TBBSTUB_DIR": str(tmp_path / "stub"), **env}
    full.pop("LD_PRELOAD", None)
    full.update(env)
    return subprocess.run(
        [str(SCRIPT), *cmd], env=full, capture_output=True, text=True, check=False
    )


def test_usage_without_command(tmp_path):
    res = run(tmp_path)
    assert res.returncode == 2 and "quartus_run.sh CMD" in res.stderr


def test_environment_and_soname(tmp_path):
    res = run(tmp_path, "sh", "-c", 'echo "$QUARTUS_64BIT $LD_PRELOAD"')
    assert res.returncode == 0, res.stderr
    lib = tmp_path / "stub" / SONAME
    assert res.stdout.split() == ["1", str(lib)]
    dyn = subprocess.run(
        ["readelf", "-d", str(lib)], capture_output=True, text=True, check=True
    ).stdout
    assert f"Library soname: [{SONAME}]" in dyn


def test_existing_preload_is_kept_and_stub_not_rebuilt(tmp_path):
    run(tmp_path, "true")
    lib = tmp_path / "stub" / SONAME
    mtime = lib.stat().st_mtime_ns
    res = run(tmp_path, "sh", "-c", 'echo "$LD_PRELOAD"', LD_PRELOAD="/x.so")
    assert res.stdout.strip() == f"{lib}:/x.so"
    assert lib.stat().st_mtime_ns == mtime


def test_stub_satisfies_a_binary_needing_the_proxy(tmp_path):
    run(tmp_path, "true")
    link = tmp_path / "link"
    link.mkdir()
    (link / SONAME).write_bytes((tmp_path / "stub" / SONAME).read_bytes())
    exe = tmp_path / "needs_proxy"
    src = tmp_path / "main.c"
    src.write_text("#include <stdlib.h>\nint main(void){free(malloc(64));return 0;}\n")
    subprocess.run(
        [
            "cc",
            "-o",
            str(exe),
            str(src),
            "-Wl,--no-as-needed",
            f"-L{link}",
            f"-l:{SONAME}",
        ],
        check=True,
    )
    bare = subprocess.run([str(exe)], capture_output=True, text=True, check=False)
    assert bare.returncode != 0 and SONAME in bare.stderr
    assert run(tmp_path, str(exe)).returncode == 0


@pytest.mark.skipif(
    not Path("/opt/altera/13.1/quartus/linux64/quartus_fit").exists(),
    reason="Quartus 13.1 not installed",
)
def test_quartus_fit_runs_64bit_on_the_stub(tmp_path):
    res = run(
        tmp_path,
        "/opt/altera/13.1/quartus/bin/quartus_fit",
        "--version",
        LD_DEBUG="libs",
    )
    assert res.returncode == 0, res.stderr
    assert "64-Bit Fitter" in res.stdout
    assert f"calling init: {tmp_path / 'stub' / SONAME}" in res.stderr
    assert f"linux64/{SONAME}" not in res.stderr
