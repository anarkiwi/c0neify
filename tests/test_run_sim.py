"""Tests for scripts/run_sim.py (case generation, prediction, parsing)."""

# pylint: disable=missing-function-docstring

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import run_sim  # noqa: E402  pylint: disable=wrong-import-position

T = run_sim.T_CLK_PS


@pytest.mark.parametrize(
    "div,q,rt,expect",
    [
        (1, 1, 0, True),
        (1, 1, T - 1000, True),
        (1, 1, T - 999, False),
        (1, 2, 0, False),
        (1, 2, 1001, True),
        (1, 2, 2 * T - 1000, True),
        (2, 2, 0, True),
        (2, 4, 4 * T - 1000, True),
        (2, 4, 4 * T - 999, False),
    ],
)
def test_predict_q_window(div, q, rt, expect):
    assert run_sim.predict(div, q, rt, 0, 1, 1000) is expect


@pytest.mark.parametrize(
    "div,visits,miso,expect",
    [
        (1, 1, 4 * T - 1, True),
        (1, 1, 4 * T, False),
        (1, 2, 8 * T - 1, True),
        (2, 1, 8 * T, False),
    ],
)
def test_predict_miso(div, visits, miso, expect):
    assert run_sim.predict(div, div, 0, miso, visits, 1000) is expect


def test_cases_unique_and_sweep_has_both_outcomes():
    cases = run_sim.nominal_cases() + run_sim.sweep_cases()
    names = [c.name for c in cases]
    assert len(names) == len(set(names))
    sweep = [c for c in cases if c.expect is not None]
    assert {c.expect for c in sweep} == {True, False}
    assert all(c.required for c in run_sim.nominal_cases())
    assert run_sim.Case("x", {"B": 2, "A": 1}).args() == ["-gA=1", "-gB=2"]


FAKE = """import sys
args = sys.argv[1:]
if "-gFAIL=1" in args:
    print("tb.vhd:1:1:@0ms:(assertion error): boom")
    sys.exit(1)
print("x:(report note): RESULT sck_mean_khz=4176")
print("x:(report note): RESULT PASS")
"""


@pytest.fixture(name="fake_cmd")
def fixture_fake_cmd(tmp_path):
    script = tmp_path / "fake_ghdl.py"
    script.write_text(FAKE)
    return [sys.executable, str(script)]


def test_run_all_and_summarise(fake_cmd, tmp_path, capsys):
    cases = [
        run_sim.Case("good", {}),
        run_sim.Case("bad", {"FAIL": 1}),
        run_sim.Case("predicted_fail", {"FAIL": 1}, required=False, expect=False),
        run_sim.Case("mispredicted", {}, required=False, expect=False),
    ]
    outs = {
        o.case.name: o
        for o in run_sim.run_all(cases, fake_cmd, str(tmp_path / "logs"), 2)
    }
    assert outs["good"].passed and outs["good"].results["sck_mean_khz"] == 4176
    assert not outs["bad"].passed and outs["bad"].error == "boom"
    assert outs["predicted_fail"].ok and not outs["mispredicted"].ok
    assert (tmp_path / "logs" / "bad.log").read_text().count("boom") == 1
    assert run_sim.summarise(list(outs.values())) == 1
    out = capsys.readouterr().out
    assert "MISMATCH mispredicted" in out and "FAILED: boom" in out
    assert run_sim.summarise([outs["good"], outs["predicted_fail"]]) == 0


def test_main_only_filter(fake_cmd, tmp_path, monkeypatch):
    seen = []
    real_run_all = run_sim.run_all

    def fake_run_all(cases, cmd, logdir, jobs):
        seen.extend(c.name for c in cases)
        assert cmd[:2] == ["ghdl", "-r"] and logdir and jobs == 3
        return real_run_all(cases[:1], fake_cmd, logdir, jobs)

    monkeypatch.setattr(run_sim, "run_all", fake_run_all)
    argv = [
        "--workdir",
        "w",
        "--altera-mf",
        "a",
        "--logdir",
        str(tmp_path),
        "--jobs",
        "3",
    ]
    assert run_sim.main(argv + ["--no-sweep", "--only", "ideal"]) == 0
    assert seen == ["div1_q1_ideal"]
