# vid-bus protocol (fallback)

The board target uses Minimig's link ([minimig_link.md](minimig_link.md)).
This protocol is kept in `fallback/` for a custom 1k30 image (BLOCKED.md
#4) and still runs in simulation. Extender side: `fallback/cone_io.vhd`.
1k30 side: `fallback/cone_1k30_mux_slave.vhd`. The header of `cone_io.vhd`
is the normative description; this page adds the timing analysis and the
simulation results.

## Lines

| vid | direction | use |
|---|---|---|
| 3:0 | 1k30 -> extender (extender input-only, CLK4..7) | q |
| 7:4 | extender -> 1k30 | d |
| 10:8, 15 | extender -> 1k30 | sel[2:0], sel[3] |
| 14 | extender -> 1k30 | mux_clk |
| 13:11 | extender input-only | unused, undriven |

## Slot map

| sel | slot | d (extender -> 1k30) | q (1k30 -> extender) |
|---|---|---|---|
| 0 | SPI | {-, cs_n, mosi, sck} | {-, cd_n, wp, miso} |
| 1 | PS/2 | {mdat, mclk, kdat, kclk} | {mdat, mclk, kdat, kclk} |
| 2 | joy A lo | - | {right, left, down, up} (active low) |
| 3 | joy A hi | - | {-, -, fire2, fire1} |
| 4 | joy B lo | - | {right, left, down, up} |
| 5 | joy B hi | - | {-, -, fire2, fire1} |
| 6 | misc | {-, -, led_red, led_green} | {-, -, menu_n, reset_n} |
| 7..15 | reserved | | |

Sequence: SPI, 1, SPI, 2, SPI, 3, SPI, 4, SPI, 5, SPI, 6 (12 slots, one
per mux_clk period).

## Timing

`clk_mux` = hostclocks c0 (100.23 MHz, period Tc). Generics of `cone_io`:

| generic | meaning | template |
|---|---|---|
| `MUX_DIV` | Tc per mux_clk half period | 2 (mux_clk 25 MHz) |
| `Q_LAT` | Tc from launching mux_clk high to sampling q | 2 |
| `MISO_VISITS` | SPI slots after a falling SCK edge before MISO is trusted | 1 |

* sel/d are launched with the falling edge of mux_clk and captured by the
  slave on the rising edge: MUX_DIV x Tc of setup and hold, less the
  sel/d-vs-mux_clk skew.
* q for a slot is valid at the extender from `rise + rt` (rt = round trip
  extender -> 1k30 -> extender, including both tCO) for one mux_clk period.
  With a capture margin m it is sampled correctly iff
  `rt + m <= Q_LAT x Tc` and `Q_LAT x Tc + m < 2 x MUX_DIV x Tc + rt`.
* The slave samples MISO in the SPI slot MISO_VISITS after the one that
  carried the falling edge, `2 x MUX_DIV x Tc x 2 x MISO_VISITS` later, so
  the card + relay delay must be below that.
* SPI acks: SCK high is acked when launched; SCK low only once the
  qualifying MISO sample is back; CS changes take an SPI slot of their own,
  ordered after a pending rising edge and before a pending falling edge.

rt and the MISO relay delay on a real C-One are not yet measured
(`BLOCKED.md`); the template values leave room for rt up to about 19 ns
and MISO delay up to about 80 ns.

## Simulation

`scripts/sim.sh` builds `fallback/tb_vidbus.vhd` with GHDL and runs its
nominal cases (`vidbus_*`; `--vidbus-sweep` adds the sweep) from
`scripts/run_sim.py`. The testbench puts both
modules back to back over 16 delayed wires, with the extender's
input-only lines driven only from the 1k30 side, and checks:

* every SPI byte both ways under CS bursts, driven by DeMiSTify's
  `spi_controller` (or `sim/models/spi_controller_model.vhd` when the
  submodule is absent) with substitute_mcu's external-clock ack
  synchroniser, against a card model that answers a known stream;
* that every falling-edge ack is raised only once `spi_miso` carries the
  card's bit for that edge, and that CS never moves with SCK;
* every PS/2 edge of a make/break sequence at the fastest PS/2 clock,
  decoded at the extender, plus the host inhibit path;
* joystick, button (also through `cone_mergeinputs`) and LED values within
  20 slots;
* setup/hold of 1 ns at both capture points, no contention on any vid line,
  and the hostclocks periods and alignment.

Nominal cases must pass. Sweep cases vary rt (0..45 ns) for every
`Q_LAT` in `1..2 x MUX_DIV + 1` and the MISO delay (0..160 ns) for
`MISO_VISITS` 1 and 2; each outcome must equal the window prediction
above.

Results (`scripts/sim.sh`, model spi_controller, 64 bytes in 4 bursts;
throughput includes CS gaps):

| case | slot | SCK | throughput | PS/2 latency min / mean / max | joystick/LED latency max |
|---|---|---|---|---|---|
| MUX_DIV 1, Q_LAT 1, rt 0 | 20 ns | 4.18 MHz | 504 kB/s | 59 / 181 / 297 ns | 298 ns |
| MUX_DIV 1, Q_LAT 2, rt 12 ns | 20 ns | 4.18 MHz | 504 kB/s | 63 / 185 / 301 ns | 307 ns |
| MUX_DIV 1, MISO 60 ns, MISO_VISITS 2 | 20 ns | 3.58 MHz | 434 kB/s | 59 / 181 / 297 ns | 298 ns |
| MUX_DIV 2, Q_LAT 2, rt 0 (template) | 40 ns | 3.13 MHz | 381 kB/s | 110 / 341 / 581 ns | 587 ns |
| MUX_DIV 2, Q_LAT 2, rt 12 ns, skew 3 ns, MISO 30 ns | 40 ns | 3.13 MHz | 381 kB/s | 104 / 335 / 575 ns | 587 ns |

Sweep: 188/188 outcomes match the predicted windows.

The draft protocol this replaced fails the same testbench: sel/d changed
on the same clk_mux edge that raised mux_clk (slave hold violation), and
the falling-edge SPI ack preceded the MISO round trip (wrong bytes even
with zero wire delay).
