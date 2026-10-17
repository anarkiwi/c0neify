"""Tests for scripts/rpt_hier.py on Quartus 'Resource Utilization by Entity' tables."""

# pylint: disable=missing-function-docstring

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import rpt_hier  # noqa: E402  pylint: disable=wrong-import-position

RULE = "+" + "-" * 40 + "+" + "-" * 13 + "+" + "-" * 13 + "+" + "-" * 7 + "+"


def report(title, cols, rows):
    head = "; Compilation Hierarchy Node ; " + " ; ".join(cols) + " ;"
    body = [f"; {node} ; " + " ; ".join(vals) + " ;" for node, vals in rows]
    return "\n".join(
        ["; Other table ;", RULE, f"; {title} ;", RULE, head, RULE, *body, RULE, ""]
        + ["; |after_the_table ; 999 (9) ; 1 ; 1 ;"]
    )


FIT = report(
    "Fitter Resource Utilization by Entity",
    ["Logic Cells", "Dedicated Logic Registers", "M9Ks"],
    [
        ("|top", ["1500 (4)", "700 (2)", "9"]),
        ("   |guest:g|", ["1200 (100)", "600 (10)", "9"]),
        ("      |cpu:c|", ["800 (800)", "160 (160)", "0"]),
        ("         |alu:a|", ["400 (400)", "0 (0)", "0"]),
        ("      |small:s|", ["50 (50)", "5 (5)", "0"]),
    ],
)
MAP = report(
    "Analysis & Synthesis Resource Utilization by Entity",
    ["LC Combinationals", "LC Registers", "Memory Bits"],
    [("|top", ["300 (3)", "100 (1)", "2048"]), ("   |u:u|", ["250 (250)", "0", "0"])],
)


def test_table_depths_and_cells():
    rows = list(rpt_hier.table(FIT.splitlines()))
    assert [(d, n) for d, n, _ in rows] == [
        (0, "|top"),
        (1, "|guest:g|"),
        (2, "|cpu:c|"),
        (3, "|alu:a|"),
        (2, "|small:s|"),
    ]
    assert rows[1][2] == {
        "Logic Cells": "1200 (100)",
        "Dedicated Logic Registers": "600 (10)",
        "M9Ks": "9",
    }


def test_render_filters_by_depth_and_size():
    out = list(rpt_hier.render(rpt_hier.table(FIT.splitlines()), 2, 200))
    assert [line.split()[0] for line in out] == ["|top", "|guest:g|", "|cpu:c|"]
    assert out[2].startswith("    |cpu:c|")
    assert out[2].split()[1:] == ["LC=800", "reg=160", "M9K=0"]


def test_map_report_uses_lc_combinationals(tmp_path, capsys):
    rpt = tmp_path / "x.map.rpt"
    rpt.write_text(MAP, encoding="latin-1")
    assert rpt_hier.main([str(rpt), "-m", "260"]) == 0
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 1 and lines[0].split()[1:] == [
        "comb=300",
        "reg=100",
        "bits=2048",
    ]


def test_missing_table(tmp_path, capsys):
    rpt = tmp_path / "empty.rpt"
    rpt.write_text("; Flow Summary ;\n")
    assert rpt_hier.main([str(rpt)]) == 1
    assert "no 'Resource Utilization by Entity' table" in capsys.readouterr().err


@pytest.mark.parametrize("cell,n", [("9156 (118)", 9156), ("25", 25)])
def test_count(cell, n):
    assert rpt_hier.count(cell) == n
