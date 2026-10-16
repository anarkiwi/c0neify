#!/usr/bin/env python3
"""Run the tb_vidbus case matrix in parallel and check every outcome.

Nominal cases must pass. Sweep cases vary the bus round trip and the card's
MISO delay around the capture windows; each outcome must equal predict().
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
"""clk_mux period produced by hostclocks c0 from the altpll stub."""

RESULT_RE = re.compile(r"RESULT (\w+)(?:=(-?\d+))?")


@dataclass(frozen=True)
class Case:
    """One simulation run."""

    name: str
    generics: dict
    required: bool = True
    expect: bool | None = None

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
    def ok(self) -> bool:
        """Whether the outcome is what the case requires or predicts."""
        if self.case.expect is not None:
            return self.passed == self.case.expect
        return self.passed or not self.case.required


def predict(  # pylint: disable=too-many-arguments,too-many-positional-arguments
    mux_div: int,
    q_lat: int,
    rt_ps: int,
    miso_delay_ps: int,
    miso_visits: int,
    margin_ps: int,
    t_clk_ps: int = T_CLK_PS,
) -> bool:
    """Whether the protocol meets its capture windows.

    q is valid at the extender for one mux_clk period from rise + rt and is
    sampled q_lat clk_mux cycles after the rise with margin_ps either side.
    The slave samples MISO miso_visits SPI slots (two periods each) later.
    """
    sample = q_lat * t_clk_ps
    period = 2 * mux_div * t_clk_ps
    q_ok = rt_ps + margin_ps <= sample and sample + margin_ps < period + rt_ps
    miso_ok = miso_delay_ps < 2 * period * miso_visits
    return q_ok and miso_ok


def nominal_cases() -> list[Case]:
    """Configurations that must pass."""
    return [
        Case("div1_q1_ideal", {"MUX_DIV": 1, "Q_LAT": 1}),
        Case("template_div2_q2", {"MUX_DIV": 2, "Q_LAT": 2}),
        Case(
            "div1_q2_rt12ns",
            {"MUX_DIV": 1, "Q_LAT": 2, "T_E2K_PS": 6000, "T_K2E_PS": 6000},
        ),
        Case(
            "div2_q2_rt12ns_skew",
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
            "div1_q1_miso60ns_v2",
            {"MUX_DIV": 1, "Q_LAT": 1, "MISO_DELAY_PS": 60000, "MISO_VISITS": 2},
        ),
    ]


def sweep_cases(margin_ps: int = 1000) -> list[Case]:
    """Round-trip and MISO-delay sweep with predicted outcomes."""
    fast = {"N_BURSTS": 1, "BURST_LEN": 8, "PS2_HALF_NS": 2000}
    cases = []
    for div, rt in itertools.product((1, 2), range(0, 45001, 2500)):
        for q_lat in range(1, 2 * div + 2):
            gen = {"MUX_DIV": div, "Q_LAT": q_lat, **fast}
            gen.update(T_E2K_PS=rt // 2, T_K2E_PS=rt - rt // 2)
            cases.append(
                Case(
                    f"sweep_div{div}_q{q_lat}_rt{rt}",
                    gen,
                    required=False,
                    expect=predict(div, q_lat, rt, 0, 1, margin_ps),
                )
            )
    for div, visits, miso in itertools.product((1, 2), (1, 2), range(0, 160001, 20000)):
        gen = {"MUX_DIV": div, "Q_LAT": div, "MISO_VISITS": visits, **fast}
        gen["MISO_DELAY_PS"] = miso
        cases.append(
            Case(
                f"sweep_div{div}_v{visits}_miso{miso}",
                gen,
                required=False,
                expect=predict(div, div, 0, miso, visits, margin_ps),
            )
        )
    return cases


def run_case(cmd: list[str], case: Case, logdir: str) -> Outcome:
    """Run one case and parse its RESULT lines."""
    start = time.monotonic()
    proc = subprocess.run(
        cmd + case.args() + ["--assert-level=error"],
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
    """Run cases in parallel, printing progress as they complete."""
    os.makedirs(logdir, exist_ok=True)
    outcomes = []
    start = time.monotonic()
    with cf.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(run_case, cmd, c, logdir) for c in cases]
        for n, fut in enumerate(cf.as_completed(futures), 1):
            out = fut.result()
            outcomes.append(out)
            elapsed = time.monotonic() - start
            print(
                f"[{n}/{len(cases)}] {elapsed:6.1f}s {n / elapsed:5.2f} runs/s "
                f"{'ok  ' if out.ok else 'FAIL'} {out.case.name}",
                flush=True,
            )
    return sorted(outcomes, key=lambda o: o.case.name)


def summarise(outcomes: list[Outcome]) -> int:
    """Print the nominal results table and sweep mismatches; return exit code."""
    keys = [
        "slot_ns",
        "sck_mean_khz",
        "sck_max_khz",
        "spi_kbyte_s",
        "ps2_lat_min_ns",
        "ps2_lat_mean_ns",
        "ps2_lat_max_ns",
        "ps2_inhibit_lat_ns",
        "io_lat_max_ns",
    ]
    nominal = [o for o in outcomes if o.case.expect is None]
    print("\n" + " ".join(f"{k:>18}" for k in ["case"] + keys))
    for o in nominal:
        cells = [str(o.results.get(k, "-")) for k in keys]
        print(" ".join(f"{c:>18}" for c in [o.case.name[-18:]] + cells))
        if not o.passed:
            print(f"    FAILED: {o.error}")
    sweep = [o for o in outcomes if o.case.expect is not None]
    if sweep:
        agree = sum(o.ok for o in sweep)
        print(
            f"\nsweep: {agree}/{len(sweep)} outcomes match the predicted capture windows"
        )
        for o in sweep:
            if not o.ok:
                print(
                    f"    MISMATCH {o.case.name}: predicted "
                    f"{'pass' if o.case.expect else 'fail'}, got "
                    f"{'pass' if o.passed else 'fail'} {o.error}"
                )
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
    ap.add_argument("--only", help="regex selecting case names")
    args = ap.parse_args(argv)
    cases = nominal_cases() + ([] if args.no_sweep else sweep_cases())
    if args.only:
        cases = [c for c in cases if re.search(args.only, c.name)]
    cmd = [
        "ghdl",
        "-r",
        "--std=08",
        f"--workdir={args.workdir}",
        f"-P{args.altera_mf}",
        "tb_vidbus",
    ]
    return summarise(run_all(cases, cmd, args.logdir, args.jobs))


if __name__ == "__main__":
    sys.exit(main())
