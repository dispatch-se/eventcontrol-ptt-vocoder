# syntax=docker.io/docker/dockerfile:1
# eventcontrol-ptt-vocoder: OpenDMR (AMBE+2, GPL) built and patched, installed
# under /opt/opendmr for EventControl's MOTOTRBO gateway voice build
# (eventcontrol/workers/ptt/Dockerfile.gateway, target voice). The gateway
# links it statically; this image only carries the library.
FROM alpine:3.20 AS build
RUN apk add --no-cache git make g++ musl-dev bash
WORKDIR /build
COPY build.sh 000*.patch ./
RUN bash build.sh

FROM scratch
COPY --from=build /build/include /opt/opendmr/include
COPY --from=build /build/lib /opt/opendmr/lib
COPY README.md /opt/opendmr/README.md
