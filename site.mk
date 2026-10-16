# DeMiSTify site configuration for this repo; scripts/build_core.sh copies
# it to DeMiSTify/site.mk.
BOARDS = cone_ext

# Quartus II 13.1: last release with Cyclone III (scripts/install_quartus.sh)
Q13 = /opt/altera/13.1/quartus/bin/

QUARTUS_CYCLONEII = $(Q13)
QUARTUS_CYCLONEIII = $(Q13)
QUARTUS_MIST = $(Q13)

NOTIFY_BOARDCOMPLETE = echo
NOTIFY_COMPLETE = echo
