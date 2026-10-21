FROM vascoguita/raspios:armhf AS step-ca-builder
WORKDIR /usr/local/app

ARG STEP_CA_VERSION=0.30.2
ARG STEP_CA_CHECKSUM="944b205d5ba89f393cbdc09d68ab7ce485f5b44f44c28025d30508af956c1cba"

ARG GOLANG_VERSION=1.27.1
ARG GOLANG_CHECKSUM="44893f200fb034791d4188df9fc9b9e73eadbb5fceafd5166703f0b9bab73fc2"

RUN apt-get -y update && apt-get install -y curl make gcc g++ pkg-config libpcsclite-dev\
    && rm -rf /var/lib/apt/lists/*

# required for step-ca: libpcsclite-dev gcc make pkg-config

RUN curl -LO "https://go.dev/dl/go$GOLANG_VERSION.linux-armv6l.tar.gz"
RUN curl -LO "https://github.com/smallstep/certificates/releases/download/v$STEP_CA_VERSION/step-ca_$STEP_CA_VERSION.tar.gz"

RUN echo "$GOLANG_CHECKSUM go$GOLANG_VERSION.linux-armv6l.tar.gz" > checksums.txt \
    && sha256sum -c checksums.txt \
    && tar -C /usr/local -xzf go$GOLANG_VERSION.linux-armv6l.tar.gz \
    && rm go$GOLANG_VERSION.linux-armv6l.tar.gz checksums.txt \
    && echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.profile

RUN . ~/.profile && go install github.com/smallstep/step-kms-plugin@latest

RUN echo "$STEP_CA_CHECKSUM step-ca_$STEP_CA_VERSION.tar.gz" > checksums.txt \
    && sha256sum -c checksums.txt \
    && tar -xzf step-ca_$STEP_CA_VERSION.tar.gz \
    && rm step-ca_$STEP_CA_VERSION.tar.gz

# see https://github.com/devcontainers/features/issues/1635
RUN sed -i 's|https://raw\.githubusercontent\.com/golangci/golangci-lint/master/install\.sh|https://golangci-lint.run/install.sh|g' Makefile
# TODO: check hash of file

# use . instead of source
RUN . ~/.profile && make bootstrap

RUN . ~/.profile \
    && make build GO_ENVS="CGO_ENABLED=1"


FROM vascoguita/raspios:armhf AS pico-rng-builder
WORKDIR /usr/local/app/

RUN apt-get -y update && apt-get install -y git cmake gcc-arm-none-eabi \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/gilex-dev/pico-rng.git

WORKDIR /usr/local/app/pico-rng

# Download pico-sdk
RUN mkdir build \
    && cd build \
    && PICO_SDK_FETCH_FROM_GIT=on cmake .. -DPICO_BOARD=pico2 -DPICO_PLATFORM=rp2350
# need to run "cmake clean" before switching target pico board. Backup pico-sdk before and restore to avoid re-downloading

RUN cd /usr/local/app/pico-rng/build \
    && make

RUN cd /usr/local/app/pico-rng/driver \
    && cmake . -DKERNELHEADERS_DIR=/usr/src/linux-headers-6.18.50+rpt-rpi-v6 \
    && make


FROM scratch
WORKDIR /usr/local/app/out

COPY --from=step-ca-builder /usr/local/app/bin/step-ca .
COPY --from=step-ca-builder /root/go/bin/step-kms-plugin .

# Skip this (comment out) when using ESP32-S3
COPY --from=pico-rng-builder /usr/local/app/pico-rng/driver/pico_rng.ko .
COPY --from=pico-rng-builder /usr/local/app/pico-rng/build/firmware/pico_rng.uf2 .

# To setup cross-platform builds
# Read here https://docs.docker.com/build/building/multi-platform/
# 
# sudo dnf install qemu-user-binfmt qemu-user-static-arm
# docker run --privileged --rm tonistiigi/binfmt --install arm

# Build the image 
# docker buildx build --cache-from=type=local,src=./docker-cache --cache-to=type=local,dest=./docker-cache --platform linux/arm/v6 -t tiny-ca:arm32v6 --load .

# Copy the files
# docker create --name tiny-ca-temp --platform linux/arm/v6 tiny-ca:arm32v6 --
# for file in step-ca step-kms-plugin pico_rng.ko pico_rng.uf2; do
#     docker cp tiny-ca-temp:/usr/local/app/out/$file bin
# done
# docker rm tiny-ca-temp
