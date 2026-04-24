PKG_VERSION = v1.11.0
TALOS_VERSION = v1.11.5
SBCOVERLAY_VERSION = main
FIRMWARE_EXT_VERSION = v1.11.5

CROSS_COMPILE ?= false

PLATFORM ?= linux/arm64
ifeq ($(CROSS_COMPILE), true)
	PLATFORM = linux/amd64
endif

REGISTRY ?= ghcr.io
REGISTRY_USERNAME ?= talos-rpi5

TAG ?= $(shell git describe --tags --exact-match)

PKG_REPOSITORY = https://github.com/siderolabs/pkgs.git
TALOS_REPOSITORY = https://github.com/siderolabs/talos.git
SBCOVERLAY_REPOSITORY = https://github.com/siderolabs-community/sbc-raspberrypi.git

CHECKOUTS_DIRECTORY := $(PWD)/checkouts
PATCHES_DIRECTORY := $(PWD)/patches
EXTENSIONS_DIRECTORY := $(PWD)/extensions

PKGS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/pkgs && git describe --tag --always --dirty --match v[0-9]\*)
TALOS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/talos && git describe --tag --always --dirty --match v[0-9]\*)
SBCOVERLAY_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi && git describe --tag --always --dirty)-$(PKGS_TAG)
SBCOVERLAY2_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5 && git describe --tag --always --dirty)-$(PKGS_TAG)

#EXTENSIONS ?= $(REGISTRY)/$(REGISTRY_USERNAME)/raspberrypi-firmware:$(SBCOVERLAY2_TAG)
EXTENSIONS ?= $(REGISTRY)/$(REGISTRY_USERNAME)/raspberrypi-firmware:$(FIRMWARE_EXT_VERSION)

#
# Help
#
.PHONY: help
help:
	@echo "checkouts        : Clone repositories required for the build"
	@echo "patches          : Apply all patches"
	@echo "kernel           : Build kernel"
	@echo "firmware-extension: Build Raspberry Pi firmware extension"
	@echo "overlay          : Build Raspberry Pi overlay"
	@echo "installer        : Build installer docker image and disk image"
	@echo "release          : Use only when building the final release, this will tag relevant images with the current Git tag."
	@echo "clean            : Clean up any remains"



#
# Checkouts
#
.PHONY: checkouts checkouts-clean
checkouts:
	git clone -c advice.detachedHead=false --branch "$(PKG_VERSION)" "$(PKG_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/pkgs"
	git clone -c advice.detachedHead=false --branch "$(TALOS_VERSION)" "$(TALOS_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/talos"
	git clone -c advice.detachedHead=false --branch "$(SBCOVERLAY_VERSION)" "$(SBCOVERLAY_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi"

checkouts-clean:
	rm -rf "$(CHECKOUTS_DIRECTORY)/pkgs"
	rm -rf "$(CHECKOUTS_DIRECTORY)/talos"
	rm -rf "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi"



#
# Patches
#
.PHONY: patches-pkgs patches-talos patches
patches-pkgs:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		for f in $(ls -d "$(PATCHES_DIRECTORY)/siderolabs/pkgs/*"); do \
			git am $f; \
		done

patches-sbc:
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi" && \
		for f in $(ls -d "$(PATCHES_DIRECTORY)/siderolabs/sbc-raspberrypi/*"); do \
			git am $f; \
		done

patches-talos:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		for f in $(ls -d "$(PATCHES_DIRECTORY)/siderolabs/talos/*"); do \
			git am $f; \
		done

patches: patches-pkgs patches-talos patches-sbc


#
# Kernel
#
.PHONY: kernel
kernel:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PLATFORM=$(PLATFORM) \
			CROSS_COMPILE=$(CROSS_COMPILE) \
			kernel

kernel-%:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PLATFORM=$(PLATFORM) \
			CROSS_COMPILE=$(CROSS_COMPILE) \
			kernel-$*

cross-toolchain:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PLATFORM=$(PLATFORM) \
			cross-toolchain

raspberrypi-firmware:
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi5" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PLATFORM=$(PLATFORM) \
			CROSS_COMPILE=$(CROSS_COMPILE) \
			raspberrypi-firmware

#
# Firmware Extension
#
.PHONY: firmware-extension
firmware-extension:
	cd "$(EXTENSIONS_DIRECTORY)/raspberrypi-firmware" && \
		docker buildx build \
			--platform=linux/arm64 \
			--progress=auto \
			--push=true \
			--tag=$(REGISTRY)/$(REGISTRY_USERNAME)/raspberrypi-firmware:$(FIRMWARE_EXT_VERSION) \
			--build-arg REGISTRY=$(REGISTRY) \
			--build-arg USERNAME=$(REGISTRY_USERNAME) \
			--build-arg VERSION=$(PKGS_TAG) \
			.

.PHONY: overlay
overlay:
	@echo SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_TAG) PUSH=true \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=$(PLATFORM) \
			CROSS_COMPILE=$(CROSS_COMPILE) \
			sbc-raspberrypi


#
# Installer/Image
#
.PHONY: installer
installer:
	@if [ "$(CROSS_COMPILE)" = "true" ]; then \
		export DOCKER_DEFAULT_PLATFORM=linux/arm64; \
	fi; \
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			IMAGER_ARGS="--overlay-name=rpi_generic --overlay-image=$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_TAG) --system-extension-image=$(EXTENSIONS)" \
			kernel initramfs imager installer-base installer && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) \
			metal --arch arm64 \
			--base-installer-image="$(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG)" \
			--overlay-name="rpi_generic" \
			--overlay-image="$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_TAG)" \
			--system-extension-image="$(EXTENSIONS)"



#
# Release
#
.PHONY: release
release:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG)



#
# Clean
#
.PHONY: clean
clean: checkouts-clean
