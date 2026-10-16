#!/usr/bin/env python3
"""Diff a Quartus II .pin report against Quartus Tcl pin assignments."""

import argparse
import re
import sys
from typing import NamedTuple

USER_DIRS = frozenset({"input", "output", "bidir"})
RESERVED_RE = re.compile(
    r"^(?:GND|VCC|RESERVED|~|MSEL|NC$|n(?:CONFIG|STATUS|CEO?|CSO)$"
    r"|CONF_DONE$|DCLK$|DATA\d$|ASDO$|T(?:CK|DI|DO|MS)$)"
)
LOC_RE = re.compile(
    r"^\s*set_location_assignment\s+PIN_(\S+)\s+-to\s+[{\"]?([^\s;}\"]+)", re.M
)
VIRT_RE = re.compile(
    r"^\s*set_instance_assignment\s+-name\s+VIRTUAL_PIN\s+ON\s+-to\s+"
    r"[{\"]?([^\s;}\"]+)",
    re.M,
)

# category -> (severity, heading, line format)
CATEGORIES = {
    "moved": ("ERROR", "location differs", "{0}: ours PIN_{1}, .pin PIN_{2}"),
    "on_reserved": (
        "ERROR",
        "assigned to non-user pin",
        "{0} at PIN_{1} is {2}",
    ),
    "renamed": ("INFO", "different name at same pin", "{0} -> {1} at PIN_{2}"),
    "unassigned": ("WARN", ".pin user signal not assigned", "{0} at PIN_{1}"),
    "missing": ("WARN", "assigned name absent from .pin", "{0} at PIN_{1}"),
    "virtual": ("INFO", "virtual pin", "{0}: unplaced, take location from .pin"),
}


class ParseError(ValueError):
    """Raised when an input file cannot be parsed."""


class PinRow(NamedTuple):
    """One row of a .pin table."""

    name: str
    loc: str
    direction: str

    @property
    def user(self):
        """True for a user I/O signal rather than power/config/reserved."""
        return self.direction in USER_DIRS and not RESERVED_RE.match(self.name)


def _norm(text):
    return " ".join(text.split())


def _key(text):
    return re.sub(r"[^a-z0-9]", "", text.lower())


def loc_key(loc):
    """Natural sort key: '9' < '10', 'A2' < 'A10'."""
    return [int(p) if i % 2 else p for i, p in enumerate(re.split(r"(\d+)", loc))]


def parse_pin_file(path):
    """Return the PinRow list of a Quartus .pin report."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    for i, line in enumerate(lines):
        cols = [_key(c) for c in line.split(":")]
        if cols[0] == "pinnameusage" and "location" in cols and "dir" in cols:
            break
    else:
        raise ParseError(f"{path}: no pin table header found")
    iloc, idir = cols.index("location"), cols.index("dir")
    rows = []
    for line in lines[i + 1 :]:
        fields = [_norm(f) for f in line.split(":")]
        if len(fields) > max(iloc, idir) and fields[0] and fields[iloc]:
            rows.append(PinRow(fields[0], fields[iloc], fields[idir].lower()))
    return rows


def parse_tcl(path):
    """Return ({name: location}, [virtual pin names]) from a Quartus Tcl file."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    return {n: loc for loc, n in LOC_RE.findall(text)}, VIRT_RE.findall(text)


def parse_aliases(pairs=(), files=()):
    """Build {ours: theirs} from 'ours=theirs' strings and 'ours theirs' files."""
    items = [p.split("=", 1) for p in pairs]
    for path in files:
        with open(path, encoding="utf-8") as fh:
            items += [ln.split("#", 1)[0].split() for ln in fh]
    items = [i for i in items if i]
    if any(len(i) != 2 for i in items):
        raise ParseError(f"bad alias entry in {items}")
    return {_norm(a): _norm(b) for a, b in items}


def diff(rows, ours, virtual=(), aliases=None):
    """Compare .pin rows with our {name: loc}; return {category: [tuple]}."""
    aliases = aliases or {}
    by_name = {r.name: r for r in rows}
    by_loc = {r.loc: r for r in rows}
    used = set(ours.values())
    out = {c: [] for c in CATEGORIES}
    for name, loc in sorted(ours.items(), key=lambda kv: loc_key(kv[1])):
        theirs = aliases.get(name, name)
        named, here = by_name.get(theirs), by_loc.get(loc)
        if named and named.loc != loc:
            out["moved"].append((name, loc, named.loc))
        if here and not here.user:
            out["on_reserved"].append((name, loc, here.name))
        elif here and here.name != theirs:
            out["renamed"].append((name, here.name, loc))
        if not named and not (here and here.user):
            out["missing"].append((name, loc))
    out["unassigned"] = [
        (r.name, r.loc)
        for r in sorted(rows, key=lambda r: loc_key(r.loc))
        if r.user and r.loc not in used
    ]
    out["virtual"] = [(v,) for v in sorted(virtual)]
    return out


def report(result):
    """Render a diff result as text lines."""
    lines = []
    for cat, (sev, heading, fmt) in CATEGORIES.items():
        if result[cat]:
            lines.append(f"{sev}: {heading} ({len(result[cat])})")
            lines += [f"  {fmt.format(*item)}" for item in result[cat]]
    return lines


def exit_status(result, strict=False):
    """0 when clean, 1 on ERROR (or WARN when strict)."""
    fail = {"ERROR", "WARN"} if strict else {"ERROR"}
    return int(any(result[c] for c, v in CATEGORIES.items() if v[0] in fail))


def main(argv=None):
    """Command line entry point."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("pinfile")
    ap.add_argument("tclfile")
    ap.add_argument("--alias", action="append", default=[], metavar="OURS=THEIRS")
    ap.add_argument("--alias-file", action="append", default=[], metavar="PATH")
    ap.add_argument("--strict", action="store_true", help="WARN also fails")
    args = ap.parse_args(argv)
    try:
        rows = parse_pin_file(args.pinfile)
        ours, virtual = parse_tcl(args.tclfile)
        aliases = parse_aliases(args.alias, args.alias_file)
    except (OSError, ParseError) as exc:
        print(f"verify_pins: {exc}", file=sys.stderr)
        return 2
    result = diff(rows, ours, virtual, aliases)
    print(
        f"{len(rows)} .pin rows ({sum(r.user for r in rows)} user), "
        f"{len(ours)} assignments, {len(virtual)} virtual"
    )
    print("\n".join(report(result)))
    return exit_status(result, args.strict)


if __name__ == "__main__":
    sys.exit(main())
