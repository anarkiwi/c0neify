
Hi All,

This is vhdl example code with a Quartus project to show how to reconfigure
the 1k30 fpga from the 1k100 side. The algorithm is described in the
cone_core_development manual that you can download from:
http://www.syntiac.com/pdf/cone_core_development.pdf

Start quartus and compile. The resulting "reconfig1k30_example.rbf" should
be copied to the CF card as "target.rbf". If done right this file is
166965 bytes in size. This code will run on the 1k100 FPGA and reconfigures
the 1k30 from SRAM. You need to have the red PCB with SRAM and WDC 65816
installed in the CPU-Slot.

Further you need to copy "support.rbf" from the chameleon or FPGA-64 newboot
release (download one of these from http://www.syntiac.com/c_one.html).
This core is needed to fill the SRAM with data from the CF card.
The example given is only for the reconfiguration process itself, the data
must already be present in the SRAM.

And ofcourse you need to have a (custom) 1k30 image. The .rbf file must
be copied to the CF card as "support.bin" (notice the extension difference!).
If done right this file is 59215 bytes in size.

Add a select.txt with proper description and try it out on the C-One!

Good luck,
Peter Wendrich

