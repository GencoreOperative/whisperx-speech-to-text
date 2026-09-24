# Diarization Implementation Plan

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
so unaligned segments still carry speaker labels (verified in source). Whether transcript
mode can keep `--no_align` is settled by the Step 1 smoke test.

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

- **CPU speed:** the image is CPU-only (torch 2.3.1+cpu, int8); pyannote's
  speaker-embedding stage runs at roughly real-time or slower on CPU.
- **torch pin:** the Dockerfile pins torch 2.3.1+cpu while pyannote 3.3.2's lockfile lists
  torch 2.7.0. Untested together — budget one debugging session on first real `--diarize` run.

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

Before any code changes, run the existing image with a manual `whisperx --diarize`
invocation on `test/jfk.wav` (or `bain23.pdf`'s companion audio) with `--no_align` and
inspect the output. If `[SPEAKER_XX]:` prefixes appear, transcript mode keeps `--no_align`
and the entire entrypoint change reduces to appending pre-built diarization args; if not,
transcript mode drops `--no_align` when diarizing. This also gives an early answer to the
torch-pin caveat above.

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

### Step 3: `Makefile` — one line

Add `--secret id=hf_token,env=HF_TOKEN` to the `build-%` recipe. The builder exports
`HF_TOKEN=hf_...` once (terms accepted on **both** gated model pages). `publish` is
unchanged — it pushes the baked images built by `build`. The publish host therefore also
needs `HF_TOKEN` set at build time; document in the README.

### Step 4: `docker/entrypoint.sh` — single source of truth for diarization logic

**New flags:** `--diarize` / `-d`, `--min-speakers <n>`, `--max-speakers <n>`.

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
**no** token check anywhere in the codebase.

**Transcript mode:** per the Step 1 smoke test — either keep `--no_align` (change is purely
appending `"$DIA_ARGS"`) or drop it when `DIARIZE` is set.

### Step 5: `transcribex` and `subtitlex` — flag passthrough only

Identical changes to both, and nothing else:
- **New flags:** `--diarize` / `-d`, `--min-speakers`, `--max-speakers`.
- No env forwarding, no volume mounts, no host-side conditionals — images are
  self-contained.

### Step 6: `PYANNOTE-NOTICE` (new file)
The MIT licence text for the baked weights, attribution to pyannote, and pointers to the
HF model pages whose terms the builder accepted.

### Step 7: `README.md` — Diarization section
- What diarization does and when to use it.
- Building: requires `HF_TOKEN` and terms accepted on **both** gated model pages; the
  resulting image (local or pulled from Docker Hub) is fully offline for diarization.
- Usage examples.
- The CPU performance expectation.

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
| `docker/entrypoint.sh` | ~15 lines |
| `transcribex` | ~12 lines |
| `subtitlex` | ~12 lines |
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
