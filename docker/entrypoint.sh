#!/bin/bash

set -e

HELP_MESSAGE="
Media is read from STDIN. By default, the transcript is written to STDOUT.

If --output is provided, the input must be a video. An MP4 with a subtitle
track is written to STDOUT. Add --bake to burn the subtitles into the video
stream instead (hardsubs).

Usage: $0 [--output] [--bake] [--help]
  --output, -o: Trigger subtitle/video mode. Output MP4 is written to STDOUT.
  --bake,   -b: Used with --output. Burns subtitles into the video stream.
  --help,   -h: Display this help message."

usage() {
    echo "$HELP_MESSAGE" >&2
    exit 1
}

VIDEO=false
BAKE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --output|-o)
            VIDEO=true
            ;;
        --bake|-b)
            BAKE=true
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
# -----------------------------------------------
if [ "$VIDEO" == "false" ]; then
	whisperx \
	  --threads $(nproc) \
	  --model ${MODEL_SIZE} \
	  --compute_type int8 \
	  --output_format txt \
	  --output_dir /tmp \
	  --language en \
	  --no_align \
	  --print_progress True \
	  "$AUDIO" >&2
	cat /tmp/audio.txt
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