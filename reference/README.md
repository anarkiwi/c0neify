# reference/

Gated inputs that cannot be redistributed. Everything here except this
file is gitignored; every script degrades gracefully when a file is absent.
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
| `C1minimigV201_source.zip` | iComp wiki, C-One page | protocol comparison with Minimig; support-core sources |
| `C1minimigV201_build.zip` | iComp wiki, C-One page | prebuilt `support.rbf` / `support.bin` (`scripts/make_cfcard.sh`) |
| `NewbootV201.zip` | iComp wiki, `File:NewbootV201.zip` page, download link (not the page itself) | NewBoot CF card layout |
| `QuartusSetupWeb-13.1.0.162.run` | Intel FPGA download centre: Archives, Quartus II Web Edition 13.1, Individual Files tab | synthesis (`scripts/install_quartus.sh`) |
| `cyclone_web-13.1.0.162.qdz` | same Individual Files tab | Cyclone III/IV device support for 13.1 |
| `QuartusSetupWeb-13.0.1.232.run` | Intel FPGA download centre: Archives, Quartus II Web Edition 13.0sp1, Individual Files tab | alternative toolchain |
| `cyclone_web-13.0.1.232.qdz` | same Individual Files tab | Cyclone device support for 13.0sp1 |
| `91sp2_quartus_free_linux.tar` (optional) | Intel FPGA download centre: Archives, Quartus II Web Edition 9.1sp2 | custom 1k30/1k100 (ACEX 1K) cores |
| `libpng12-0_1.2.54-1ubuntu1_i386.deb` (optional) | packages.ubuntu.com, xenial | Quartus 13.x GUI dependency |

`check_assets.sh` reports each file as present, missing or invalid; a
saved HTML page or a file whose leading bytes don't match its type
(zip, PDF, ELF, tar, deb) counts as invalid.

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
