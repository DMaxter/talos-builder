ARG REGISTRY=ghcr.io
ARG USERNAME=siderolabs
ARG VERSION=v1.11.5

# Import the built kernel
FROM ${REGISTRY}/${USERNAME}/kernel:${VERSION} AS kernel

# Build the wifi handler
FROM golang:1.23-alpine AS go-builder
WORKDIR /app
RUN apk add --no-cache git

RUN go mod init wifi-manager && \
    go get github.com/vishvananda/netlink
COPY main.go .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o wifi-manager .

# Assemble all kernel modules, wpa_supplicant and wifi-manager into the correct directory
FROM alpine:3 AS builder
ARG KERNEL_VERSION=6.12.25-talos

RUN apk update && apk add wget ca-certificates wpa_supplicant

RUN mkdir -p /staging/usr/lib/firmware/brcm && \
    cd /staging/usr/lib/firmware/brcm && \
    wget -O brcmfmac43455-sdio.txt https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/refs/heads/trixie/debian/config/brcm80211/brcm/brcmfmac43455-sdio.txt && \
    wget -O brcmfmac43455-sdio.clm_blob https://github.com/RPi-Distro/firmware-nonfree/raw/refs/heads/trixie/debian/config/brcm80211/cypress/cyfmac43455-sdio.clm_blob && \
    wget -O brcmfmac43455-sdio.bin https://github.com/RPi-Distro/firmware-nonfree/raw/refs/heads/trixie/debian/config/brcm80211/cypress/cyfmac43455-sdio-minimal.bin && \
    for suffix in "raspberrypi,5-compute-module" "raspberrypi,5-model-b" "raspberrypi,500"; do \
        for ext in .txt .clm_blob .bin; do \
            cp ./brcmfmac43455-sdio${ext} ./brcmfmac43455-sdio.${suffix}${ext}; \
        done; \
    done

RUN mkdir -p /staging/usr/local/lib/containers/wpa_supplicant/usr/lib && \
    mkdir -p /staging/usr/local/lib/containers/wpa_supplicant/usr/sbin && \
    cp /sbin/wpa_supplicant /staging/usr/local/lib/containers/wpa_supplicant/usr/sbin/wpa_supplicant

COPY --from=go-builder /app/wifi-manager /staging/usr/local/lib/containers/wpa_supplicant/wifi-manager

RUN ldd /sbin/wpa_supplicant | grep "=> /" | awk '{print $3}' | xargs -I {} cp --parents {} /staging/usr/local/lib/containers/wpa_supplicant && \ 
    cp /lib/ld-musl-aarch64.so.1 /staging/usr/local/lib/containers/wpa_supplicant/usr/lib

COPY wpa_supplicant.yaml /staging/usr/local/etc/containers/wpa_supplicant.yaml

COPY --from=kernel /usr/lib/modules/6.12.25-talos/kernel/net/wireless/ /staging/usr/lib/modules/6.12.25-talos/kernel/net/wireless/
COPY --from=kernel /usr/lib/modules/6.12.25-talos/kernel/net/mac80211/ /staging/usr/lib/modules/6.12.25-talos/kernel/net/mac80211/
COPY --from=kernel /usr/lib/modules/6.12.25-talos/kernel/drivers/net/wireless/broadcom/ /staging/usr/lib/modules/6.12.25-talos/kernel/drivers/net/wireless/broadcom/

# Copy all artifacts to the final image
FROM scratch
COPY --from=builder /staging /rootfs
COPY manifest.yaml /manifest.yaml
