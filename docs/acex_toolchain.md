# ACEX 1K toolchain (1k30 / 1k100)

The C-One's 1k30 (EP1K30QC208-3) and 1k100 (EP1K100QC208-3) are ACEX 1K
parts. The toolchain is Quartus II 9.0 Web Edition for Windows (9.0 Build
132, the version Minimig V2.01's 1k30 project was last built with), run
under Wine in Docker. The Quartus 9.1 Linux tarball is the Subscription
Edition and ships no ACEX device package, so it cannot be used.

## Input

`reference/90_quartus_free.exe` (Intel FPGA download centre, Archives,
Quartus II Web Edition 9.0, Windows). `scripts/check_assets.sh` validates
it; its checksum is in [reference/README.md](../reference/README.md).

## Image

`docker/quartus90/Dockerfile`, three stages:

| Stage | Contents |
|---|---|
| `wine` | Debian bookworm, `wine` + `wine32` (i386) |
| `extract` | `scripts/isx_unpack.py` splits the InstallShield 11.5 self-extractor into its Disk1 files, `unshield` extracts the `Program Quartus Files` group and the `ACEX1K`/`EP1K*` device groups into `/opt/quartus`; other device families, debug symbols and non-ACEX programming data are removed |
| `quartus` | `/opt/quartus` on top of `wine`, an initialised win32 prefix for uid 1000 |

No InstallShield script runs, so the install needs no display, no response
file and no registry. The installer reaches the build only as a bind
mount of the named build context `installer`; it is never part of a layer.
The image tag is a hash of the Dockerfile and `isx_unpack.py`, so a recipe
change builds a new image.

## Usage

```
scripts/build_acex.sh --image-only                       # build the image (first use does this too)
scripts/build_acex.sh [--out DIR] [--compare FILE]... PROJECT_DIR REVISION
```

The project directory (without `db/` and `incremental_db/`) is streamed into
a container, `quartus_map`, `quartus_fit`, `quartus_asm` and `quartus_tan`
run in turn with `--write_settings_files=off`, and the whole directory comes
back into `--out` (default: the project directory). Each stage prints a
progress line with its run time; the Quartus log is `REVISION.wine.log`.
The fit and timing summaries, the `.rbf` size and any `--compare` byte
difference counts are printed at the end. Docker bind mounts are not used,
so the project may live anywhere.

`docker/quartus90/smoke` is a counter + EAB RAM design with one revision
per device:

```
scripts/build_acex.sh --out build/acex_smoke docker/quartus90/smoke ep1k30
scripts/build_acex.sh --out build/acex_smoke docker/quartus90/smoke ep1k100
```

## Minimig 1k30 rebuild

```
mkdir -p build/minimig && cd build/minimig
unzip -o ../../reference/C1minimigV201_source.zip '1k30/*'
unzip -o ../../reference/C1minimigV201_build.zip v2.01/c1dcores/minimig/support.bin
cd ../..
scripts/build_acex.sh --out build/minimig/out \
    --compare build/minimig/v2.01/c1dcores/minimig/support.bin \
    --compare build/minimig/1k30/ehle.rbf build/minimig/1k30 ehle
```

The result is byte-identical to `support.bin` from `C1minimigV201_build.zip`
(59215 bytes, 167 of 1728 LEs, 72 pins, no EAB bits). `1k30/ehle.rbf` in the
source zip predates the last `gdemux.tdf` change and differs. The project's
blanket 5 ns tsu/tco/tpd and 100 MHz fmax requirements are placeholders and
are not met (`sysclk` reaches 40.98 MHz).

## CI

The `acex` job builds the `wine` stage on every push. The smoke builds run
only where `reference/90_quartus_free.exe` is present (a self-hosted runner),
and are reported as skipped otherwise.
