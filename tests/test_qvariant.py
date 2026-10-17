"""Tests for scripts/qvariant.sh against stub Quartus tools."""

# pylint: disable=missing-function-docstring

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "qvariant.sh"

# Each stub tool logs its argv and environment, then writes its summary,
# or exits with STUB_RC_<tool> when set.
TOOL = r"""#!/usr/bin/env bash
t=${0##*/}
printf '%s %s 64=%s preload=%s\n' "$t" "$*" "$QUARTUS_64BIT" "${LD_PRELOAD##*/}" >>"$STUB_LOG"
rc_var=STUB_RC_$t
[[ -n ${!rc_var:-} ]] && exit "${!rc_var}"
mkdir -p output_files
echo "$t summary: $(tail -n 1 "$3.qsf")" >"output_files/$3.${t#quartus_}.summary"
"""


@pytest.fixture(name="env")
def fixture_env(tmp_path):
    qbin = tmp_path / "qbin"
    qbin.mkdir()
    for tool in ("quartus_map", "quartus_fit"):
        (qbin / tool).write_text(TOOL)
        (qbin / tool).chmod(0o755)
    proj = tmp_path / "proj"
    for d in ("db", "incremental_db", "output_files"):
        (proj / d).mkdir(parents=True)
        (proj / d / "stale").write_text("x")
    (proj / "top.qsf").write_text("set_global_assignment -name FAMILY X\n")
    (proj / "top.qpf").write_text("")
    (proj / "core.vhd").write_text("")
    (proj / "link.vhd").symlink_to("core.vhd")
    return {
        **os.environ,
        "QUARTUS_BIN": str(qbin),
        "STUB_LOG": str(tmp_path / "log"),
        "TBBSTUB_DIR": str(tmp_path / "stub"),
    }


def run(env, *args):
    return subprocess.run(
        [str(SCRIPT), *args], env=env, capture_output=True, text=True, check=False
    )


def test_map_only_copies_project_and_appends_lines(env, tmp_path):
    res = run(env, str(tmp_path / "proj"), "top", "v1", "line A", "line B")
    assert res.returncode == 0, res.stderr
    dst = tmp_path / "proj_v1"
    assert sorted(p.name for p in dst.iterdir()) == [
        "core.vhd",
        "link.vhd",
        "output_files",
        "quartus_map.log",
        "top.qpf",
        "top.qsf",
    ]
    assert (dst / "link.vhd").is_symlink()
    assert not (dst / "output_files" / "stale").exists()
    assert (dst / "top.qsf").read_text().endswith("FAMILY X\n\nline A\nline B\n")
    assert "quartus_map summary: line B" in res.stdout
    assert "v1 quartus_map: rc=0" in res.stdout
    log = (tmp_path / "log").read_text().splitlines()
    assert log == [
        "quartus_map --read_settings_files=on --write_settings_files=off top -c top"
        " 64=1 preload=libtbbmalloc_proxy.so.2"
    ]


def test_fit_runs_after_map_and_rerun_replaces_variant(env, tmp_path):
    run(env, str(tmp_path / "proj"), "top", "v2", "old")
    res = run(env, "--fit", "5", str(tmp_path / "proj"), "top", "v2", "new")
    assert res.returncode == 0, res.stderr
    assert "quartus_fit summary: new" in res.stdout
    qsf = (tmp_path / "proj_v2" / "top.qsf").read_text()
    assert "old" not in qsf
    tools = [line.split()[0] for line in (tmp_path / "log").read_text().splitlines()]
    assert tools == ["quartus_map", "quartus_map", "quartus_fit"]


def test_failing_stage_returns_its_rc(env, tmp_path):
    env["STUB_RC_quartus_fit"] = "3"
    res = run(env, "--fit", "1", str(tmp_path / "proj"), "top", "v3")
    assert res.returncode == 3
    assert "v3 quartus_fit: rc=3" in res.stdout


@pytest.mark.parametrize(
    "args", [[], ["--fit"], ["dir", "rev"], ["--fit", "1", "dir", "rev"]]
)
def test_usage(env, args):
    res = run(env, *args)
    assert res.returncode == 2 and "qvariant.sh [--fit MINUTES]" in res.stderr


def test_missing_revision(env, tmp_path):
    res = run(env, str(tmp_path / "proj"), "nope", "v4")
    assert res.returncode == 2 and "no nope.qsf" in res.stderr
