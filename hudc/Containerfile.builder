# Cross-Build-Image für hudc (arm64 / Pi Zero 2 W)
# Läuft via QEMU transparent auf dem x86_64-Host
#
# Einmalig bauen:
#   podman build --platform linux/arm64 -t hudc-builder -f Containerfile.builder .
#
# Danach zum Kompilieren (aus repo/hudc/):
#   podman run --platform linux/arm64 --rm \
#     -v "$(pwd)":/src -v /tmp/hudc-build:/build \
#     hudc-builder

FROM debian:bookworm

# Build-Abhängigkeiten: Qt5 + cmake + g++
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        g++ \
        git \
        make \
        qtbase5-dev \
        qtdeclarative5-dev \
    && rm -rf /var/lib/apt/lists/*

# pigpio aus Quellcode (nicht in Debian-Repos)
# make install schlägt wegen Python distutils fehl → C-Teile manuell installieren
RUN git clone --depth=1 https://github.com/joan2937/pigpio /tmp/pigpio \
    && cd /tmp/pigpio \
    && make -j4 \
    && cp libpigpio.so.1     /usr/local/lib/ \
    && cp libpigpiod_if.so.1  /usr/local/lib/ \
    && cp libpigpiod_if2.so.1 /usr/local/lib/ \
    && ln -sf /usr/local/lib/libpigpio.so.1      /usr/local/lib/libpigpio.so \
    && ln -sf /usr/local/lib/libpigpiod_if.so.1  /usr/local/lib/libpigpiod_if.so \
    && ln -sf /usr/local/lib/libpigpiod_if2.so.1 /usr/local/lib/libpigpiod_if2.so \
    && cp pigpio.h pigpiod_if.h pigpiod_if2.h /usr/local/include/ \
    && ldconfig \
    && rm -rf /tmp/pigpio

# Build-Script
RUN printf '#!/bin/bash\nset -e\ncmake -B /build -S /src -DCMAKE_BUILD_TYPE=Release 2>&1\ncmake --build /build -j4 2>&1\ncp /build/hudc /src/hudc_new\necho "BUILD OK: $(ls -lh /src/hudc_new)"\n' \
    > /usr/local/bin/build-hudc && chmod +x /usr/local/bin/build-hudc

CMD ["/usr/local/bin/build-hudc"]
