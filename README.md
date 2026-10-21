# Tiny-CA

Running a [step-ca](https://github.com/smallstep/certificates) server with [pico-rng](https://github.com/polhenarejos/pico-rng) and [pico-hsm](https://github.com/polhenarejos/pico-hsm) on a Raspberry Pi Zero W

This project / guide is heavily inspired by [step-ca's tiny ca build](https://smallstep.com/blog/build-a-tiny-ca-with-raspberry-pi-yubikey/) ([archive.org link](https://web.archive.org/web/20260914210127/https://smallstep.com/blog/build-a-tiny-ca-with-raspberry-pi-yubikey/))

## Requirements

### For the setup

- Machine with docker installed and buildx / qemu setup for the target architecture
- An internet connection
- A display & keyboard connected to the Pi to not down the luks2 & root key during initial generation
- Raspberry Pi Pico / Pico 2 (skip the pico-rng step when using ESP32-S3)
- An internet connection to the Pi

## For permanent operation

- Raspberry Pi with latest OS (this assumes a Pi Zero W, but other SBCs also work with some changes)
- LAN connection to the Pi
- Raspberry Pi Pico / Pico 2 / ESP32-S3 compatible board
- Micro USB (M) OTG to USB A (F) adapter
- A cable to connect the Pico to the OTG adapter

## Steps involved

1. Compile step-ca and pico-rng (comment out the last two `COPY` commands in [Dockerfile](./Dockerfile#L72) when using an ESP32-S3).

   The Pi is too slow to do this in a reasonable amount of time.

   This still takes > 30min on a AMD Ryzen 5 7500F with a 60Mbit/s connection and 32GB of RAM.

   ```bash
   docker buildx build --cache-from=type=local,src=./docker-cache --cache-to=type=local,dest=./docker-cache --platform linux/arm/v6 -t tiny-ca:arm32v6 --load .
   # Go watch some anime i.g.

   docker create --name tiny-ca-temp --platform linux/arm/v6 tiny-ca:arm32v6 --
   for file in step-ca step-kms-plugin pico_rng.ko pico_rng.uf2; do
       docker cp tiny-ca-temp:/usr/local/app/out/$file bin
   done
   docker rm tiny-ca-temp
   ```

## TODOs

- Look if we can use some of this repositories instructions: https://github.com/mafrosis/step-ca-on-rpi
- Provide binaries for most common architectures
- Encrypt OS at rest using luks2 and allow builtin WiFi to open using ssh with dropbear
- Convert instructions to docker: https://github.com/ViRb3/pi-encrypted-boot-ssh
- Test and integrate: https://github.com/m4dm4x1337/initramfs-wifi

## License

[GNU GPLv3 only](./COPYING.md)
