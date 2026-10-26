# eventcontrol-ptt-vocoder

The AMBE+2 vocoder for EventControl's MOTOTRBO gateway, kept apart from
EventControl's own code: OpenDMR is GPL, and AMBE+2 is patent-encumbered —
who may build, host and distribute this image is a legal question as much as
a technical one. Dispatch publishes it, and the gateway's voice image built
from it, publicly under GPL-2 (LICENSE), decided 2026-10-26.

- `build.sh` clones OpenDMR at a pinned commit and applies the three patches
  (see README.md for why each is needed).
- The image is `FROM scratch` with `/opt/opendmr/{include,lib}` and the
  complete corresponding source under `/opt/opendmr/src` (the patched tree as
  a tarball, the patches, `build.sh`); the gateway's voice image copies it.
- Tag `vX.Y.Z` → `ghcr.io/dispatch-se/eventcontrol-ptt-vocoder:X.Y.Z`
  (.github/workflows/image.yml). EventControl's `Dockerfile.gateway` pins
  the version in `VOCODER_IMAGE`.
