# BLOCKED

Gaps that only a gated file or a hardware measurement can close. Paths are
relative to the repo root; `scripts/check_assets.sh` shows current state.

| # | Gap | Unblocked by | Stub / current behaviour |
|---|---|---|---|
| 1 | Extender pins unverified against the board's own pin report | `reference/C1_extender.pin` | `cone_ext_pins.tcl` from the Wendrich manual; `verify_pins.py` skipped in lint |
| 2 | Audio DAC pins `sigma_l`/`sigma_r` | `reference/C1_extender.pin`, `reference/C1_extender_schem.pdf` | `VIRTUAL_PIN ON` in `cone_ext_pins.tcl` |
| 3 | SDRAM part number, timing macros, nCS/CKE wiring | `reference/C1_extender_schem.pdf` | generic placeholder timings in `cone_ext_support.tcl` |
| 4 | Input-only vid lines (manual says vid[3:0], vid[13:11]) | `reference/C1_extender.pin`, `reference/C1_extender_schem.pdf` | as manual |
| 5 | Citation source for the pin table | `reference/Cone_core_development.pdf` | draft citations unchecked |
| 6 | Minimig vid-bus protocol comparison; 1k30/1k100 sources | `reference/C1minimigV201_source.zip` | own protocol (`docs/vidbus.md`) |
| 7 | Prebuilt 1k100/1k30 images for the CF card | `reference/C1minimigV201_build.zip` | `make_cfcard.sh` writes `*.MISSING` placeholders |
| 8 | NewBoot CF layout | `reference/NewbootV201.zip` | layout from the manual (`docs/architecture.md`) |
| 9 | Synthesis, fit, timing | `reference/QuartusSetupWeb-13.1.0.162.run` + `reference/cyclone_web-13.1.0.162.qdz` (or the 13.0.1.232 pair) | `install_quartus.sh` skips; CI `synth` job skips |
| 10 | vid-bus round trip and MISO relay delay on a real board | measurement on hardware (or ACEX/board timing data) | template `MUX_DIV 2, Q_LAT 2, MISO_VISITS 1`: tolerates rt up to about 19 ns, MISO delay up to about 80 ns |
