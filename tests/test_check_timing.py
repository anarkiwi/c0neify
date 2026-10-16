"""Tests for scripts/check_timing.py against TimeQuest-format summaries."""

# pylint: disable=missing-function-docstring

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import check_timing  # noqa: E402  pylint: disable=wrong-import-position

PLL0 = "clocks|altpll_component|auto_generated|pll1|clk[0]"


def table(title, rows):
    rule = "+" + "-" * 70 + "+"
    lines = [rule, f"; {title} ;", rule, "; Clock ; Slack ; End Point TNS ;", rule]
    lines += [f"; {c} ; {s} ; 0.000 ;" for c, s in rows]
    return "\n".join(lines + [rule, ""])


REPORT = "\n".join(
    [
        "Some header text ; with a semicolon",
        table(
            "Slow 1200mV 85C Model Setup Summary", [(PLL0, "1.234"), ("clk14", "60.1")]
        ),
        table("Slow 1200mV 85C Model Hold Summary", [(PLL0, "0.402")]),
        table("Fast 1200mV 0C Model Hold Summary", [(PLL0, "-0.050")]),
        table("Slow 1200mV 85C Model Fmax Summary", [(PLL0, "123.4")]),
        table("Setup Summary", [("clk28", "3")]),
    ]
)


def test_parse_reads_only_summary_tables():
    rows = check_timing.parse(REPORT)
    assert rows == [
        check_timing.Slack("Slow 1200mV 85C Model", "Setup", PLL0, 1.234),
        check_timing.Slack("Slow 1200mV 85C Model", "Setup", "clk14", 60.1),
        check_timing.Slack("Slow 1200mV 85C Model", "Hold", PLL0, 0.402),
        check_timing.Slack("Fast 1200mV 0C Model", "Hold", PLL0, -0.05),
        check_timing.Slack("-", "Setup", "clk28", 3.0),
    ]


def test_main_exit_codes(tmp_path, capsys):
    bad = tmp_path / "bad.sta.rpt"
    bad.write_text(REPORT)
    good = tmp_path / "good.sta.rpt"
    good.write_text(REPORT.replace("-0.050", "0.050"))
    empty = tmp_path / "empty.sta.rpt"
    empty.write_text("nothing here\n")
    assert check_timing.main([str(good)]) == 0
    assert check_timing.main([str(bad), str(good)]) == 1
    out = capsys.readouterr().out
    assert f"FAIL {bad}: Fast 1200mV 0C Model Hold" in out and "timing NOT met" in out
    assert check_timing.main([str(empty)]) == 2
