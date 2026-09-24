# Diarization Implementation Plan

> **STATUS: IMPLEMENTED AND VERIFIED (2026-09-24).** All steps complete. The bake step is
> proven with a real token-authenticated build (`make build-small`), diarization works
> fully offline (`--network none`), and both wrapper scripts pass the new flags through.
> The `--aligned` mode evolved during implementation: it emits JSON and regroups word-level
> speaker labels into speaker-turn lines (the TXT writer discards word labels — see
> Step 4). Test article: `gencore/whisperx-speech-to-text:small-diarize-proto` (prototype,
> COPY-based) and `:small` (production, secret-baked).

**Diagrams** (Mermaid source + rendered PNG in `diagrams/`):
- [Current architecture](diagrams/current-architecture.png) — the solution as committed today
  ([source](diagrams/current-architecture.mmd)).
- [Planned architecture](diagrams/planned-architecture.png) — this plan applied: green =
  new elements, amber = changed, grey = untouched
  ([source](diagrams/planned-architecture.mmd)).

## Background

WhisperX supports speaker diarization via `pyannote.audio`. The `pyannote-audio` library is
**already installed** in the Docker image (it is a direct dependency of whisperx). The
diarization models themselves live on HuggingFace as gated models — the builder must accept
pyannote's terms of use and supply a personal access token before they can be downloaded.

The `--diarize` flag passed to `whisperx` triggers diarization. In whisperx 3.3.2,
diarization runs regardless of `--no_align` and assigns speaker labels via time overlap —
so unaligned segments still carry speaker labels (verified in source **and confirmed
empirically** — see "Smoke test result" under Decisions).

Also verified against whisperx 3.3.2 source: the CLI flags `--diarize`, `--min_speakers`,
`--max_speakers`, and `--hf_token` all exist. The TXT writer prefixes lines with
`[SPEAKER_00]:` when speaker labels are present, and the SRT writer prepends speaker labels
to subtitle text. No output format changes are required.

---

## Decisions

### Model delivery: bake into the image at build time — no fallback

Every image build — local *and* the build that feeds `make publish` — downloads the
pyannote models via a BuildKit secret mount and bakes them into the image. The image is
then fully offline for diarization: no runtime token, no cache volume, no first-run
internet cost. This matches the image's existing philosophy (Whisper + alignment models are
already pre-cached at build time via the jfk.wav step).

**A build without `HF_TOKEN` fails.** There is deliberately no runtime-download path: if
the bake step can't fetch the models, the build fails, and the builder fixes the token.
This keeps one image flavour and keeps the design free of fallback complexity.

**Licensing basis:** the pyannote gate is a terms-of-use and contact-information gate, not a
no-redistribution licence. The `speaker-diarization-3.1` weights are **MIT-licensed** —
redistribution is permitted provided the licence text accompanies the weights. A
`PYANNOTE-NOTICE` file in the image covers this, so `make publish` may push baked images.

**Contingency (not a runtime fallback):** if secret-mounting were ever unavailable in some
build environment, the alternative is still build-time — pre-download + `COPY`, SHA256
pinned in the tag (see Fallback Build Method section).

### Gated models — there are TWO, not one

The `pyannote/speaker-diarization-3.1` pipeline internally pulls `pyannote/segmentation-3.0`,
which is **also gated**. The builder must accept terms of use on **both** model pages:

- `https://hf.co/pyannote/speaker-diarization-3.1`
- `https://hf.co/pyannote/segmentation-3.0`

Accepting terms on only the diarization page produces a confusing failure at build time.

### No new image tag scheme

`pyannote-audio` is already installed; diarization needs no build variant. The existing
`small` / `medium` / `large-v3` tags are sufficient.

### Known trade-offs (documented in README, not fixed)

- **CPU speed:** the image is CPU-only (torch 2.3.1+cpu, int8). Measured in the smoke test
  (below): a 36 s clip transcribed *and* diarized in ~25 s wall time on the small model —
  much better than the "real-time or worse" worst case; the README can describe
  diarization as adding roughly half the transcription time rather than warning of
  real-time-or-worse.
- **torch pin:** **resolved by the smoke test** — the diarization pipeline ran cleanly on
  torch 2.3.1+cpu. The only warning seen is the pre-existing VAD-model version notice.

### Smoke test result (Step 1 — executed 2026-09-24)

Ran the existing `:small` image with a manual `whisperx --no_align --diarize --hf_token ""`
invocation on `test/we-choose-to-go-to-the-moon.mp4`, `HF_HUB_OFFLINE=1`, pyannote models
supplied via a mounted cache. **Outcome: transcript mode KEEPS `--no_align`.**

- `[SPEAKER_00]:`-prefixed lines appear on STDOUT without the alignment pass — the
  entrypoint change is purely appending `DIA_ARGS`.
- Offline, token-free operation confirmed end-to-end (the plan's no-token-check design).
- **Cache-dir discovery:** pyannote's `Pipeline.from_pretrained` does **not** use the HF
  hub cache — it uses `~/.cache/torch/pyannote`, overridable via `$PYANNOTE_CACHE`. For
  the Dockerfile bake step this is self-consistent (bake and runtime share the in-image
  default), but any manual cache seeding must target `PYANNOTE_CACHE` or the default
  torch path, not `~/.cache/huggingface/hub` alone.
- Diarization-3.1 actually comprises **three** pieces: pipeline `config.yaml` (469 B),
  `pyannote/segmentation-3.0` weights (~5.9 MB), and `pyannote/wespeaker-voxceleb-resnet34-LM`
  embedding weights (~26.6 MB, **not gated**). Total ~33 MB.

---

## User Experience

### Persona 1: the image builder (you, or anyone building locally)

**One-time setup (5 minutes):**
1. Create an HF read token at `hf.co/settings/tokens`.
2. Log in and accept terms on **both** gated model pages (2 clicks each).
3. `export HF_TOKEN=hf_...` in shell profile.

**Every build:**
```bash
make build        # downloads pyannote models via secret mount, bakes them in
make publish      # pushes baked images — no extra steps, no HF_TOKEN needed for the push itself
```
The only new friction vs today is exporting `HF_TOKEN` before building. Forgetting it
fails the build at the bake step with a clear error — by design; export the token and rerun.

### Persona 2: the end user (everyone, on every image)

All images have diarization models baked in. Diarization is **just another flag** — no
token, no config, no setup, no internet beyond the docker pull itself:

```bash
bash transcribex --diarize meeting.mp3
```

What they see, in order:
1. **STDERR progress** from the container (suppress with `-q`): ffmpeg preprocessing,
   transcription, then diarization. Diarization is the slow part — expect roughly
   real-time-or-worse on CPU (a 15-minute recording may take 15+ minutes extra). This
   expectation is set in the README.
2. **STDOUT**: the transcript with speaker labels:
   ```
   [SPEAKER_00]: We choose to go to the moon in this decade...
   [SPEAKER_01]: Not because they are easy, but because they are hard.
   ```
   (Or `-o transcript.txt` to write to a file instead.)

**Speaker-count variant** — if they know how many people spoke:
```bash
bash transcribex --diarize --min-speakers 2 --max-speakers 4 meeting.mp3
```

**Word-aligned variant** — if speaker attribution looks off (see "Attribution accuracy"
below), opt into the alignment pass for word-level speaker annotation:
```bash
bash transcribex --diarize --aligned meeting.mp3
```
Default transcript mode skips alignment (cheap, segment-level labels — a segment bridging
two speakers takes the dominant voice's label). `--aligned` runs the alignment pass too:
whisperx then stamps a speaker onto every **word** (confirmed in the second smoke test),
and the entrypoint regroups the text into speaker-turn lines — so a bridged segment is
**split** at the speaker boundary instead of mislabelled wholesale. Slower (alignment +
diarization, measured ~35 s vs ~25 s on the 36 s test clip, small model), but attributions
follow the words. Subtitle mode always aligns (SRT timing requires it) and ignores the flag.

**Subtitled video**:
```bash
bash subtitlex --diarize interview.mp4          # soft subs, default output name
bash subtitlex --diarize --bake -o final.mp4 interview.mp4   # burned in
```
The SRT track's subtitle text carries speaker labels (`[SPEAKER_00]: ...`), visible in
players regardless of soft or baked.

Runs are fully offline and repeatable — nothing is downloaded on any run.

### Error and edge paths

| Situation | What the user sees |
|-----------|-------------------|
| `--diarize` on any image | Works immediately; fully offline |
| `--min-speakers`/`--max-speakers` without `--diarize` | Flag accepted, passed through to whisperx, no effect (whisperx ignores them without `--diarize`) |
| `--aligned` without `--diarize` | No-op for transcript mode (no diarization → no word labels to align); subtitle mode already aligns |
| No `--diarize` at all | Existing behaviour, unchanged |
| Very long audio on CPU | Works, but slow — README sets the expectation; no artificial limit |
| Build without `HF_TOKEN` | Build fails at the bake step; export the token and rerun |

### What the user never has to do

- Never touches a HuggingFace model page or terms (that's the builder's one-time task).
- Never passes `--hf_token` to whisperx directly — the entrypoint handles it.
- Never mounts a volume, writes a cache dir, or downloads a model at run time.

---

## Implementation

### Step 0: Housekeeping
Add a `.gitignore` covering `.token` (currently untracked but not ignored — a `git add .`
would sweep it in). Note: `.token` is a GitHub PAT, unrelated to diarization; the
HuggingFace token (`hf_...`) is separate.

### Step 1: Smoke test — settle the `--no_align` question first

**DONE (2026-09-24) — see "Smoke test result" under Decisions. Transcript mode keeps
`--no_align`; the entrypoint change is purely appending `DIA_ARGS`. The torch pin is also
cleared.**

### Step 2: `docker/Dockerfile` — mandatory bake

After the existing jfk.wav pre-cache step:

```dockerfile
RUN --mount=type=secret,id=hf_token \
    python -c "from pyannote.audio import Pipeline; \
    Pipeline.from_pretrained('pyannote/speaker-diarization-3.1', \
    use_auth_token=open('/run/secrets/hf_token').read().strip())"

COPY PYANNOTE-NOTICE /etc/PYANNOTE-NOTICE
```

- The bake is unconditional: a build without `HF_TOKEN` **fails** here with the download
  error. That is the intended behaviour — export the token and rerun. No marker file, no
  fallback flavour, no empty-secret short-circuit to reason about.
- The token never enters image layers, build cache, or `docker history`.
- The download lands in pyannote's native cache path (`~/.cache/torch/pyannote`), not the
  HF hub cache — the smoke-test discovery. No `PYANNOTE_CACHE` configuration needed: the
  runtime reads the same default.
- `PYANNOTE-NOTICE` lives in `docker/` (the build context), not the repo root — the
  `COPY PYANNOTE-NOTICE` path is relative to the context, so a root-level copy fails the
  build with `"/PYANNOTE-NOTICE": not found`. Discovered when the notice was briefly
  moved to the root; a cached rebuild masked the failure once before a no-cache build
  exposed it.

### Step 3: `Makefile` — one line

Add `--secret id=hf_token,env=HF_TOKEN` to the `build-%` recipe. The builder exports
`HF_TOKEN=hf_...` once (terms accepted on **both** gated model pages). `publish` is
unchanged — it pushes the baked images built by `build`. The publish host therefore also
needs `HF_TOKEN` set at build time; document in the README.

### Step 4: `docker/entrypoint.sh` — single source of truth for diarization logic

**New flags:** `--diarize` / `-d`, `--aligned` / `-a`, `--min-speakers <n>`,
`--max-speakers <n>`.

**Build the whisperx flags once, use twice:**
```bash
DIA_ARGS=()
if [ -n "$DIARIZE" ]; then
    DIA_ARGS=(--diarize --hf_token ""
              ${MIN_SPEAKERS:+--min_speakers "$MIN_SPEAKERS"}
              ${MAX_SPEAKERS:+--max_speakers "$MAX_SPEAKERS"})
fi
```
Append `"$DIA_ARGS"` to **both** whisperx invocations (transcript and subtitle mode). No
duplication of the flag list.

**No token logic at all:** every image has the models baked in, so when `--diarize` is set
the entrypoint sets `HF_HUB_OFFLINE=1` — huggingface_hub never contacts the Hub, and the
empty `--hf_token ""` is passed harmlessly to satisfy whisperx's argument check. There is
**no** token check anywhere in the codebase. Without this flag, a diarized run wastes
~40 seconds on HEAD-request retries against huggingface.co (5 retries per model file,
3 model repos) before falling back to the local cache — discovered in the first
entrypoint test, which ran without the env var and worked but stalled.

**Transcript mode:** keeps `--no_align` by default (settled by the Step 1 smoke test) —
the change is purely appending `"$DIA_ARGS"`. When `--aligned` is also set: **omit**
`--no_align` and run with `--output_format json` instead of `txt`, because the TXT writer
prints only segment labels — word-level speaker labels (which exist only when alignment
ran) would be discarded. The entrypoint then regroups the JSON words into speaker-turn
lines (splitting bridged segments at speaker boundaries) and prints them to STDOUT as
`[SPEAKER_XX]: text` lines, same shape as the default output.

### Step 5: `transcribex` and `subtitlex` — flag passthrough only

Identical changes to both, and nothing else:
- **New flags:** `--diarize` / `-d`, `--aligned` / `-a`, `--min-speakers`, `--max-speakers`.
  (`--aligned` is accepted by both for a uniform CLI; the entrypoint decides its effect —
  meaningful only in transcript mode.)
- No env forwarding, no volume mounts, no host-side conditionals — images are
  self-contained.

### Step 6: `PYANNOTE-NOTICE` (new file)
The MIT licence text for the baked weights, attribution to pyannote, and pointers to the
HF model pages whose terms the builder accepted.

### Step 7: `README.md` — Diarization section
- What diarization does and when to use it.
- The two transcript modes: default (segment-level labels, cheap) and `--aligned`
  (word-level labels; bridged segments split at speaker boundaries) — with guidance that
  `SPEAKER_XX` means "dominant voice in this segment", and `--aligned` is the tool to
  reach for when attribution looks off.
- **Attribution accuracy:** speaker labels are assigned per segment by time overlap; a
  segment that bridges two speakers takes the label of the dominant voice, so the first
  words after a speaker hand-off can carry the previous speaker's label. Crosstalk and
  backchannel ("mm-hm") may be absorbed into the dominant speaker. Passing
  `--min-speakers`/`--max-speakers` when the count is known prevents the clusterer from
  merging similar voices.
- Building: requires `HF_TOKEN` and terms accepted on **both** gated model pages; the
  resulting image (local or pulled from Docker Hub) is fully offline for diarization.
- Usage examples.
- The CPU performance expectation (measured: diarization adds roughly half the
  transcription time on the small model).

---

## Fallback Build Method: pre-download + COPY with SHA256 in the tag

Not a runtime fallback — a build-time alternative, used only if secret-mounting is ever
unavailable in some build environment.

1. On a machine with `HF_TOKEN` and terms accepted, pre-download once:
   ```bash
   python -c "from pyannote.audio import Pipeline; \
   Pipeline.from_pretrained('pyannote/speaker-diarization-3.1', \
   use_auth_token='$HF_TOKEN')"
   tar -C "$HOME/.cache/huggingface" -czf pyannote-cache.tar.gz .
   sha256sum pyannote-cache.tar.gz
   ```
2. Extract into `docker/pyannote-cache/` (git-ignored), `COPY` it to
   `/root/.cache/huggingface/` in the Dockerfile.
3. Encode the cache SHA256 (first 12 hex chars) in the image tag:
   `gencore/whisperx-speech-to-text:3.4.2-medium-diarize-<sha12>`, with the full SHA256 in
   an OCI label. Plain tags (no suffix) continue to mean "built with secret, models baked".

---

## Effort Estimate

| File | Change size |
|------|-------------|
| `docker/Dockerfile` | ~8 lines |
| `Makefile` | ~1 line |
| `docker/entrypoint.sh` | ~30 lines (includes JSON→speaker-turn regrouping for `--aligned`) |
| `transcribex` | ~16 lines |
| `subtitlex` | ~16 lines |
| `PYANNOTE-NOTICE` | ~10 lines |
| `README.md` | ~40 lines |
| `.gitignore` | 1 line |

---

## Example Usage After Implementation

```bash
# One-time, on the build machine:
export HF_TOKEN=hf_your_token_here   # terms accepted on both gated model pages
make build
make publish                          # pushes baked images; licence-compliant (MIT)

# Using the image — no token, no cache volume, no first-run download:
bash transcribex --diarize meeting.mp3

# Transcribe with known speaker count
bash transcribex --diarize --min-speakers 2 --max-speakers 4 meeting.mp3

# Word-level aligned speaker annotation (slower; use if attribution looks off)
bash transcribex --diarize --aligned meeting.mp3

# Add diarized subtitles to a video
bash subtitlex --diarize --model medium interview.mp4
```

**Example output (transcript mode with diarization):**
```
[SPEAKER_00]: We choose to go to the moon in this decade and do the other things.
[SPEAKER_01]: Not because they are easy, but because they are hard.
[SPEAKER_00]: Because that goal will serve to organise and measure the best of our energies.
```

---

## Deferred (out of scope)

- **pyannote community-1 upgrade:** see [COMMUNITY-1-UPGRADE.md](COMMUNITY-1-UPGRADE.md).
  Defer until this plan ships.

---

## References

### WhisperX
- [WhisperX GitHub repository](https://github.com/m-bain/whisperX) — pinned at 3.3.2 in
  `requirements.txt`, 3.4.2 in the `Makefile`.
- [WhisperX 3.3.2 `transcribe.py`](https://github.com/m-bain/whisperX/blob/v3.3.2/whisperx/transcribe.py) —
  source of the CLI-flag verification (`--diarize`, `--min_speakers`, `--max_speakers`,
  `--hf_token` all present).
- [WhisperX 3.3.2 `diarize.py`](https://github.com/m-bain/whisperX/blob/v3.3.2/whisperx/diarize.py) —
  `DiarizationPipeline` and `assign_word_speakers`; diarization runs regardless of
  `--no_align` and assigns labels via time overlap.
- [WhisperX 3.3.2 `utils.py`](https://github.com/m-bain/whisperX/blob/v3.3.2/whisperx/utils.py) —
  output writers: TXT prefixes `[SPEAKER_00]:`, SRT prepends speaker labels.
- [WhisperX on PyPI](https://pypi.org/project/whisperx/) — version history and Python
  version requirements for the phase-2 upgrade path.

### pyannote models (gated — terms must be accepted)
- [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1) —
  the pipeline baked in this plan. Gated; **MIT-licensed** weights (the licence basis for
  baking into published images).
- [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0) — pulled
  internally by the 3.1 pipeline; also gated, also must have terms accepted.
- [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) —
  phase-2 successor: better quality, exclusive ASR-alignment output, CC BY 4.0; requires
  pyannote.audio 4.x + torch 2.8 family + whisperx 3.8.x (see COMMUNITY-1-UPGRADE.md).

### pyannote.audio
- [pyannote.audio releases](https://github.com/pyannote/pyannote-audio/releases) — v4.x
  version notes (torch 2.8 family pin, torchcodec dependency) relevant to the phase-2
  upgrade.

### Known issues
- [WhisperX issue #1322](https://github.com/m-bain/whisperX/issues/1322) — older whisperx
  versions' `use_auth_token=` incompatibility with pyannote.audio 4.0.1+; confirms the
  whisperx pin must move together with pyannote in phase 2.
