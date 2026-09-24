# Phase-2 Upgrade: pyannote community-1

Out of scope for the [DIARIZE-PLAN.md](DIARIZE-PLAN.md) implementation; this is the
recorded follow-up. Revisit after the diarization plan ships.

## What it is

`pyannote/speaker-diarization-community-1` is pyannote's successor to
`speaker-diarization-3.1`:

- Measurably better diarization error rates (e.g. AliMeeting 20.3% vs 24.5%; CALLHOME
  26.7% vs 28.5%; DIHARD 3 20.2% vs 21.4%; slightly worse on REPERE 8.9% vs 7.9%).
- An **exclusive** diarization output (`output.exclusive_speaker_diarization`) designed
  specifically for aligning diarization with ASR timestamps — exactly the whisperx use case.
- Licence: **CC BY 4.0** (redistribution permitted with attribution). Still gated on
  HuggingFace (accept conditions + token).
- Same speaker-count controls (`num_speakers`, `min_speakers`, `max_speakers`).

## Why it is not a drop-in

Adopting it breaks all three of the image's carefully-earned dependency pins:

| Component | Current pin | Required for community-1 |
|-----------|-------------|--------------------------|
| pyannote-audio | 3.3.2 | **4.x** (4.0.2+ recommended) |
| torch / torchaudio | 2.3.1+cpu | **2.8.0** family, plus new **torchcodec 0.7.x** |
| whisperx | 3.3.2 / 3.4.2 | **~3.8.x** (defaults to community-1; uses `token=`, not the deprecated `use_auth_token=`; older versions are reported incompatible with pyannote 4.0.1+) |

Notes:
- pyannote.audio 4.x dropped Python < 3.10; 4.0.2 pinned the torch family to avoid
  segmentation faults. Do not mix torch / torchaudio / torchcodec versions.
- pyannote v4 switched audio decoding to TorchCodec, which hard-requires **ffmpeg**
  (already in the image).
- CPU-only 2.8 wheels exist, so the image stays CPU-viable, but the Dockerfile's derived
  minimal-dependency list (see its "Install CPU-only torch" comment block) would need
  redoing — the original motivation for the 2.3.1+cpu pin was avoiding huge CUDA wheels.
- WhisperX reads the ordinary `speaker_diarization` output for speaker-label assignment;
  the exclusive output is what makes timestamp alignment easier.

## What survives the upgrade unchanged

The baking mechanism from DIARIZE-PLAN.md (BuildKit secret mount, `/etc/diarize_preloaded`
marker, `PYANNOTE-NOTICE`, entrypoint `DIA_ARGS` flow) survives unchanged — only the model
name in the Dockerfile prefetch step and the dependency layers change.

## Migration sketch

1. Bump whisperx to ~3.8.x in `Makefile` / `requirements.txt`; re-verify the STDIN/STDOUT
   entrypoint flow against the new version (flag names and output writers may have shifted).
2. Rebuild the dependency list: pyannote-audio 4.x, torch 2.8.0 + torchaudio 2.8.0 +
   torchcodec 0.7.x (cpu index), keeping the image CPU-only and minimal.
3. Re-run the checkpoint-upgrade step against the new whisperx assets.
4. Change the Dockerfile prefetch model name to
   `pyannote/speaker-diarization-community-1` (single gated model page now, not two).
5. Update `PYANNOTE-NOTICE` for CC BY 4.0 attribution.
6. Re-run the `--no_align` smoke test from DIARIZE-PLAN.md Step 1 against the new stack.
