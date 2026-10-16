"""Tests for scripts/verify_pins.py."""

# pylint: disable=missing-function-docstring

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import verify_pins as vp  # pylint: disable=wrong-import-position

PIN = ROOT / "tests" / "fixtures" / "synthetic_extender.pin"
TCL = ROOT / "Board" / "cone_ext" / "cone_ext_pins.tcl"
MINIMIG = ["ram_addr[0]=sdram_addr[0]", "ram_addr[1]=sdram_addr[1]"]
HEADER = (
    'CHIP "t" ASSIGNED TO AN: EP3C25E144C8\n\n'
    "Pin Name/Usage : Location : Dir : I/O Standard : User Assignment\n"
    "-----\n"
)


@pytest.fixture(name="result")
def fixture_result():
    ours, virtual = vp.parse_tcl(TCL)
    return vp.diff(vp.parse_pin_file(PIN), ours, virtual)


def write(tmp_path, name, text):
    path = tmp_path / name
    path.write_text(text, encoding="utf-8")
    return str(path)


def test_parse_real_tcl():
    ours, virtual = vp.parse_tcl(TCL)
    assert len(ours) == 80
    assert virtual == ["sigma_l", "sigma_r"]
    assert ours["vid[0]"] == "91" and ours["clk28"] == "126"
    assert ours["ram_addr[11]"] == "100"


def test_parse_pin_file():
    rows = vp.parse_pin_file(PIN)
    by_loc = {r.loc: r for r in rows}
    assert by_loc["91"] == vp.PinRow("vid[0]", "91", "input")
    assert by_loc["12"].name == "~ALTERA_ASDO_DATA1~ / RESERVED_INPUT"
    assert by_loc["10"].direction == ""
    assert sum(r.user for r in rows) == 79
    assert not any(by_loc[k].user for k in ("1", "4", "5", "9", "12", "20", "21"))


@pytest.mark.parametrize(
    "name,direction,user",
    [
        ("vid[3]", "input", True),
        ("ram_data[0]", "bidir", True),
        ("data0", "output", True),
        ("nc_flag", "output", True),
        ("DATA0", "input", False),
        ("nCEO", "output", False),
        ("TDO", "output", False),
        ("NC", "", False),
        ("VCCIO3", "power", False),
        ("x", "gnd", False),
    ],
)
def test_user_classification(name, direction, user):
    assert vp.PinRow(name, "1", direction).user is user


def test_categories(result):
    assert result["moved"] == [("ram_clk", "99", "97")]
    assert result["on_reserved"] == [
        ("ram_addr[3]", "4", "GND"),
        ("vid[15]", "43", "RESERVED_INPUT_WITH_WEAK_PULLUP"),
    ]
    assert result["renamed"] == [
        ("ram_addr[2]", "sdram_addr[2]", "6"),
        ("ram_addr[1]", "sdram_addr[1]", "7"),
        ("ram_addr[0]", "sdram_addr[0]", "8"),
    ]
    assert result["unassigned"] == [
        ("led_n", "2"),
        ("spare_io", "3"),
        ("ram_clk", "97"),
    ]
    assert result["missing"] == [
        ("ram_addr[3]", "4"),
        ("vid[15]", "43"),
        ("clk14", "55"),
    ]
    assert result["virtual"] == [("sigma_l",), ("sigma_r",)]


def test_report_lines(result):
    lines = vp.report(result)
    assert "ERROR: location differs (1)" in lines
    assert "  ram_addr[0] -> sdram_addr[0] at PIN_8" in lines
    assert "  sigma_r: unplaced, take location from .pin" in lines


def test_aliases_remove_renames(tmp_path):
    alias_file = write(
        tmp_path, "a.txt", "# minimig names\nram_addr[2] sdram_addr[2]  # c\n\n"
    )
    aliases = vp.parse_aliases(MINIMIG, [alias_file])
    assert aliases == {f"ram_addr[{i}]": f"sdram_addr[{i}]" for i in range(3)}
    ours, _ = vp.parse_tcl(TCL)
    assert not vp.diff(vp.parse_pin_file(PIN), ours, aliases=aliases)["renamed"]


def test_alias_moved_detected():
    rows = [vp.PinRow("sdram_addr[0]", "9", "output")]
    result = vp.diff(rows, {"ram_addr[0]": "8"}, aliases=dict([MINIMIG[0].split("=")]))
    assert result["moved"] == [("ram_addr[0]", "8", "9")]
    assert not result["missing"]


def test_bad_alias():
    with pytest.raises(vp.ParseError):
        vp.parse_aliases(["noequals"])


def test_loc_key_sorting():
    assert sorted(["10", "9", "A10", "A2", "B1"], key=vp.loc_key) == [
        "9",
        "10",
        "A2",
        "A10",
        "B1",
    ]


def test_main_default_and_strict(capsys):
    assert vp.main([str(PIN), str(TCL)]) == 1
    out = capsys.readouterr().out
    assert out.startswith("96 .pin rows (79 user), 80 assignments, 2 virtual")
    assert vp.main([str(PIN), str(TCL), "--strict"]) == 1


def test_main_exit_codes(tmp_path):
    tcl = write(
        tmp_path,
        "p.tcl",
        "set_location_assignment PIN_A1 -to {vid[0]} ;# x\n"
        "# set_location_assignment PIN_A2 -to commented\n"
        "set_instance_assignment -name VIRTUAL_PIN ON -to sigma_l\n",
    )
    clean = write(tmp_path, "c.pin", HEADER + "vid[0] : A1 : input : 3.3-V LVTTL : Y\n")
    warn = write(
        tmp_path,
        "w.pin",
        HEADER + "x[0] : A1 : input : :\nled : B2 : output : :\nGND : C3 : gnd : :\n",
    )
    assert vp.main([clean, tcl]) == 0
    assert vp.main([clean, tcl, "--strict"]) == 0
    assert vp.main([warn, tcl]) == 0
    assert vp.main([warn, tcl, "--strict"]) == 1
    assert vp.main([warn, tcl, "--alias", "vid[0]=x[0]", "--strict"]) == 1


def test_main_parse_errors(tmp_path, capsys):
    bad = write(tmp_path, "bad.pin", " -- just a header\nCHIP x\n")
    assert vp.main([bad, str(TCL)]) == 2
    assert "no pin table header" in capsys.readouterr().err
    assert vp.main([str(tmp_path / "missing.pin"), str(TCL)]) == 2
    assert vp.main([str(PIN), str(TCL), "--alias", "a=b=c=d", "--alias", "x"]) == 2
