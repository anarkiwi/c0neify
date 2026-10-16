#!/usr/bin/env python3
"""List the source files a Quartus .qip/.tcl file list pulls in, recursively.

Prints "KIND<TAB>path" per file (VHDL_FILE, VERILOG_FILE, ...), paths
relative to the current directory; --kind filters, --exclude skips qips.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

ASSIGN = re.compile(
    r"set_global_assignment\s+-name\s+(\w+_FILE)\s+"
    r"(?:\[\s*file\s+join\s+\$::quartus\(qip_path\)\s+\"?([^\"\]]+?)\"?\s*\]|\"?([^\s\"]+)\"?)"
)


def resolve(
    path: str, base: str, exclude: set[str], seen: set[str]
) -> list[tuple[str, str]]:
    """Expand one file list; relative entries resolve against base or the qip's dir."""
    out: list[tuple[str, str]] = []
    real = os.path.realpath(path)
    if real in seen:
        return out
    seen.add(real)
    here = os.path.dirname(path)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    for kind, in_qip, plain in ASSIGN.findall(text):
        target = os.path.normpath(
            os.path.join(here, in_qip) if in_qip else os.path.join(base, plain)
        )
        if kind == "QIP_FILE":
            if os.path.basename(target) not in exclude:
                out += resolve(target, base, exclude, seen)
        else:
            out.append((kind, target))
    return out


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("lists", nargs="+", help=".qip or _files.tcl, relative to --base")
    ap.add_argument(
        "--base", default=".", help="project directory (plain paths resolve here)"
    )
    ap.add_argument("--kind", action="append", help="only these assignment kinds")
    ap.add_argument(
        "--exclude", action="append", default=[], help="qip basenames to skip"
    )
    args = ap.parse_args(argv)
    seen: set[str] = set()
    for lst in args.lists:
        for kind, path in resolve(
            os.path.join(args.base, lst), args.base, set(args.exclude), seen
        ):
            if not args.kind or kind in args.kind:
                print(f"{kind}\t{path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
