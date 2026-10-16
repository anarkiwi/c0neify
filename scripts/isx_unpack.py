#!/usr/bin/env python3
"""Unpack the Disk1 files appended to an InstallShield 11.x setup.exe.

The data after the last PE section is a run of entries, each
``name NUL path NUL version NUL decimal-size NUL`` followed by ``size`` bytes.
The cabinets it yields (data1.hdr, data*.cab) are read by unshield.
"""

import argparse
import os
import struct
import sys

from tqdm import tqdm

CHUNK = 1 << 22
MAX_FIELD = 1024


class FormatError(ValueError):
    """The input is not a supported InstallShield self-extractor."""


def overlay_offset(f):
    """Return the file offset just past the last PE section's raw data."""
    f.seek(0)
    mz = f.read(64)
    if len(mz) < 64 or mz[:2] != b"MZ":
        raise FormatError("not an MZ executable")
    (pe,) = struct.unpack_from("<I", mz, 0x3C)
    f.seek(pe)
    hdr = f.read(24)
    if len(hdr) < 24 or hdr[:4] != b"PE\0\0":
        raise FormatError("no PE header")
    nsec, opt = struct.unpack_from("<H12xH", hdr, 6)
    f.seek(pe + 24 + opt)
    table = f.read(40 * nsec)
    if len(table) < 40 * nsec:
        raise FormatError("truncated section table")
    return max(
        (sum(struct.unpack_from("<II", table, 40 * i + 16)) for i in range(nsec)),
        default=0,
    )


def _field(f):
    out = bytearray()
    while len(out) <= MAX_FIELD:
        c = f.read(1)
        if not c:
            raise FormatError("truncated entry header")
        if c == b"\0":
            return out.decode("latin-1")
        out += c
    raise FormatError("entry header field too long")


def entries(f):
    """Yield (name, path, version, offset, size) for every appended file."""
    end = f.seek(0, os.SEEK_END)
    pos = overlay_offset(f)
    while pos < end:
        f.seek(pos)
        name, path, version, size = (_field(f) for _ in range(4))
        if not size.isdigit():
            raise FormatError(f"bad size {size!r} for {name!r}")
        if not name or name in (".", "..") or any(c in name for c in "/\\:"):
            raise FormatError(f"unsafe file name {name!r}")
        pos = f.tell() + int(size)
        if pos > end:
            raise FormatError(f"{name} runs past end of file")
        yield name, path, version, f.tell(), int(size)


def extract(src, outdir, quiet=False):
    """Write every appended file into outdir; return the entry list."""
    os.makedirs(outdir, exist_ok=True)
    with open(src, "rb") as f:
        found = list(entries(f))
        total = sum(e[4] for e in found)
        with tqdm(
            total=total, unit="B", unit_scale=True, disable=quiet, desc="unpack"
        ) as progress:
            for name, _, _, off, size in found:
                f.seek(off)
                with open(os.path.join(outdir, name), "wb") as out:
                    while size:
                        buf = f.read(min(size, CHUNK))
                        out.write(buf)
                        size -= len(buf)
                        progress.update(len(buf))
    return found


def main(argv=None):
    """CLI entry point."""
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("setup", help="InstallShield self-extracting setup.exe")
    ap.add_argument("outdir", nargs="?", help="extract here (omit to list)")
    ap.add_argument("-q", "--quiet", action="store_true", help="no progress bar")
    args = ap.parse_args(argv)
    try:
        if args.outdir:
            found = extract(args.setup, args.outdir, args.quiet)
        else:
            with open(args.setup, "rb") as f:
                found = list(entries(f))
    except (OSError, FormatError) as e:
        print(f"{args.setup}: {e}", file=sys.stderr)
        return 1
    for name, path, version, _, size in found:
        print(f"{size:>12}  {version:<16} {path or name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
