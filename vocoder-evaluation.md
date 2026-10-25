# AMBE+2 vocoder evaluation

Bridging MOTOTRBO voice needs an AMBE+2 codec. Unlike the Hytera path — where the
repeater transcodes AMBE↔G.711 and the gateway never sees a vocoder — MOTOTRBO
over IPSC delivers raw AMBE+2 frames, so the codec is unavoidable.

This records what was tested, what the numbers were, and what it means for scope.
Redo it before trusting any of these conclusions to a newer release.

## Result

| | |
|---|---|
| **Decode** (radio → dispatch) | Viable. Untested against real frames, but the code is `mbelib-neo`, which the whole DSD / DSDPlus / DroidStar world runs against live DMR daily. |
| **Encode** (dispatch → radio) | Broken upstream in two places, **both fixed by patches**. See `third_party/opendmr/`. |

Both directions work. A software-only stack is viable — no DVSI dongle, no
extracted firmware.

Two upstream defects were found, each recorded in its own section below: the
49-bit packing order (the first spike) and the Golay B-block alignment (found
later, while building the gateway). The gateway uses a third patch's 49-bit API,
which bypasses FEC entirely.

## The fix

Upstream's `encode_ambe_frame` packed the nine AMBE parameters into 49 bits
sequentially. The real format interleaves them, putting the most significant bits
of every parameter into the Golay-protected first 24 positions — which is what
OP25's own `encode_49bit` does and what `mbelib` expects. OpenDMR's decoder
produced correct wire-order bits, so the two halves disagreed.

After the patch, on the same 6.2 s of speech:

| Measure | Before | After |
|---|---|---|
| Energy envelope correlation | 0.09 | **0.89** (at 60 ms lag, the vocoder's delay) |
| Spectral envelope, voiced frames | 0.22 mean, 3.9% > 0.7 | **0.70 mean, 59.3% > 0.7** |

Everything below describes the original failing state, kept because it is how the
bug was found and how to recognise it again.

## What was tested

`MW0MWZ/OpenDMR` @ `d28164b` (its only commit, 31 Dec 2025) — a single C API over
`mbelib-neo` for decode and OP25's `MBEEncoder` for encode. Built clean on macOS
with its own Makefile.

Structurally it is correct: 9-byte frames, 50/sec, exactly 3600 bps, which is
AMBE+2 half-rate. The problem is the contents of those frames.

Two inputs: a synthetic voiced signal, and 6.2 s of real speech from macOS `say`
resampled to 8 kHz mono.

## Numbers

Real speech, encoded then decoded, compared against the input:

| Measure | Result | Expected if working |
|---|---|---|
| Energy envelope correlation | **0.09** (0.13 at best lag) | > 0.8 — speech/silence structure should survive |
| Spectral envelope correlation, voiced frames | **0.22** mean, 3.9% of frames above 0.7 | > 0.6 — formants are what a vocoder models |
| Transcode stability (encode→decode→encode vs first pass) | **52% of bits**, 2/308 frames identical | high — chance is 50% |

Transcode stability looked decisive at the time. **It was not** — after the fix it
still sits at 54%, while the audio measures well. Re-encoding decoded audio is not
expected to reproduce the original parameters, because the decoded signal has
already been through parametric synthesis; a vocoder is not idempotent under
transcode. Treat it as weak corroboration alongside the audio measures, not as
evidence on its own. The energy and spectral correlations are what matter.

Supporting detail: consecutive speech frames differ by 30.7 of 72 bits where
random would be 36 — the bits look close to noise, whereas real speech parameters
change smoothly between 20 ms frames. Silence does behave differently (13.6 bits),
so the encoder responds to gross energy; it is the spectral and pitch parameters
that are wrong or wrongly packed.

Silence round-trips correctly — encoder silence decodes to RMS 2.4. The pair
agrees on the trivial case and fails on speech.

## A second bug: the Golay B block

Found while building the gateway, and worth more than the level numbers below.

`ENCODING_TABLE_23127` stores each Golay(23,12) codeword **left-shifted by one**,
in a 24-bit field. `decode23127()` expects it right-aligned — it recovers the data
with `code >> 11`. So OpenDMR's encode and decode disagree by one bit position,
and the PRNG scrambling mask is applied at the wrong offset on top of that.

The consequence is that a frame does not survive its own FEC round trip. Encoding
49 bits to 72 and decoding back does not return the 49 bits that went in, so the
documented `opendmr_encode`/`opendmr_decode` frame API degrades audio on every
frame.

Patch `0003` shifts the codeword right by one before scrambling. After it, the
72-bit frame path and the 49-bit path agree **bit for bit** over a full test
signal — 0 of 12 800 samples differ, where before the fix 12 731 did. That
agreement is the useful part: a FEC round trip *must* be lossless, so the two
paths matching is evidence that the frame layout is understood correctly, not
just that the audio sounds better.

Envelope correlation on the frame path went from 0.879 to 0.974.

## The 49-bit path

Over the air a DMR voice frame is 72 bits: 49 bits of parameters plus Golay FEC.
The repeater corrects and strips that FEC before putting the frame on the IPSC
wire, so a gateway only ever handles 49 bits.

Patch `0002` adds `opendmr_encode49` / `opendmr_decode49`, which skip the FEC
entirely — `mbe_processAmbe2450Data` already takes the 49-bit form. This is what
the gateway uses. It avoids re-deriving FEC that is about to be discarded, and it
sidesteps the bug above rather than depending on the fix.

## Level behaviour

Measured through the 49-bit path on the fixed codec. **The earlier version of
this section was measured through the broken FEC path and was wrong** — it
reported a variable 4–9x gain, which was an artefact of the corruption.

| Input peak | Output peak | Energy ratio |
|---|---|---|
| 300 | 4 375 | 14.8x |
| 600 | 8 978 | 14.6x |
| 1 000 | 14 782 | 14.7x |
| 1 500 | 24 869 | 14.9x |
| 2 000 | 30 594 | 14.3x |
| 3 000 | 31 128 | 14.1x |
| 6 000 | 31 128 | 11.2x |
| 16 000 | 31 128 | 6.6x |

**The round trip is about +23 dB**, and in the linear region — input peak up to
about 1 500 — the ratio is a stable 14.6–14.9x. Above roughly 2 000 the output
pins at 31 128 and louder speech is flattened.

What is **not** known is how that gain splits between encode and decode, and it
matters: transmitting, our encoder feeds the radio's decoder; receiving, the
radio's encoder feeds ours. Only one half is ours at a time, so a round-trip
figure cannot be apportioned. Separating them needs a real radio.

Rather than guess, `gain.go` normalises against the signal actually present —
peak-tracking with instant attack and slow release, targeting `NominalPeak =
1200` into the encoder. That is robust to the unknown split, and to the much
larger variation between one dispatcher's microphone gain and another's. The gate
threshold is relative to the target rather than absolute: the decoder's idle
output has a peak of 263, so a fixed floor tuned for the encode side sits below
it and the normaliser amplifies the codec's own hiss between transmissions.

## What this does *not* prove

- **Not that OP25's encoder is broken.** The fault may be in OpenDMR's glue —
  parameter mapping or bit packing between OP25's output and the DMR 72-bit frame.
  Testing `ambe_encoder.cc` directly, without the wrapper, would separate these.
- **Not that the decoder is broken.** These tests only show the *pair* fails, and
  the encoder is the unproven half. Confirming the decoder needs known-good frames
  captured from a real repeater.
- Do not read anything into `dmr_codec`'s "Total bit errors corrected: 0". It
  reports zero for 900 bytes of `/dev/urandom` as well, so it validates nothing.

## Options for TX

1. **Lift OP25's `ambe_encoder.cc` directly** and drive it without OpenDMR's
   wrapper. Cheapest next experiment if TX matters, and isolates glue from DSP.
2. **DVSI hardware dongle** (ThumbDV / DVstick30, roughly $100/channel). What the
   entire ham DMR ecosystem actually uses for encode — XLX `ambed`, DVSwitch and
   BrandMeister interlinks all require one. Definitive, legal, but breaks
   containerisation: USB passthrough, hardware per host, 1–6 channels per chip.
3. **DVSI software licence.** The only option with both clean legals and clean
   containerisation. Worth a quote if this becomes a commercial product.
4. **MD380 firmware extraction** — works and is bit-exact, but it is DVSI object
   code. Copyright problem on top of the patent one, ARM-only or via qemu, and the
   image cannot be redistributed. Useful only as a dev-only oracle to check
   whether a software encoder emits frames a real DVSI decoder accepts.

## Reproducing

```bash
git clone --depth 1 https://github.com/MW0MWZ/OpenDMR.git && cd OpenDMR && make
say -v Daniel -o s.aiff "Control from unit seven, we are at the north gate."
afconvert -f WAVE -d LEI16@8000 -c 1 s.aiff s.wav        # or sox
# strip the WAV header to raw PCM, then:
./dmr_codec encode s.raw s.ambe
./dmr_codec decode s.ambe out.raw
./dmr_codec transcode s.ambe s2.ambe   # compare s2 against s.ambe bit-wise
```

Compare `out.raw` against `s.raw` on energy envelope and per-frame spectral
envelope correlation, and `s2.ambe` against `s.ambe` bit-wise. Listening also
works: the output is audibly unrelated to the input.

## Licensing note

`mbelib-neo` is GPL-2 and OP25 is GPL-3. Linking either into the gateway makes a
*distributed* binary GPL; self-hosting without distribution does not trigger it.
Keeping the vocoder in a separate process behind a narrow interface avoids the
question, and is worth doing for that reason alone regardless of which
implementation wins.
