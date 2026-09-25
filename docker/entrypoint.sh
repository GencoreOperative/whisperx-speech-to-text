#!/bin/bash

set -e

# -----------------------------------------------
# Signal forwarding. The entrypoint is PID 1, which
# the kernel treats specially: unhandled SIGINT/SIGTERM
# are ignored. Bash also defers traps while a foreground
# command runs — and docker's signal proxy only signals
# PID 1, never its children. Running the long steps via
# run() (background + wait) makes the traps fire
# immediately, so Ctrl+C cancels the step instead of
# stalling until it finishes.
# -----------------------------------------------
FWD_PID=""
cancel() {
    [ -n "$FWD_PID" ] && kill -TERM "$FWD_PID" 2>/dev/null
    exit 130
}
trap cancel INT TERM

run() {
    "$@" &
    FWD_PID=$!
    wait "$FWD_PID"
}

HELP_MESSAGE="
Media is read from STDIN. By default, the transcript is written to STDOUT.

If --output is provided, the input must be a video. An MP4 with a subtitle
track is written to STDOUT. Add --bake to burn the subtitles into the video
stream instead (hardsubs).

Speaker diarization labels each transcript line with the speaker who said it
(e.g. [SPEAKER_00]:). The diarization models are baked into this image; no
token or network access is needed. Diarization progress is reported to STDERR.

Usage: $0 [--output] [--bake] [--diarize] [--aligned] [--help]
  --output, -o: Trigger subtitle/video mode. Output MP4 is written to STDOUT.
  --bake,   -b: Used with --output. Burns subtitles into the video stream.
  --diarize, -d: Assign speaker labels ([SPEAKER_00]: ...) to the output.
  --aligned, -a: With --diarize in transcript mode, run the alignment pass for
                 word-level speaker attribution (slower, finer-grained labels).
  --num-speakers N: With --diarize, exact speaker count. Constraining the
                 count improves both attribution accuracy and diarization speed.
  --help,   -h: Display this help message."

usage() {
    echo "$HELP_MESSAGE" >&2
    exit 1
}

VIDEO=false
BAKE=false
DIARIZE=""
ALIGNED=""
NUM_SPEAKERS=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --output|-o)
            VIDEO=true
            ;;
        --bake|-b)
            BAKE=true
            ;;
        --diarize|-d)
            DIARIZE=1
            ;;
        --aligned|-a)
            ALIGNED=1
            ;;
        --num-speakers)
            NUM_SPEAKERS="$2"
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown parameter: $1" >&2
            usage
            ;;
    esac
    shift
done

# -----------------------------------------------
# Diarization is driven by diarize_progress.py (see
# the script header for why we bypass --diarize).
# Models are baked into the image at PYANNOTE_CACHE;
# HF_HUB_OFFLINE keeps huggingface_hub away from the
# network.
# -----------------------------------------------
DIA_ARGS=()
if [ -n "$DIARIZE" ]; then
    export HF_HUB_OFFLINE=1
    DIA_ARGS=(${NUM_SPEAKERS:+--num-speakers "$NUM_SPEAKERS"})
fi

# -----------------------------------------------
# Read STDIN into a temp file.
# ffmpeg requires a seekable input for most formats.
# -----------------------------------------------
INPUT=/tmp/stdin_input
cat - > "$INPUT"

if [ ! -s "$INPUT" ]; then
    echo "Error: No input received on STDIN." >&2
    usage
fi

# -----------------------------------------------
# Audio Extraction
# Convert the provided media to 16kHz mono WAV.
# -----------------------------------------------
AUDIO=/tmp/audio.wav
run ffmpeg -i "$INPUT" \
	-ar 16000 \
	-ac 1 \
	-filter:a dynaudnorm \
	"$AUDIO" >&2

MODEL_SIZE=$(cat /etc/model_size)

# -----------------------------------------------
# Transcript Mode
# Output plain text to STDOUT. Whisperx always writes
# JSON here; diarizing post-processes it with speaker
# labels, otherwise it is regrouped into plain lines.
# Default (no --aligned) skips the alignment pass —
# segment-level speaker labels, cheaper.
# -----------------------------------------------
if [ "$VIDEO" == "false" ]; then
	ALIGN_ARGS=(--no_align)
	if [ -n "$DIARIZE" ] && [ -n "$ALIGNED" ]; then
		ALIGN_ARGS=()
	fi
	run whisperx \
	  --threads $(nproc) \
	  --model ${MODEL_SIZE} \
	  --compute_type int8 \
	  --output_format json \
	  --output_dir /tmp \
	  --language en \
	  "${ALIGN_ARGS[@]}" \
	  --print_progress True \
	  "$AUDIO" >&2
	if [ -n "$DIARIZE" ]; then
		run python3 /diarize_progress.py \
			--audio "$AUDIO" \
			--json /tmp/audio.json \
			"${DIA_ARGS[@]}"
	else
		# Regroup JSON into plain text lines.
		python3 -c 'import json
data = json.load(open("/tmp/audio.json"))
for seg in data["segments"]:
    print(seg["text"].strip())'
	fi
	exit
fi

# -----------------------------------------------
# Video/Subtitle Mode
# Run alignment for accurate subtitle timing, then
# mux with the original video and stream to STDOUT
# as a fragmented MP4 (seekable output not required).
# -----------------------------------------------
run whisperx \
	--model ${MODEL_SIZE} \
	--compute_type int8 \
	--output_format json \
	--output_dir /tmp \
	--language en \
	--print_progress True \
	"$AUDIO" >&2

if [ -n "$DIARIZE" ]; then
	# Diarize (with progress) and write /tmp/audio.srt.
	run python3 /diarize_progress.py \
		--audio "$AUDIO" \
		--json /tmp/audio.json \
		--srt \
		"${DIA_ARGS[@]}"
else
	# JSON → SRT with whisperx's own writer.
	python3 -c 'import json
from whisperx.utils import get_writer
result = json.load(open("/tmp/audio.json"))
result.setdefault("language", "en")
get_writer("srt", "/tmp")(result, "/tmp/audio.wav", {
    "highlight_words": False, "max_line_count": None, "max_line_width": None})'
fi

if [ "$BAKE" == "true" ]; then
	# Hard subtitles: burn text into the video stream
	ffmpeg -i "$INPUT" \
		-vf subtitles=/tmp/audio.srt \
		-c:v libx264 \
		-profile:v high \
		-crf 22 \
		-c:a aac \
		-q:a 6 \
		-filter:a dynaudnorm \
		-movflags frag_keyframe+empty_moov \
		-f mp4 \
		pipe:1
else
	# Soft subtitles: add as a separate subtitle track
	# https://superuser.com/questions/700082/is-there-an-option-in-ffmpeg-to-specify-a-subtitle-track-that-should-be-shown-by
	ffmpeg -i "$INPUT" \
		-i /tmp/audio.srt \
		-c:v copy \
		-c:a copy \
		-c:s mov_text \
		-metadata:s:s:0 language=eng \
		-disposition:s:0 default \
		-movflags frag_keyframe+empty_moov \
		-f mp4 \
		pipe:1
fi