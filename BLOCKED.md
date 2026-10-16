# BLOCKED

Gaps that only a gated file or a hardware measurement can close. Paths are
relative to the repo root; `scripts/check_assets.sh` shows current state.

## Open

| # | Gap | Unblocked by | Stub / current behaviour |
|---|---|---|---|
| 1 | NewBoot CF layout and boot behaviour | `reference/NewbootV201.zip` (the file supplied is the wiki's HTML page, reported `invalid`; the zip is behind the page's download link) | layout from the manual (`docs/architecture.md`), cross-checked against `C1minimigV201_build.zip` |
| 2 | SDRAM timing macros for the fitted Samsung K4S281632-UC60 | its datasheet, e.g. `reference/K4S281632.pdf` | generic placeholders in `cone_ext_support.tcl` (CL3, tRC 66 ns, tRP 15 ns, tWR 2); the BBC core uses its own controller |
| 3 | vid-bus round trip and MISO relay delay | measurement on hardware, or EP1K30QC208-3 and board timing data | template `MUX_DIV 2, Q_LAT 2, MISO_VISITS 1`: tolerates rt up to about 19 ns, MISO delay up to about 80 ns; SDC uses placeholder 0.5 ns I/O delays |
| 4 | (superseded by option B) 1k30 / 1k100 images for our own protocol (`cone_1k30_mux_slave` + gb relay, 1k100 joystick/SD relay) | Quartus II 9.1sp2 with ACEX 1K support: `reference/91sp2_quartus_free_linux.tar` | none built; see `docs/protocol_decision.md` |
| 5 | Stereo placement of `sigma_l`/`sigma_r` (SID1/SID2 external audio inputs) | `reference/C1schematics.pdf` mixer section | sigma1 -> `sigma_l`, sigma2 -> `sigma_r` |

## Closed

| Gap | Closed by |
|---|---|
| Extender pins unverified | `reference/C1_extender.pin`: all 82 assignments at the same locations (`verify_pins.py --strict` with `Board/cone_ext/pin_aliases.txt`, run in lint) |
| Audio DAC pins | `reference/C1_extender.pin` and `C1_extender_schem.pdf`: sigma1 PIN_10, sigma2 PIN_11 |
| SDRAM part, nCS/CKE | `reference/C1_extender_schem.pdf`: K4S281632-UC60, CKE tied to V33, nCS to ground |
| Input-only vid lines | Quartus 13.1 device database: vid[3:0], vid[13:11] input-only as the manual says; also mdb[7:5] (not in the manual) |
| Synthesis toolchain | `reference/QuartusSetupWeb-13.1.0.162.run` + `cyclone_web-13.1.0.162.qdz`, installed by `scripts/install_quartus.sh` |
| Minimig protocol comparison | `reference/C1minimigV201_source.zip` (`docs/protocol_decision.md`) |
