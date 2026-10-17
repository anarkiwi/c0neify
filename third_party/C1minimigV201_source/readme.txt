Tobias Gubener has done it again!

This is the Minimig V2.01 core for the C-One. Features include:

    * emulation of four floppy drives (DF0: to DF3:)
    * emulation of two harddrives using two image files of up to 4GB each
    * FAT16 or FAT32 supported for the CF card
    * long filenames for ADF images allowed
    * max. memory 11.5MB: 2MB chipmem, 1.5MB slowmem and up to 8MB fast at the same time!
    * horizontal and vertical image interpolation in VGA 31kHz mode
    * scanline effect emulation like on Indivision flickerfixers 

**bugfix: random keypresses in OSD menu fixed now (minor issue fixed in 1k30 FPGA).

While some of these features cannot be used on the original Minimig hardware at all,
others are possible using Jakub's ARM board as a replacement for the PIC chip.
However, Tobias' implementation uses a different approach: A second instance of the
68000 processor replaces the ARM processor. This makes the C-One with FPGA extender
the best-equipped Minimig on the market!

Kickstart roms and harddrive images must be placed in the root directory of the core. ADF
files can be placed anywhere in subdirectories.

If the core is launched from a subdirectory, a config file is being loaded from there. This
configfile contains information about the memory layout, name of the Kickstart rom and names
of the harddrive image files. ADF files must be attached during runtime through the OSD using
the known key combinations. However, if files names DF0.ADF, DF1.ADF, DF2.ADF or DF3.ADF are
found in the core directory, they are "inserted" by default. If these files are not found,
the computer will be launched with the virtual drives empty.

