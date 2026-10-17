# BLOCKED

Gaps that only a gated file or a hardware measurement can close. Paths are
relative to the repo root; `scripts/check_assets.sh` shows current state.

## Open

| # | Gap | Unblocked by | Stub / current behaviour |
|---|---|---|---|
| 2 | The BBC core's own `sdram.v` runs the SDRAM at CAS latency 2 (48.16 MHz); the K4S281632F -60 grade specifies CL3 only. The same die's -75 parts are CL2-rated at 10 ns, so CL2 at 20.8 ns is expected to work but is outside the -60 datasheet | a hardware test, or a core patch moving `sdram.v` to CL3 | CL2 as in the MiST core |
| 3 | vid-bus round trip (IOclk out to vid[3:0]/vid[13] in) and data-vs-IOclk skew at the 1k30 | measurement on hardware, or EP1K30QC208-3 and board timing data | `cone_mm_link` tolerates 1 < rt <= 18.95 ns and skew <= 13.9 ns with 1 ns margins in simulation (Minimig's own 56.75 MHz link allows rt < 17.6 ns); SDC uses placeholder 0.5 ns I/O delays ([minimig_link.md](docs/minimig_link.md)) |
| 4 | (superseded by option B) 1k30 / 1k100 images for our own protocol (`cone_1k30_mux_slave` + gb relay, 1k100 joystick/SD relay) | design work only: the ACEX toolchain is `scripts/build_acex.sh` (Quartus II 9.0 Web Edition under Wine, `reference/90_quartus_free.exe`, [acex_toolchain.md](docs/acex_toolchain.md)); the Quartus 9.1 Linux tarball is subscription-licensed and has no ACEX package | none built; see `docs/protocol_decision.md` |
| 5 | Stereo placement of `sigma_l`/`sigma_r` (SID1/SID2 external audio inputs) | `reference/C1schematics.pdf` mixer section, or a listening test | sigma1 -> `sigma_l`, sigma2 -> `sigma_r`; Wendrich's `cone_800x600_test.qsf` names PIN_10 `sigmaL` and PIN_11 `sigmaR` |
| 6 | Minimig's `support.rbf` (1k100, no source) is assumed to load `support.bin` and relay the CPLD joystick stream on gb[5] as `Gbridge.tdf` does | running it on a C-One ([programming.md](docs/programming.md), bring-up step 3) | joysticks rebuilt as `cyclone.vhd` does; PS/2 and CF do not depend on it. `Gbridge.tdf:124-135` (byte-identical in `Bigpicview.zip`) puts `ioshift` on gb[5], so any GBridge-based 1k100 core relays the stream |

## Closed

| Gap | Closed by |
|---|---|
| Extender pins unverified | `reference/C1_extender.pin`: all 82 assignments at the same locations (`verify_pins.py --strict` with `Board/cone_ext/pin_aliases.txt`, run in lint) |
| Audio DAC pins | `reference/C1_extender.pin` and `C1_extender_schem.pdf`: sigma1 PIN_10, sigma2 PIN_11 |
| SDRAM timing macros | `reference/K4S280432F-UC.PDF` (K4S281632F -60): CL3, tRC 60 ns, tRP 18 ns, tRDL 2 CLK in `cone_ext_support.tcl`; no CL2 rating, so `SDRAM_tCKminCL2` is undefined |
| SDRAM part, nCS/CKE | `reference/C1_extender_schem.pdf`: K4S281632-UC60, CKE tied to V33, nCS to ground |
| Input-only vid lines | Quartus 13.1 device database: vid[3:0], vid[13:11] input-only as the manual says; also mdb[7:5] (not in the manual) |
| Synthesis toolchain | `reference/QuartusSetupWeb-13.1.0.162.run` + `cyclone_web-13.1.0.162.qdz`, installed by `scripts/install_quartus.sh` |
| NewBoot CF layout | `reference/NewbootV201.zip`: card root, `c1dcores/<core>/` with `select.raw`/`select.txt`, bypass `extender.rbf` (`docs/hardware.md`) |
| ACEX 1K toolchain | `reference/90_quartus_free.exe`: `scripts/build_acex.sh` rebuilds Minimig's 1k30 byte-identical to `support.bin`; EP1K100QC208-3 fits ([acex_toolchain.md](docs/acex_toolchain.md)) |
| Minimig protocol comparison | `reference/C1minimigV201_source.zip` (`docs/protocol_decision.md`) |
| Extender side of Minimig's link, cycle for cycle | `reference/C1minimigV201_source.zip`: `scripts/sim.sh` runs `tb_mmlink` against the extracted `1k30/acex.vhd` (`acex_*` cases) |
