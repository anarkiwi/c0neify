"""Tests for scripts/qip_files.py."""

# pylint: disable=missing-function-docstring

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import qip_files  # noqa: E402  pylint: disable=wrong-import-position


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def test_resolve_recursive(tmp_path, capsys):
    prj = tmp_path / "core" / "board"
    write(
        prj / "files.tcl",
        "set_global_assignment -name QIP_FILE ../lib/lib.qip\n"
        "set_global_assignment -name QIP_FILE ../files.qip\n"
        "set_global_assignment -name VHDL_FILE ../pkg.vhd\n"
        "set_global_assignment -name PRE_FLOW_SCRIPT_FILE quartus_sh:../x.tcl\n",
    )
    write(
        tmp_path / "core" / "lib" / "lib.qip",
        'set_global_assignment -name VHDL_FILE [file join $::quartus(qip_path) "a.vhd"]\n'
        "set_global_assignment -name VERILOG_FILE [file join $::quartus(qip_path) sub/b.v]\n"
        'set_global_assignment -name QIP_FILE [file join $::quartus(qip_path) "../lib/lib.qip"]\n'
        "set_global_assignment -name QIP_FILE [file join $::quartus(qip_path) sub/c.qip]\n",
    )
    write(
        tmp_path / "core" / "lib" / "sub" / "c.qip",
        "set_global_assignment -name SYSTEMVERILOG_FILE [file join $::quartus(qip_path) c.sv]\n",
    )
    write(
        tmp_path / "core" / "files.qip",
        "set_global_assignment -name VHDL_FILE guest.vhd\n",
    )
    got = qip_files.resolve(str(prj / "files.tcl"), str(prj), {"files.qip"}, set())
    lib = tmp_path / "core" / "lib"
    assert got == [
        ("VHDL_FILE", str(lib / "a.vhd")),
        ("VERILOG_FILE", str(lib / "sub" / "b.v")),
        ("SYSTEMVERILOG_FILE", str(lib / "sub" / "c.sv")),
        ("VHDL_FILE", str(tmp_path / "core" / "pkg.vhd")),
        ("PRE_FLOW_SCRIPT_FILE", str(prj / "quartus_sh:../x.tcl")),
    ]
    assert qip_files.main(["--base", str(prj), "--kind", "VHDL_FILE", "files.tcl"]) == 0
    out = capsys.readouterr().out.splitlines()
    assert out == [
        f"VHDL_FILE\t{lib / 'a.vhd'}",
        f"VHDL_FILE\t{prj / 'guest.vhd'}",
        f"VHDL_FILE\t{tmp_path / 'core' / 'pkg.vhd'}",
    ]
