#!/usr/bin/env python3
"""Fail when a TimeQuest report (.sta.rpt) shows negative slack on any clock.

Reads every "<corner> Setup|Hold|Recovery|Removal Summary" table and reports
each clock's worst slack per corner and check. Exit 1 on any negative slack,
2 when no summary table is found.
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import NamedTuple

TITLE = re.compile(r"^;\s*(.*?)\s*(Setup|Hold|Recovery|Removal) Summary\s*;\s*$")
ROW = re.compile(r"^;([^;]+);\s*(-?\d+(?:\.\d+)?)\s*;")


class Slack(NamedTuple):
    """Worst slack of one clock for one corner and check."""

    corner: str
    check: str
    clock: str
    slack: float


def parse(text: str) -> list[Slack]:
    """Collect clock/slack rows from every summary table in a report."""
    out: list[Slack] = []
    corner = check = None
    for line in text.splitlines():
        if m := TITLE.match(line):
            corner, check = m[1] or "-", m[2]
        elif check and line.startswith("+"):
            continue
        elif check and (m := ROW.match(line)):
            out.append(Slack(corner, check, m[1].strip(), float(m[2])))
        elif check and not line.startswith(";"):
            corner = check = None
    return out


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("reports", nargs="+")
    args = ap.parse_args(argv)
    rc = 0
    for path in args.reports:
        with open(path, encoding="utf-8", errors="replace") as fh:
            rows = parse(fh.read())
        if not rows:
            print(f"{path}: no setup/hold summary tables found")
            rc = max(rc, 2)
            continue
        failing = [r for r in rows if r.slack < 0]
        for r in rows:
            mark = "FAIL" if r.slack < 0 else "ok  "
            print(f"{mark} {path}: {r.corner} {r.check:8} {r.slack:8.3f}  {r.clock}")
        if failing:
            rc = max(rc, 1)
    print("timing", "met" if rc == 0 else "NOT met")
    return rc


if __name__ == "__main__":
    sys.exit(main())
