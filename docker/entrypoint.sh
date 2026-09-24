#!/bin/bash

set -e

HELP_MESSAGE="
Media is read from STDIN. By default, the transcript is written to STDOUT.

If --output is provided, the input must be a video. An MP4 with a subtitle
track is written to STDOUT. Add --bake to burn the subtitles into the video
stream instead (hardsubs).

Speaker diarization labels each transcript line with the speaker who said it
(e.g. [SPEAKER_00]:). The diarization models are baked into this image; no
token or network access is needed.

Usage: $0 [--output] [--bake] [--diarize] [--aligned] [--help]
  --output, -o: Trigger subtitle/video mode. Output MP4 is written to STDOUT.
  --bake,   -b: Used with --output. Burns subtitles into the video stream.
  --diarize, -d: Assign speaker labels ([SPEAKER_00]: ...) to the output.
  --aligned, -a: With --diarize in transcript mode, run the alignment pass for
                 word-level speaker attribution (slower, finer-grained labels).
  --min-speakers N: With --diarize, lower bound for speaker count.
  --max-speakers N: With --diarize, upper bound for speaker count.
  --help,   -h: Display this help message."

usage() {
    echo "$HELP_MESSAGE" >&2
    exit 1
}

VIDEO=false
BAKE=false
DIARIZE=""
ALIGNED=""
MIN_SPEAKERS=""
MAX_SPEAKERS=""

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
        --min-speakers)
            MIN_SPEAKERS="$2"
            shift
            ;;
        --max-speakers)
            MAX_SPEAKERS="$2"
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
# Diarization flags — built once, appended to both
# whisperx invocations below.
# Models are baked into the image at PYANNOTE_CACHE;
# HF_HUB_OFFLINE keeps huggingface_hub away from the
# network and the empty token satisfies the CLI check.
# -----------------------------------------------
DIA_ARGS=()
if [ -n "$DIARIZE" ]; then
    export HF_HUB_OFFLINE=1
    DIA_ARGS=(--diarize --hf_token ""
              ${MIN_SPEAKERS:+--min_speakers "$MIN_SPEAKERS"}
              ${MAX_SPEAKERS:+--max_speakers "$MAX_SPEAKERS"})
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
ffmpeg -i "$INPUT" \
	-ar 16000 \
	-ac 1 \
	-filter:a dynaudnorm \
	"$AUDIO" >&2

MODEL_SIZE=$(cat /etc/model_size)

# -----------------------------------------------
# Transcript Mode
# Skip alignment; output plain text to STDOUT.
# With --aligned (and --diarize), run the alignment
# pass and emit JSON so word-level speaker labels can
# be regrouped into speaker-turn lines below.
# -----------------------------------------------
if [ "$VIDEO" == "false" ]; then
	ALIGN_ARGS=(--no_align)
	OUT_FORMAT=txt
	if [ -n "$ALIGNED" ] && [ -n "$DIARIZE" ]; then
		ALIGN_ARGS=()
		OUT_FORMAT=json
	fi
	whisperx \
	  --threads $(nproc) \
	  --model ${MODEL_SIZE} \
	  --compute_type int8 \
	  --output_format ${OUT_FORMAT} \
	  --output_dir /tmp \
	  --language en \
	  "${ALIGN_ARGS[@]}" \
	  --print_progress True \
	  "${DIA_ARGS[@]}" \
	  "$AUDIO" >&2
	if [ "$OUT_FORMAT" == "json" ]; then
		# Regroup word-level speaker labels into speaker-turn lines.
		# A segment bridging two speakers is split at the boundary.
		python3 - <<'PYEOF'
import json

data = json.load(open("/tmp/audio.json"))
current = None
line = []
for seg in data["segments"]:
    for word in seg.get("words", []):
        spk = word.get("speaker", seg.get("speaker"))
        if spk != current and line:
            print(f"[{current}]: " + " ".join(line))
            line = []
        current = spk
        line.append(word["word"])
if line and current:
    print(f"[{current}]: " + " ".join(line))
PYEOF
	else
		cat /tmp/audio.txt
	fi
	exit
fi

# -----------------------------------------------
# Video/Subtitle Mode
# Run alignment for accurate subtitle timing, then
# mux with the original video and stream to STDOUT
# as a fragmented MP4 (seekable output not required).
# -----------------------------------------------
whisperx \
	--model ${MODEL_SIZE} \
	--compute_type int8 \
	--output_format srt \
	--output_dir /tmp \
	--language en \
	--print_progress True \
	"${DIA_ARGS[@]}" \
	"$AUDIO" >&2

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