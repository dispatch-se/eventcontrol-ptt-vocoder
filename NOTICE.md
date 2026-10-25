# eventcontrol-ptt-vocoder

The AMBE+2 vocoder for EventControl's MOTOTRBO gateway, kept apart from
EventControl's own code: OpenDMR is GPL, and AMBE+2 is patent-encumbered —
who may build, host and distribute this image is a legal question as much as
a technical one. Check before publishing it outside the organisation.

- `build.sh` clones OpenDMR at a pinned commit and applies the three patches
  (see README.md for why each is needed).
- The image is `FROM scratch` with only `/opt/opendmr/{include,lib}`.
- Tag `vX.Y.Z` → `ghcr.io/dispatch-se/eventcontrol-ptt-vocoder:vX.Y.Z`
  (.github/workflows/image.yml). EventControl's `Dockerfile.gateway` pins
  the version in `VOCODER_IMAGE`.
