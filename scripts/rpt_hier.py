#!/usr/bin/env python3
"""Print a Quartus map/fit 'Resource Utilization by Entity' table as a tree."""

import argparse
import re
import sys
from collections.abc import Iterable, Iterator

COLS = {
    "Logic Cells": "LC",
    "LC Combinationals": "comb",
    "LC Registers": "reg",
    "Dedicated Logic Registers": "reg",
    "Memory Bits": "bits",
    "M9Ks": "M9K",
    "DSP Elements": "DSP",
    "DSP 9x9": "DSP9",
    "DSP 18x18": "DSP18",
}
TITLE = re.compile(r";.*Resource Utilization by Entity\s*;")

Row = tuple[int, str, dict[str, str]]


def table(lines: Iterable[str]) -> Iterator[Row]:
    """Yield (depth, node, {column: cell}) for each row of the first table."""
    it = iter(lines)
    if not any(TITLE.match(line) for line in it):
        raise ValueError("no 'Resource Utilization by Entity' table")
    hdr: list[str] = []
    rules = 0
    for line in it:
        if line.startswith("+"):
            rules += 1
            if rules == 3:
                return
            continue
        cells = line.split(";")[1:-1]
        if not hdr:
            hdr = [c.strip() for c in cells]
            continue
        node = cells[0].rstrip()
        depth = (len(node) - len(node.lstrip())) // 3
        yield depth, node.strip(), dict(zip(hdr[1:], (c.strip() for c in cells[1:])))


def count(cell: str) -> int:
    """Total from a cell such as '9156 (118)'."""
    return int(cell.split()[0])


def render(rows: Iterable[Row], depth: int, minimum: int) -> Iterator[str]:
    """Lines for rows at most `depth` deep with at least `minimum` LUTs."""
    for d, node, cells in rows:
        key = "Logic Cells" if "Logic Cells" in cells else "LC Combinationals"
        if d <= depth and count(cells[key]) >= minimum:
            vals = "  ".join(
                f"{short}={count(cells[c])}" for c, short in COLS.items() if c in cells
            )
            yield f"{'  ' * d}{node[:60]:<{62 - 2 * d}} {vals}"


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("rpt", help="Quartus .map.rpt or .fit.rpt")
    ap.add_argument("-d", "--depth", type=int, default=3)
    ap.add_argument(
        "-m", "--min", type=int, default=200, help="minimum LUTs (comb or LC)"
    )
    args = ap.parse_args(argv)
    with open(args.rpt, encoding="latin-1") as f:
        try:
            for line in render(table(f.read().splitlines()), args.depth, args.min):
                print(line)
        except ValueError as e:
            print(f"{args.rpt}: {e}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
