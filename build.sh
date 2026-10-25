#!/usr/bin/env bash
#
# Build libopendmr for the `opendmr` build tag.
#
# The default gateway build needs none of this — it has no vocoder and no C
# toolchain. Run this only when you want voice, then build with:
#
#     go build -tags opendmr ./cmd/mototrbo-gateway
#
# Everything lands under this directory (build/, include/, lib/), all of which
# are gitignored: the source is GPL and pinned upstream, so it is fetched rather
# than vendored.

set -euo pipefail

REPO="https://github.com/MW0MWZ/OpenDMR.git"
# Pinned: upstream has exactly one commit, and the patch below is written
# against it. A moving target here would silently change the vocoder.
COMMIT="d28164b"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/build/OpenDMR"
PATCHES=(
    "$HERE/0001-fix-49bit-packing-order.patch"
    "$HERE/0002-add-49bit-api.patch"
    "$HERE/0003-fix-golay-b-block-alignment.patch"
)

if [ ! -d "$SRC/.git" ]; then
    echo "==> Cloning OpenDMR at $COMMIT"
    mkdir -p "$HERE/build"
    git clone "$REPO" "$SRC"
    git -C "$SRC" checkout --quiet "$COMMIT"
else
    echo "==> Reusing existing clone at $SRC"
    # Discard any previous patch application so re-running is idempotent.
    git -C "$SRC" checkout --quiet -- .
    git -C "$SRC" checkout --quiet "$COMMIT"
fi

# 0001 fixes the encoder — without it the frames are noise. 0002 adds the
# 49-bit entry points, which is the form MOTOTRBO IPSC actually carries. 0003
# fixes the Golay alignment so a frame survives its own FEC round trip.
# See README.md and docs/vocoder-evaluation.md.
for p in "${PATCHES[@]}"; do
    echo "==> Applying $(basename "$p")"
    git -C "$SRC" apply "$p"
done

echo "==> Building"
make -C "$SRC" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" libopendmr.a

echo "==> Installing into $HERE"
mkdir -p "$HERE/include" "$HERE/lib"
cp "$SRC/opendmr.h" "$HERE/include/"
cp "$SRC/libopendmr.a" "$HERE/lib/"

echo
echo "Done. Build the gateway with voice:"
echo "    (install include/ and lib/ under /opt/opendmr for the gateway voice build)"
