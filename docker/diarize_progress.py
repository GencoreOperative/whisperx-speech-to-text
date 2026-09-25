#!/usr/bin/env python3
"""Run speaker diarization with progress reporting, then merge the speaker
labels into a whisperx JSON transcript.

This replaces whisperx's `--diarize` flag. whisperx's own diarization path
(whisperx/diarize.py) calls the pyannote pipeline without a progress hook, so
on CPU the slowest phase of a run is completely silent. We drive the same
pyannote pipeline directly, passing a hook that reports per-batch progress to
STDERR, then reuse whisperx's own `assign_word_speakers` to merge the labels
into the transcript — the merge logic stays upstream's, not forked.

The pyannote models are baked into the image (see the Dockerfile); runs are
fully offline (the entrypoint exports HF_HUB_OFFLINE=1).

Mode of use (the entrypoint always writes the transcription to
/tmp/audio.json first):
  - Subtitle mode: --srt writes /tmp/audio.srt for the ffmpeg mux step.
  - Transcript mode: speaker-turn lines are printed to STDOUT.
"""

import argparse
import json
import os
import signal
import sys

import pandas as pd
import torch
from pyannote.audio import Pipeline
from whisperx.audio import SAMPLE_RATE, load_audio
from whisperx.diarize import assign_word_speakers
from whisperx.utils import get_writer


def make_progress_hook():
    """Build a pyannote pipeline hook that reports progress on STDERR.

    pyannote calls the hook with (step_name, artefact) at each step
    transition, and with additional `completed`/`total` keyword arguments
    repeatedly during the time-consuming steps (segmentation, embeddings).
    Percentage lines reuse the same terminal line; a step without them ends
    the line. The clustering step between embeddings and output is silent in
    pyannote, but is comparatively quick.
    """
    state = {"line_open": False}

    def hook(step, artefact, file=None, completed=None, total=None):
        if completed is not None and total:
            pct = min(100, round(100 * completed / total))
            print(f"\r>>Diarizing: {step}: {pct}% ({min(completed, total)}/{total} chunks)   ",
                  end="", flush=True, file=sys.stderr)
            state["line_open"] = True
        elif state["line_open"]:
            print(" done", flush=True, file=sys.stderr)
            state["line_open"] = False
        else:
            print(f">>Diarizing: {step}...", flush=True, file=sys.stderr)

    return hook


def print_speaker_turns(result):
    """Print the transcript as speaker-turn lines to STDOUT.

    With word-level labels (--aligned), lines are regrouped at speaker
    boundaries and a segment bridging two speakers is split at the boundary.
    Without them, each segment is one line labelled by its dominant voice —
    the same shape as whisperx's TXT writer.
    """
    current = None
    line = []
    for seg in result["segments"]:
        words = seg.get("words")
        if words:
            for word in words:
                spk = word.get("speaker", seg.get("speaker"))
                if spk != current and line:
                    print(f"[{current}]: " + " ".join(line))
                    line = []
                current = spk
                line.append(word["word"])
        else:
            if line:
                print(f"[{current}]: " + " ".join(line))
                line = []
                current = None
            spk = seg.get("speaker")
            text = seg["text"].strip()
            print(f"[{spk}]: {text}" if spk else text)
    if line and current:
        print(f"[{current}]: " + " ".join(line))


def main():
    # Cancelled (SIGTERM forwarded by the entrypoint's traps): close the
    # progress line so the cancellation is legible, and exit with 130 like
    # a Ctrl+C'd process. Torch's inference loop does not unwind cleanly on
    # signals, so raise instead of returning.
    def cancelled(signum, frame):
        print("\n>>Diarizing: cancelled", file=sys.stderr)
        sys.exit(130)

    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    parser = argparse.ArgumentParser(description="Diarize a whisperx JSON transcript with progress reporting.")
    parser.add_argument("--audio", required=True,
                        help="16kHz mono WAV to diarize (the whisperx input)")
    parser.add_argument("--json", required=True,
                        help="whisperx JSON transcript, updated in place with speaker labels")
    parser.add_argument("--srt", action="store_true",
                        help="write an SRT next to the JSON (subtitle mode) instead of printing transcript lines")
    parser.add_argument("--num-speakers", type=int,
                        help="exact speaker count — constrains the clusterer "
                             "and speeds the pipeline up")
    parser.add_argument("--batch-size", type=int, default=1,
                        help="chunks per inference batch for segmentation and "
                             "embeddings. Measured on CPU (Ryzen, 16 threads): "
                             "values >1 are SLOWER — torch already parallelises "
                             "within each chunk; batching only helps on GPU")
    args = parser.parse_args()

    with open(args.json, encoding="utf-8") as f:
        result = json.load(f)

    print(">>Diarizing: loading pyannote pipeline...", flush=True, file=sys.stderr)
    pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")
    pipeline.segmentation_batch_size = args.batch_size
    pipeline.embedding_batch_size = args.batch_size
    audio = load_audio(args.audio)
    audio_data = {
        "waveform": torch.from_numpy(audio[None, :]),
        "sample_rate": SAMPLE_RATE,
    }
    diarization = pipeline(
        audio_data,
        num_speakers=args.num_speakers,
        min_speakers=None,
        max_speakers=None,
        hook=make_progress_hook(),
    )

    # Label merge identical to whisperx's DiarizationPipeline (whisperx/diarize.py).
    diarize_df = pd.DataFrame(
        diarization.itertracks(yield_label=True),
        columns=["segment", "label", "speaker"],
    )
    diarize_df["start"] = diarize_df["segment"].apply(lambda x: x.start)
    diarize_df["end"] = diarize_df["segment"].apply(lambda x: x.end)
    assign_word_speakers(diarize_df, result)

    if args.srt:
        # whisperx's own SRT writer — the same one --output_format srt uses.
        # It emits segment-level cues when words are absent and prefixes
        # speaker labels to the subtitle text when present.
        result.setdefault("language", "en")
        out_dir = os.path.dirname(os.path.abspath(args.json))
        get_writer("srt", out_dir)(result, args.audio, {
            "highlight_words": False,
            "max_line_count": None,
            "max_line_width": None,
        })
    else:
        print_speaker_turns(result)


if __name__ == "__main__":
    main()
