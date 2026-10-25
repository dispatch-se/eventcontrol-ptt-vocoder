# OpenDMR — vendored patch

The AMBE+2 vocoder for the MOTOTRBO gateway. Upstream is
[MW0MWZ/OpenDMR](https://github.com/MW0MWZ/OpenDMR): `mbelib-neo` for decode,
OP25's MBE encoder for encode, behind one C API.

Upstream is broken as of its only commit, `d28164b` — in two independent ways.
Three patches here fix it and add the entry point this gateway needs. See
`docs/vocoder-evaluation.md` for the measurements.

| Patch | What |
|---|---|
| `0001` | The encoder packed the 49 bits in the wrong order, so speech became noise. |
| `0002` | Adds a 49-bit API — the form MOTOTRBO IPSC actually carries. |
| `0003` | Golay B-block alignment: a frame did not survive its own FEC round trip. |

## The bug

`encode_ambe_frame` packed the nine AMBE parameters into 49 bits **sequentially** —
all 7 bits of `b0`, then all 5 of `b1`, and so on.

The real format **interleaves** them: the most significant bits of every parameter
go into the first 24 positions, because that block is Golay-protected. That is
what OP25's own `encode_49bit` does, and what `mbelib` expects when decoding.

OpenDMR's *decoder* produces correct wire-order bits, so encode and decode
disagreed. Silence survived the round trip because near-zero parameters are
insensitive to ordering; speech became noise.

The patch replaces the packing loop with OP25's ordering, taken from
`op25/gr-op25_repeater/lib/ambe_encoder.cc`.

## Effect

Round-tripping 6.2 s of real speech:

| | Before | After |
|---|---|---|
| Energy envelope correlation | 0.09 | **0.89** |
| Spectral envelope, voiced frames | 0.22 mean, 3.9% > 0.7 | **0.70 mean, 59.3% > 0.7** |

The 60 ms lag in the energy correlation is the vocoder's algorithmic delay and is
expected.

## Building

```bash
./build.sh
```

Clones upstream at the pinned commit, applies the patch, builds, and installs
`include/opendmr.h` and `lib/libopendmr.a` here. All of that is gitignored: the
source is GPL and pinned, so it is fetched rather than vendored.

Then build the gateway with voice:

```bash
cd backend && go build -tags opendmr ./cmd/mototrbo-gateway
```

Without the tag there is no vocoder, no C toolchain needed, and no GPL code —
the gateway still carries position, presence and text, and simply has no audio.

The Go tests that guard this fix live in
`backend/internal/mototrbo/vocoder/vocoder_opendmr_test.go` and only run under
the same tag:

```bash
cd backend && go test -tags opendmr ./internal/mototrbo/vocoder/
```

Worth sending upstream — it is a real defect in a young project, and the fix is
lifted from the encoder OpenDMR already vendors.

## Still unverified

Agreeing with `mbelib` is strong evidence the frames are in genuine AMBE+2 wire
format, since `mbelib` is what the DSD/DSDPlus/DroidStar world decodes live DMR
with. It is not proof of interop. **The authoritative test is a real MOTOTRBO
radio producing intelligible audio from these frames**, and that needs a hardware
window.

## Licensing

`mbelib-neo` is GPL-2, OP25 is GPL-3, so OpenDMR is GPL-2. Linking it into a
*distributed* binary makes that binary GPL; self-hosting without distribution
does not trigger it. Running the vocoder as a separate process behind a narrow
interface avoids the question — a second reason to structure it that way, beyond
being able to swap in a DVSI dongle.
