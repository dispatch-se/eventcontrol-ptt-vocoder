# syntax=docker.io/docker/dockerfile:1
# eventcontrol-ptt-vocoder: OpenDMR (AMBE+2, GPL) built and patched, installed
# under /opt/opendmr for EventControl's MOTOTRBO gateway voice build
# (eventcontrol/workers/ptt/Dockerfile.gateway, target voice). The gateway
# links it statically. Besides the library this image carries the complete
# corresponding source (GPL-2): the patched OpenDMR tree, the patches and the
# build script, under /opt/opendmr/src, so every image built from it can ship it.
FROM alpine:3.20 AS build
RUN apk add --no-cache git make g++ musl-dev bash
WORKDIR /build
COPY build.sh 000*.patch ./
RUN bash build.sh \
 && mkdir -p /build/src \
 && tar -C /build/build/OpenDMR --exclude=.git --exclude='*.o' --exclude='*.a' -czf /build/src/opendmr-d28164b-patched.tar.gz . \
 && cp build.sh 000*.patch /build/src/

FROM scratch
COPY --from=build /build/include /opt/opendmr/include
COPY --from=build /build/lib /opt/opendmr/lib
COPY --from=build /build/src /opt/opendmr/src
COPY README.md NOTICE.md LICENSE /opt/opendmr/
