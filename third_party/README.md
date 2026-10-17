# third_party/

Files extracted unchanged from GPL/LGPL C-One source archives, at their
original paths under `third_party/<archive stem>/`, each with the licence
texts and readme shipped in the archive. Only files this repo uses or cites
(and what those need to build) are included. Original archives and their
sources are listed in [reference/README.md](../reference/README.md);
authors in [CREDITS.md](../CREDITS.md).

| Directory | Source archive | sha256 of the archive | Authors | Licence |
|---|---|---|---|---|
| `C1minimigV201_source/` | `C1minimigV201_source.zip` (Minimig V2.01 for the C-One) | `0e6a1ba036b6dcfb4a717d479fdcba25bff7a7eb485aebf00220857216115df0` | Tobias Gubener (C-One port, 1k30 core); Jakub Bednarski (`minimig/Gayle.v`); Minimig by Dennis van Weeren | GPL-3.0-or-later (`gpl.txt`); Quartus-generated project, symbol and megafunction files carry Altera's tool notice |
| `reconfig1k30_example/` | `reconfig1k30_example.zip` | `2f457afd2071c6d4c45bc4d66ba0b178c45a0aaf0377f4ac8cedd06407dddf68` | Peter Wendrich (Syntiac), with Tobias Gubener in `cone_reconfig1k30.vhd` | LGPL-3.0-or-later (`lgpl.txt`, `gpl.txt`) |
| `cone_800x600_test_v3/` | `cone_800x600_test_v3.zip` | `44a403a60f5574e4ff557c7e13face7ae996093e0db8f39a7c7d758257c55d6f` | Peter Wendrich (Syntiac) | LGPL-3.0-or-later (`src/lgpl.txt`, `src/gpl.txt`); `800x600/extender.rbf` is built from `src/` |

Use:

* `C1minimigV201_source/1k30/acex.vhd`: the 1k30 end of Minimig's link in
  `scripts/sim.sh` (`acex_*` cases of `tb_mmlink`).
* `C1minimigV201_source/`: the `src:` citations in
  [docs/minimig_link.md](../docs/minimig_link.md) and
  [docs/protocol_decision.md](../docs/protocol_decision.md).
* `reconfig1k30_example/`: 1k30 reconfiguration from the 1k100
  ([docs/programming.md](../docs/programming.md)).
* `cone_800x600_test_v3/800x600/`: bring-up step 2 core directory;
  `src/` is its source.

Not included: `1k30/gdemux.tdf` (its header reserves all rights, "only for
use in the C-One project", in every archive that has it), so rebuilding
Minimig's 1k30 still needs `reference/C1minimigV201_source.zip`
([docs/acex_toolchain.md](../docs/acex_toolchain.md)); `1k30/ehle.rbf`
(built from `gdemux.tdf`); `C1minimigV201_build.zip` (`support.rbf` has no
source); Windows executables (`hexer.exe`), Quartus workspace files and
reports. Files that nothing here uses stay in the archives.
