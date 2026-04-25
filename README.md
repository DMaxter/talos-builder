# Raspberry Pi 5 Talos Builder
This repository serves as the glue to build custom Talos images for the Raspberry Pi 5. It patches the Kernel and Talos build process to use the Linux Kernel source provided by [raspberrypi/linux](https://github.com/raspberrypi/linux). 

## Tested on
So far, this release has been verified on:

| ✅ Hardware                                                |
|------------------------------------------------------------|
| Raspberry Pi Compute Module 5 on Compute Module 5 IO Board |
| Raspberry Pi Compute Module 5 Lite on [DeskPi Super6C](https://wiki.deskpi.com/super6c/) |
| Raspberry Pi 5b with [RS-P11 for RS-P22 RPi5](https://wiki.52pi.com/index.php?title=EP-0234) |
| Raspberry Pi 5 |

## What's not working?
* Booting from USB: USB is only available once LINUX has booted up but not in U-Boot.

## How to use?
The releases on this repository align with the corresponding Talos version. There is a raw disk image (initial setup) and an installer image (upgrades) provided. 

### Examples
Initial:
```
unzstd metal-arm64-rpi.raw.zst
dd if=metal-arm64-rpi.raw of=<disk> bs=4M status=progress
sync
```

Upgrade:
```
talosctl upgrade \
  --nodes <node IP> \
  --image ghcr.io/talos-rpi5/installer:<version>
```

## Building
If you'd like to make modifications, it is possible to create your own build. Bellow is an example of the standard build.

```
# Clones all dependencies and applies the necessary patches
make checkouts patches

# Builds the Linux Kernel (can take a while)
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> kernel

# Builds the overlay (U-Boot, dtoverlays ...)
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> overlay

# Final step to build the installer and disk image
make REGISTRY=ghcr.io REGISTRY_USERNAME=<username> installer
```

### Cross compiling

When building on amd64 host to arm64 target, we can set `CROSS_COMPILE=true` and it will work for all the steps above, except `installer`.

For generating the final image, we are running an `arm64` container, so we need to have [`binfmt_misc`](https://en.wikipedia.org/wiki/Binfmt_misc) on the host.
If it isn't enabled, please run

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

### Wifi

By default the wifi extension is included, but it can be removed if not needed, by removing it from the Makefile.

The wifi configuration is provided with `talosctl apply-config` with a patch looking like the following:

```bash
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: wpa_supplicant
configFiles:
    - content: |
        country=<YOUR CONTRY CODE>
        network={
          ssid=<YOUR NETWORK SSID>
          psk="<YOUR NETWORK PASSPHRASE">
        }
      mountPath: /etc/wpa_supplicant.conf
```


## License
See [LICENSE](LICENSE).
