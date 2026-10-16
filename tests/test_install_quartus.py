"""Tests for scripts/install_quartus.sh (no real installer or apt is run)."""

# pylint: disable=missing-function-docstring

import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "install_quartus.sh"
CMD = re.compile(r"^(?:\[\d+/\d+\] )?\+ (.*)$", re.M)
RUNFILE = "QuartusSetupWeb-13.1.0.162.run"
KEPT = {
    "quartus/bin/quartus_sh",
    "quartus/common/devinfo/cycloneii/d",
    "quartus/common/devinfo/cycloneiii/d",
    "quartus/common/devinfo/cycloneiiils/d",
    "quartus/common/devinfo/cycloneive/d",
    "quartus/common/devinfo/programmer/d",
    "quartus/common/tcl/d",
    "uninstall/d",
}
PRUNED_DIRS = {
    "modelsim_ase",
    "modelsim_ae",
    "nios2eds",
    "docs",
    "quartus/common/help",
    "quartus/common/devinfo/cyclone",
    "quartus/common/devinfo/cyclonev",
    "quartus/common/devinfo/stratixiv",
    "quartus/common/devinfo/arriaii",
    "quartus/common/devinfo/maxii",
    "quartus/common/devinfo/hardcopyiv",
}
PRUNED = {f"{d}/sub/d" for d in PRUNED_DIRS}


def run(*args, ref=None):
    env = dict(os.environ, SUDO="sudo-stub")
    if ref is not None:
        env["REFERENCE_DIR"] = str(ref)
    return subprocess.run(
        [str(SCRIPT), *args], env=env, capture_output=True, text=True, check=False
    )


def make_tree(prefix):
    for rel in KEPT | PRUNED:
        (prefix / rel).parent.mkdir(parents=True, exist_ok=True)
        (prefix / rel).write_text(rel)


def files(prefix):
    return {str(p.relative_to(prefix)) for p in prefix.rglob("*") if p.is_file()}


def commands(stdout):
    return [m[1] for m in CMD.finditer(stdout)]


def test_skips_without_installer(tmp_path):
    res = run(ref=tmp_path)
    assert res.returncode == 0
    assert "installer not present, skipping" in res.stdout
    assert not commands(res.stdout)


def test_dry_run_prints_commands(tmp_path):
    (tmp_path / RUNFILE).write_bytes(b"")
    (tmp_path / "cyclone_web-13.1.0.162.qdz").write_bytes(b"")
    prefix = tmp_path / "opt" / "q"
    res = run("--dry-run", "--reference", str(tmp_path), "--prefix", str(prefix))
    assert res.returncode == 0, res.stderr
    cmds = commands(res.stdout)
    root = "" if os.geteuid() == 0 else "sudo-stub "
    assert cmds[:2] == [
        f"{root}dpkg --add-architecture i386",
        f"{root}env TMPDIR=/var/tmp apt-get update",
    ]
    install = cmds[2].split()
    assert install[install.index("apt-get") + 1 : install.index("libc6:i386")] == [
        "install",
        "-y",
        "--no-install-recommends",
    ]
    assert {"libc6:i386", "libstdc++6:i386", "libgtk2.0-0:i386"} <= set(install)
    run_path = tmp_path / RUNFILE
    stage = re.search(r"staging installer in (\S+)", res.stdout)[1]
    assert cmds[3:6] == [
        f"cp --dereference -- {run_path} {stage}/",
        f"cp --dereference -- {tmp_path / 'cyclone_web-13.1.0.162.qdz'} {stage}/",
        f"chmod +x {stage}/{RUNFILE}",
    ]
    assert cmds[6] == (
        f"{stage}/{RUNFILE} --mode unattended --unattendedmodeui none "
        f"--installdir {prefix} --disable-components "
        "quartus_help,modelsim_ase,modelsim_ae"
    )
    assert cmds[7] == f"{prefix}/quartus/bin/quartus_sh --version"
    assert len(cmds) == 8
    assert "would remove under" in res.stdout
    assert not os.access(run_path, os.X_OK)
    assert not prefix.exists() and not Path(stage).exists()


def test_executable_installer_runs_in_place(tmp_path):
    run_path = tmp_path / RUNFILE
    run_path.write_bytes(b"")
    run_path.chmod(0o755)
    res = run("--dry-run", ref=tmp_path)
    cmds = commands(res.stdout)
    assert "staging" not in res.stdout and not any(c.startswith("cp ") for c in cmds)
    assert any(f"{run_path} --mode unattended" in c for c in cmds)


def test_prune_only(tmp_path):
    make_tree(tmp_path)
    res = run("--prune-only", "--prefix", str(tmp_path))
    assert res.returncode == 0, res.stderr
    assert files(tmp_path) == KEPT
    assert not (tmp_path / "modelsim_ase").exists()
    assert "size before:" in res.stdout and "size after:" in res.stdout
    assert f"[{len(PRUNED_DIRS)}/{len(PRUNED_DIRS)}]" in res.stdout
    assert not any(c.startswith("sudo-stub") for c in commands(res.stdout))


def test_prune_dry_run_lists_without_deleting(tmp_path):
    make_tree(tmp_path)
    res = run("--prune-only", "--dry-run", "--prefix", str(tmp_path))
    assert res.returncode == 0, res.stderr
    assert files(tmp_path) == KEPT | PRUNED
    removed = {c.split(" -- ", 1)[1] for c in commands(res.stdout)}
    assert removed == {str(tmp_path / d) for d in PRUNED_DIRS}


def test_prune_only_without_tree_fails(tmp_path):
    res = run("--prune-only", "--prefix", str(tmp_path / "absent"))
    assert res.returncode == 1
    assert "no Quartus tree" in res.stderr


def test_usage_error():
    assert run("--bogus").returncode == 2


def test_falls_back_to_13_0sp1(tmp_path):
    (tmp_path / "QuartusSetupWeb-13.0.1.232.run").write_bytes(b"")
    res = run("--dry-run", ref=tmp_path)
    assert res.returncode == 0, res.stderr
    cmds = commands(res.stdout)
    installer = next(c for c in cmds if "--mode unattended" in c)
    assert "QuartusSetupWeb-13.0.1.232.run" in installer
    assert "--installdir /opt/altera/13.0sp1" in installer
    assert "cyclone_web-13.0.1.232.qdz" in res.stderr


def test_prefers_13_1(tmp_path):
    for name in (RUNFILE, "QuartusSetupWeb-13.0.1.232.run"):
        (tmp_path / name).write_bytes(b"")
    res = run("--dry-run", ref=tmp_path)
    installer = next(c for c in commands(res.stdout) if "--mode unattended" in c)
    assert RUNFILE in installer and "--installdir /opt/altera/13.1 " in installer
