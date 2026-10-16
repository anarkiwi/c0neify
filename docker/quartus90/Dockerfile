# syntax=docker/dockerfile:1
# Quartus II 9.0 Web Edition (Windows) under Wine, ACEX 1K devices only.
# Build with scripts/build_acex.sh --image-only; the installer comes in as
# the named build context "installer" and never enters a layer.

FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587 AS wine
ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends wine wine32 \
	&& rm -rf /var/lib/apt/lists/*

FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587 AS extract
ARG INSTALLER=90_quartus_free.exe
ARG ACEX_GROUPS="ACEX1K EP1K10 EP1K30 EP1K50 EP1K100"
ARG KEEP_DEVINFO="acex1k configuration programmer"
RUN apt-get update \
	&& apt-get install -y --no-install-recommends unshield python3 python3-tqdm \
	&& rm -rf /var/lib/apt/lists/*
RUN --mount=type=bind,from=installer,target=/in \
	--mount=type=bind,source=scripts/isx_unpack.py,target=/isx_unpack.py \
	set -eu; \
	python3 /isx_unpack.py "/in/$INSTALLER" /disk1; \
	unshield -D 0 -d /x -g "Program Quartus Files" x /disk1/data1.hdr >/dev/null; \
	mv /x/Program_Quartus_Files /opt/quartus; \
	dev=/opt/quartus/common/devinfo; \
	for g in $ACEX_GROUPS; do unshield -D 0 -d /g -g "$g" x /disk1/data1.hdr >/dev/null; done; \
	cp -n /g/*/* "$dev/acex1k/"; \
	for d in "$dev"/*/; do \
		case " $KEEP_DEVINFO " in *" $(basename "$d") "*) ;; *) rm -rf "$d" ;; esac; \
	done; \
	find "$dev/programmer" -type f ! -name adapter_db.ddb ! -name "ep1k*_pcf.ddb" ! -name "epc*_pcf.ddb" -delete; \
	find /opt/quartus -name "*.pdb" -delete; \
	rm -rf /disk1 /x /g /opt/quartus/dsp_builder; \
	chmod -R a+rX,go-w /opt/quartus; \
	test -f "$dev/acex1k/ep1k30_device.ddb" && test -f "$dev/acex1k/ep1k100_device.ddb"; \
	du -sh /opt/quartus

FROM wine AS quartus
RUN useradd -m -u 1000 quartus
COPY --from=extract /opt/quartus /opt/quartus
USER 1000:1000
ENV WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" WINEARCH=win32 \
	WINEPREFIX=/home/quartus/.wine QUARTUS_BIN=/opt/quartus/bin
RUN wineboot -i && wineserver -w
WORKDIR /work
