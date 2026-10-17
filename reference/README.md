# reference/

Gated inputs that cannot be redistributed, and the original archives of
the GPL/LGPL files vendored in [third_party/](../third_party/README.md)
(`vendored` in `scripts/assets.tsv`, kept as provenance). Everything here
except this file is gitignored; every script degrades gracefully when a
file is absent.
`scripts/check_assets.sh` (`--json`, `--require NAME`) reports what is
present; the list lives in `scripts/assets.tsv`.

| File | Source | Unblocks |
|---|---|---|
| `C1_extender.pin` | iComp wiki, C-One page | pin verification (`scripts/verify_pins.py`, `scripts/lint.sh`) |
| `C1_extender_schem.pdf` | iComp wiki, C-One page | audio DAC pins, SDRAM part number, nCS/CKE wiring |
| `Cone_core_development.pdf` | Peter Wendrich, *C-One core development* (syntiac.com, mirrored on the iComp wiki) | pin table, SDRAM/VGA/PS/2, reconfiguration sequence |
| `A1k100.pin`, `A1k30.pin` | iComp wiki, C-One page | pin assignments for the 1k100 / 1k30 support cores |
| `Gbridge.tdf` | iComp wiki, C-One page | 1k100/1k30 gb[] bridge reference |
| `C1schematics.pdf` | iComp wiki, C-One page | PS/2, CPLD and IDE/CF wiring on the main board |
| `C1minimigV201_source.zip` (vendored) | iComp wiki, C-One page | provenance of `third_party/C1minimigV201_source/`; `1k30/gdemux.tdf` for the 1k30 rebuild |
| `C1minimigV201_build.zip` | iComp wiki, C-One page | prebuilt `support.rbf` / `support.bin` (`scripts/make_cfcard.sh`) |
| `NewbootV201.zip` | iComp wiki, `File:NewbootV201.zip` page, download link (not the page itself) | NewBoot CF card layout |
| `QuartusSetupWeb-13.1.0.162.run` | Intel FPGA download centre: Archives, Quartus II Web Edition 13.1, Individual Files tab | synthesis (`scripts/install_quartus.sh`) |
| `cyclone_web-13.1.0.162.qdz` | same Individual Files tab | Cyclone III/IV device support for 13.1 |
| `QuartusSetupWeb-13.0.1.232.run` | Intel FPGA download centre: Archives, Quartus II Web Edition 13.0sp1, Individual Files tab | alternative toolchain |
| `cyclone_web-13.0.1.232.qdz` | same Individual Files tab | Cyclone device support for 13.0sp1 |
| `90_quartus_free.exe` (optional) | Intel FPGA download centre: Archives, Quartus II Web Edition 9.0, Windows | ACEX 1K (1k30/1k100) builds (`scripts/build_acex.sh`, [docs/acex_toolchain.md](../docs/acex_toolchain.md)) |
| `Minimig_source211108.zip` (optional) | iComp wiki / syntiac.com C-One downloads | Minimig 2008 source (extender, 1k30, NTSC) |
| `Snapshot_ver1.26.zip` (optional) | iComp wiki / syntiac.com C-One downloads | Minimig snapshot: extender and 1k30 projects |
| `Symb_cpc_source.zip` (optional) | iComp wiki / syntiac.com C-One downloads | SymbOS CPC: extender and 1k30 projects |
| `VC20_V12.zip` (optional) | iComp wiki / syntiac.com C-One downloads | 1k100 VIC-20 project with GBridge and ioshift |
| `Bigpicview.zip` (optional) | iComp wiki / syntiac.com C-One downloads | 1k100 project with GBridge and SDRAM |
| `Picview.zip` (optional) | iComp wiki / syntiac.com C-One downloads | 1k100 project with GBridge |
| `Pong_chapter1.zip` (optional) | iComp wiki / syntiac.com C-One downloads | 1k100 project with gbmux |
| `reconfig1k30_example.zip` (vendored) | iComp wiki / syntiac.com C-One downloads | provenance of `third_party/reconfig1k30_example/` |
| `cone_800x600_test_v3.zip` (vendored) | iComp wiki / syntiac.com C-One downloads | provenance of `third_party/cone_800x600_test_v3/` |
| `fpga64_029.zip` (optional) | iComp wiki / syntiac.com C-One downloads | FPGA-64 0.29 card files, standard support.rbf loader |
| `libpng12-0_1.2.54-1ubuntu1_i386.deb` (optional) | packages.ubuntu.com, xenial | Quartus 13.x GUI dependency |

`check_assets.sh` reports each file as present, missing or invalid; a
saved HTML page or a file whose leading bytes don't match its type
(zip, PDF, ELF, Windows exe, deb) counts as invalid.

## Quartus version

The extender FPGA is a Cyclone III (EP3C25E144C8), so 13.1 is the primary
toolchain; `install_quartus.sh` falls back to 13.0sp1 (prefix
`/opt/altera/13.0sp1`) when only that installer is present. 13.0sp1 is
the last release supporting Cyclone II.

```
scripts/install_quartus.sh --dry-run   # show apt / installer / prune commands
scripts/install_quartus.sh             # install into /opt/altera/13.1
```

Keep the `.qdz` next to the `.run`: the installer picks up device files
from its own directory.

## NewBoot card

```
scripts/make_cfcard.sh --core NAME --rbf output_files/NAME.rbf --out card/ \
    [--icon select.raw] [--rom FILE]... [--strict]
```

Support files missing from both the command line and
`C1minimigV201_build.zip` become zero-byte `<name>.MISSING` placeholders.

## Checksums of the files used

```
5e950cb854c8584ba43fede650cded40e79534f1fa31ba43a7eb18d61f177ba9  QuartusSetupWeb-13.1.0.162.run
7d65dfa5edf8965dc45b54f34c34b9eef2e7f3a9c293377b4dfe6a4e71845db6  cyclone_web-13.1.0.162.qdz
31c251c8c9e61ed627bcae71af874e40da53bd1df461ad5d2fa747298faaeb5b  90_quartus_free.exe
0e6a1ba036b6dcfb4a717d479fdcba25bff7a7eb485aebf00220857216115df0  C1minimigV201_source.zip
2f457afd2071c6d4c45bc4d66ba0b178c45a0aaf0377f4ac8cedd06407dddf68  reconfig1k30_example.zip
44a403a60f5574e4ff557c7e13face7ae996093e0db8f39a7c7d758257c55d6f  cone_800x600_test_v3.zip
```
