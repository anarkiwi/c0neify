"""Tests for scripts/isx_unpack.py."""

# pylint: disable=missing-function-docstring

import struct
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import isx_unpack  # pylint: disable=wrong-import-position

FILES = [
    ("data1.hdr", "Disk1\\data1.hdr", "0.0.0.0", b"ISc(" + bytes(range(60))),
    ("setup.exe", "Disk1\\setup.exe", "11.50.0.42618", b"MZ" * 3),
    ("empty.bin", "Disk1\\empty.bin", "0.0.0.0", b""),
]


def pe(raw_end=0x400, sections=((0x200, 0x100), (0x300, 0x100)), opt=0xE0):
    """A minimal PE image whose last section ends at raw_end."""
    head = bytearray(0x80)
    head[:2] = b"MZ"
    struct.pack_into("<I", head, 0x3C, 0x80)
    head += b"PE\0\0" + struct.pack("<HHIIIHH", 0x14C, len(sections), 0, 0, 0, opt, 0)
    head += bytes(opt)
    for ptr, size in sections:
        head += struct.pack("<8sIIII16x", b".text", size, 0, size, ptr)
    return bytes(head.ljust(raw_end, b"\xcc"))


def entry(name, path, version, data, size=None):
    fields = (name, path, version, str(len(data) if size is None else size))
    return b"".join(f.encode() + b"\0" for f in fields) + data


def write(tmp_path, body, image=None):
    exe = tmp_path / "setup.exe"
    exe.write_bytes((pe() if image is None else image) + body)
    return exe


def test_overlay_offset_is_end_of_last_section(tmp_path):
    exe = write(tmp_path, b"", pe(raw_end=0x700, sections=((0x600, 0x100),)))
    with exe.open("rb") as f:
        assert isx_unpack.overlay_offset(f) == 0x700


def test_extract_round_trip(tmp_path):
    exe = write(tmp_path, b"".join(entry(*e) for e in FILES))
    found = isx_unpack.extract(exe, tmp_path / "out", quiet=True)
    assert [(n, p, v, s) for n, p, v, _, s in found] == [
        (n, p, v, len(d)) for n, p, v, d in FILES
    ]
    for name, _, _, data in FILES:
        assert (tmp_path / "out" / name).read_bytes() == data


def test_large_entry_spans_chunks(tmp_path, monkeypatch):
    monkeypatch.setattr(isx_unpack, "CHUNK", 7)
    data = bytes(range(256)) * 3
    exe = write(tmp_path, entry("data2.cab", "Disk1\\data2.cab", "0", data))
    isx_unpack.extract(exe, tmp_path / "out", quiet=True)
    assert (tmp_path / "out" / "data2.cab").read_bytes() == data


@pytest.mark.parametrize(
    "body,image,message",
    [
        (b"", b"ZM" + bytes(100), "not an MZ"),
        (b"", pe()[:0x80] + b"XX\0\0" + bytes(0x200), "no PE header"),
        (b"", pe()[:0x90], "no PE header"),
        (b"", pe(opt=0x1000)[:0x200], "truncated section table"),
        (entry("a", "b", "c", b"xyz", size="12x"), None, "bad size"),
        (entry("..", "b", "c", b"x"), None, "unsafe file name"),
        (entry("a/b", "b", "c", b"x"), None, "unsafe file name"),
        (entry("C:x", "b", "c", b"x"), None, "unsafe file name"),
        (entry("a", "b", "c", b"x", size=99), None, "runs past end"),
        (b"name\0path", None, "truncated entry header"),
        (b"n" * 2000, None, "too long"),
    ],
)
def test_format_errors(tmp_path, body, image, message):
    exe = write(tmp_path, body, image)
    with exe.open("rb") as f, pytest.raises(isx_unpack.FormatError, match=message):
        list(isx_unpack.entries(f))


def test_cli_list_and_extract(tmp_path, capsys):
    exe = write(tmp_path, b"".join(entry(*e) for e in FILES))
    assert isx_unpack.main([str(exe)]) == 0
    lines = capsys.readouterr().out.splitlines()
    assert [line.split()[-1] for line in lines] == [p for _, p, _, _ in FILES]
    assert lines[1].split()[:2] == ["6", "11.50.0.42618"]
    assert not (tmp_path / "out").exists()
    assert isx_unpack.main([str(exe), str(tmp_path / "out"), "-q"]) == 0
    assert sorted(p.name for p in (tmp_path / "out").iterdir()) == sorted(
        n for n, _, _, _ in FILES
    )


def test_cli_errors(tmp_path, capsys):
    assert isx_unpack.main([str(tmp_path / "absent.exe")]) == 1
    exe = write(tmp_path, b"", b"PK\3\4" + bytes(80))
    assert isx_unpack.main([str(exe), str(tmp_path / "out")]) == 1
    assert "not an MZ executable" in capsys.readouterr().err
