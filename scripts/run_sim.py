#!/usr/bin/env python3
"""Run the GHDL testbench case matrix in parallel and check every outcome.

tb_mmlink: firmware-timed nominal run plus a wire-delay sweep whose pass/fail
and measured setup/hold must equal mm_windows(); --acex repeats it on acex.vhd.
tb_vidbus (cone_io fallback): nominal cases; --vidbus-sweep adds its sweep.
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import itertools
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field

T_CLK_PS = 9977
"""clk_100 period produced by hostclocks c0 from the altpll stub."""
T_HIGH_PS = T_CLK_PS / 2
"""clk_100 rising to falling edge (the stub places edges on a half-period grid)."""
WINDOW_TOL_PS = 2
"""Edge rounding of the stub's half-period grid."""
MARGIN_PS = 1000
"""Setup/hold margin the testbenches require at every capture point."""

RESULT_RE = re.compile(r"RESULT (\w+)(?:=(-?\d+))?")
WINDOW_KEYS = ("ext_setup_ps", "ext_hold_ps", "k30_setup_ps", "k30_hold_ps")


@dataclass(frozen=True)
class Case:  # pylint: disable=too-many-instance-attributes
    """One simulation run."""

    name: str
    generics: dict
    required: bool = True
    expect: bool | None = None
    tb: str = "tb_vidbus"
    flags: tuple = ()
    windows: dict | None = None

    def args(self) -> list[str]:
        """GHDL -g overrides for this case."""
        return [f"-g{k}={v}" for k, v in sorted(self.generics.items())]


@dataclass
class Outcome:
    """Parsed result of one run."""

    case: Case
    passed: bool
    results: dict = field(default_factory=dict)
    error: str = ""
    seconds: float = 0.0

    @property
    def window_errors(self) -> list[str]:
        """Measured capture windows that differ from the prediction."""
        want = self.case.windows or {}
        return [
            f"{k} {self.results[k]} != {v:.0f}"
            for k, v in want.items()
            if k in self.results and abs(self.results[k] - v) > WINDOW_TOL_PS
        ]

    @property
    def ok(self) -> bool:
        """Whether the outcome is what the case requires or predicts."""
        if self.window_errors:
            return False
        if self.case.expect is not None:
            return self.passed == self.case.expect
        return self.passed or not self.case.required


def mm_windows(
    rt_ps: int, skew_ps: int, t_clk_ps: int = T_CLK_PS, t_high_ps: float = T_HIGH_PS
) -> dict:
    """Setup/hold at the Minimig link's two capture points, both IOclk rises.

    The extender launches half a clk_100 after raising IOclk (data skew_ps
    later than IOclk at the 1k30); the 1k30's data arrives rt_ps after IOclk.
    """
    period = 2 * t_clk_ps
    ext = rt_ps % period
    k30 = (t_high_ps + skew_ps) % period
    return {
        "ext_setup_ps": period - ext,
        "ext_hold_ps": ext,
        "k30_setup_ps": period - k30,
        "k30_hold_ps": k30,
    }


def mm_predict(rt_ps: int, skew_ps: int, margin_ps: int = MARGIN_PS) -> bool:
    """Whether both windows hold the margin without slipping an IOclk cycle."""
    period = 2 * T_CLK_PS
    k30 = T_HIGH_PS + skew_ps
    return (
        margin_ps < rt_ps <= period - margin_ps
        and margin_ps < k30 <= period - margin_ps
    )


def mm_case(name: str, rt_ps: int, skew_ps: int, acex: bool, **gen) -> Case:
    """A tb_mmlink case with its round trip split evenly over both directions."""
    gen.update(T_E2K_PS=rt_ps // 2, T_K2E_PS=rt_ps - rt_ps // 2, SKEW_PS=skew_ps)
    if acex:
        gen["K30_REAL"] = "true"
    sweep = name.startswith("sweep")
    return Case(
        ("acex_" if acex else "mm_") + name,
        gen,
        required=not sweep,
        expect=mm_predict(rt_ps, skew_ps) if sweep else None,
        tb="tb_mmlink",
        flags=("-fsynopsys",),
        windows=mm_windows(rt_ps, skew_ps),
    )


def mm_cases(sweep: bool, acex: bool) -> list[Case]:
    """tb_mmlink cases: firmware timing, a 1k30 that starts late, the sweep."""
    fast = {"SLOWBIT": 2, "SPIN_BYTES": 4, "FULL": "false", "PS2_HALF_NS": 5000}
    cases = [
        mm_case("firmware", 6000, 0, acex),
        mm_case("late_k30", 6000, 0, acex, K30_START_NS=500000, **fast),
    ]
    if not sweep:
        return cases
    for rt in range(0, 30001, 2500):
        cases.append(mm_case(f"sweep_rt{rt}", rt, 0, acex, **fast))
    for skew in range(2500, 17501, 2500):
        cases.append(mm_case(f"sweep_skew{skew}", 6000, skew, acex, **fast))
    return cases


def vidbus_predict(  # pylint: disable=too-many-arguments,too-many-positional-arguments
    mux_div: int,
    q_lat: int,
    rt_ps: int,
    miso_delay_ps: int,
    miso_visits: int,
    margin_ps: int,
    t_clk_ps: int = T_CLK_PS,
) -> bool:
    """Whether the cone_io protocol meets its capture windows.

    q is valid for one mux_clk period from rise + rt, sampled q_lat clk_mux
    cycles after the rise; MISO is sampled miso_visits SPI slots later.
    """
    sample = q_lat * t_clk_ps
    period = 2 * mux_div * t_clk_ps
    q_ok = rt_ps + margin_ps <= sample and sample + margin_ps < period + rt_ps
    miso_ok = miso_delay_ps < 2 * period * miso_visits
    return q_ok and miso_ok


def vidbus_cases(sweep: bool, margin_ps: int = MARGIN_PS) -> list[Case]:
    """tb_vidbus nominal configurations, and optionally its predicted sweep."""
    cases = [
        Case("vidbus_div1_q1_ideal", {"MUX_DIV": 1, "Q_LAT": 1}),
        Case("vidbus_template_div2_q2", {"MUX_DIV": 2, "Q_LAT": 2}),
        Case(
            "vidbus_div1_q2_rt12ns",
            {"MUX_DIV": 1, "Q_LAT": 2, "T_E2K_PS": 6000, "T_K2E_PS": 6000},
        ),
        Case(
            "vidbus_div2_q2_rt12ns_skew",
            {
                "MUX_DIV": 2,
                "Q_LAT": 2,
                "T_E2K_PS": 6000,
                "T_K2E_PS": 6000,
                "SKEW_PS": 3000,
                "MISO_DELAY_PS": 30000,
            },
        ),
        Case(
            "vidbus_div1_q1_miso60ns_v2",
            {"MUX_DIV": 1, "Q_LAT": 1, "MISO_DELAY_PS": 60000, "MISO_VISITS": 2},
        ),
    ]
    if not sweep:
        return cases
    fast = {"N_BURSTS": 1, "BURST_LEN": 8, "PS2_HALF_NS": 2000}
    for div, rt in itertools.product((1, 2), range(0, 45001, 2500)):
        for q_lat in range(1, 2 * div + 2):
            gen = {"MUX_DIV": div, "Q_LAT": q_lat, **fast}
            gen.update(T_E2K_PS=rt // 2, T_K2E_PS=rt - rt // 2)
            cases.append(
                Case(
                    f"vidbus_sweep_div{div}_q{q_lat}_rt{rt}",
                    gen,
                    required=False,
                    expect=vidbus_predict(div, q_lat, rt, 0, 1, margin_ps),
                )
            )
    for div, visits, miso in itertools.product((1, 2), (1, 2), range(0, 160001, 20000)):
        gen = {"MUX_DIV": div, "Q_LAT": div, "MISO_VISITS": visits, **fast}
        gen["MISO_DELAY_PS"] = miso
        cases.append(
            Case(
                f"vidbus_sweep_div{div}_v{visits}_miso{miso}",
                gen,
                required=False,
                expect=vidbus_predict(div, div, 0, miso, visits, margin_ps),
            )
        )
    return cases


def run_case(cmd: list[str], case: Case, logdir: str) -> Outcome:
    """Run one case and parse its RESULT lines."""
    start = time.monotonic()
    proc = subprocess.run(
        cmd + list(case.flags) + [case.tb] + case.args() + ["--assert-level=error"],
        capture_output=True,
        text=True,
        check=False,
    )
    log = proc.stdout + proc.stderr
    with open(os.path.join(logdir, case.name + ".log"), "w", encoding="utf-8") as fh:
        fh.write(log)
    results = {m[1]: int(m[2]) if m[2] else 1 for m in RESULT_RE.finditer(log)}
    errors = [ln for ln in log.splitlines() if "(assertion error)" in ln]
    return Outcome(
        case,
        proc.returncode == 0 and "PASS" in results,
        results,
        errors[0].split("(assertion error):")[-1].strip() if errors else "",
        time.monotonic() - start,
    )


def run_all(cases: list[Case], cmd: list[str], logdir: str, jobs: int) -> list[Outcome]:
    """Run cases in parallel, nominal (long) ones first, printing progress."""
    os.makedirs(logdir, exist_ok=True)
    outcomes = []
    start = time.monotonic()
    order = sorted(cases, key=lambda c: c.expect is not None)
    with cf.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(run_case, cmd, c, logdir) for c in order]
        for n, fut in enumerate(cf.as_completed(futures), 1):
            out = fut.result()
            outcomes.append(out)
            elapsed = time.monotonic() - start
            print(
                f"[{n}/{len(cases)}] {elapsed:6.1f}s {n / elapsed:5.2f} runs/s "
                f"{'ok  ' if out.ok else 'FAIL'} {out.case.name} ({out.seconds:.1f}s)",
                flush=True,
            )
    return sorted(outcomes, key=lambda o: o.case.name)


def _table(outcomes: list[Outcome], keys: list[str]) -> None:
    if not outcomes:
        return
    print("\n" + " ".join(f"{k:>14}" for k in ["case"] + keys))
    for o in outcomes:
        cells = [str(o.results.get(k, "-")) for k in keys]
        print(" ".join(f"{c:>14}" for c in [o.case.name[-14:]] + cells))
        if not o.passed:
            print(f"    FAILED: {o.error}")


def summarise(outcomes: list[Outcome]) -> int:
    """Print the nominal results tables and sweep mismatches; return exit code."""
    nominal = [o for o in outcomes if o.case.expect is None]
    _table(
        [o for o in nominal if o.case.tb == "tb_mmlink"],
        ["sync_ns", "sd_init_us", "read_us", "write_us", "sd_size", "dior_ns"]
        + ["diow_ns", "ext_setup_ps", "k30_setup_ps"],
    )
    _table(
        [o for o in nominal if o.case.tb == "tb_vidbus"],
        ["slot_ns", "sck_mean_khz", "spi_kbyte_s", "ps2_lat_max_ns", "io_lat_max_ns"],
    )
    sweep = [o for o in outcomes if o.case.expect is not None]
    if sweep:
        agree = sum(o.ok for o in sweep)
        print(
            f"\nsweep: {agree}/{len(sweep)} outcomes match the predicted capture windows"
        )
    for o in outcomes:
        if o.case.expect is not None and o.passed != o.case.expect:
            print(
                f"    MISMATCH {o.case.name}: predicted "
                f"{'pass' if o.case.expect else 'fail'}, got "
                f"{'pass' if o.passed else 'fail'} {o.error}"
            )
        for err in o.window_errors:
            print(f"    WINDOW {o.case.name}: {err}")
    bad = [o for o in outcomes if not o.ok]
    print(
        f"\nsim {'FAILED' if bad else 'OK'}: {len(outcomes) - len(bad)}/{len(outcomes)}"
    )
    return 1 if bad else 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--altera-mf", required=True)
    ap.add_argument("--logdir", required=True)
    ap.add_argument("--jobs", type=int, default=os.cpu_count())
    ap.add_argument("--no-sweep", action="store_true")
    ap.add_argument("--vidbus-sweep", action="store_true")
    ap.add_argument("--acex", action="store_true", help="also run on 1k30/acex.vhd")
    ap.add_argument("--only", help="regex selecting case names")
    args = ap.parse_args(argv)
    cases = mm_cases(not args.no_sweep, False) + vidbus_cases(args.vidbus_sweep)
    if args.acex:
        cases += mm_cases(not args.no_sweep, True)
    if args.only:
        cases = [c for c in cases if re.search(args.only, c.name)]
    cmd = ["ghdl", "-r", "--std=08", f"--workdir={args.workdir}", f"-P{args.altera_mf}"]
    return summarise(run_all(cases, cmd, args.logdir, args.jobs))


if __name__ == "__main__":
    sys.exit(main())
