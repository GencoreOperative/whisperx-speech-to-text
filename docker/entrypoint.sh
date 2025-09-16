#!/bin/bash

set -e

# This script will process the input arguments for the user. 
# See the help information for the arguents.

# Help message
HELP_MESSAGE="Usage: $0 <input> [--output <output>] [--bake] [--help]
  <input>: Required. A media file that must exist.
  --output, -o: Optional output file to store the output video. If no file name is provided, then one will be generated.
  --bake, -b: Optional. Bake-in selector flag that will cause the subtitles to be baked into the video.
  --help, -h: Display this help message."

# Function to display usage information
usage() {
    echo "$HELP_MESSAGE"
    exit 1
}

# Check if at least one argument (input file) is provided
if [ $# -lt 1 ]; then
    usage
fi

# Initialize variables
SOURCE=""
TARGET=""
BAKE=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --output|-o)
            TARGET="$2"
            shift
            ;;
        --bake|-b)
            BAKE=true
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [ -z "$SOURCE" ]; then
                SOURCE="$1"
            else
                echo "Unknown parameter: $1"
                usage
            fi
            ;;
    esac
    shift
done

# Check if the input file exists
if [ ! -f "$SOURCE" ]; then
    echo "Input file does not exist: $SOURCE"
    usage
fi

# Generate default output file name if not provided
if [ -z "$TARGET" ]; then
    TARGET=$(dirname "$SOURCE")/subtitle-$(basename "$SOURCE")
fi

# -----------------------------------------------
# Extract the audio from the video so Whisper can
# listen to it.
# -----------------------------------------------
# Even if the source is an MP3 file, we need to create
# to ensure that the AUDIO is a fixed name. This helps
# the downstream stages of processing.

AUDIO=/tmp/audio.mp3
ffmpeg -i "$SOURCE" \
	-ar 44100 \
	-filter:a dynaudnorm \
	$AUDIO

# -----------------------------------------------
# Run the audio through Whisper for transcription
# -----------------------------------------------
# This will generate the multiple output files including the subtitle file.
# Note: https://github.com/openai/whisper/discussions/301 provided the tip on FP16 mode
MODEL_SIZE=$(cat /etc/model_size)
cd /audio && whisperx \
	--model ${MODEL_SIZE} \
	--compute_type int8 \
	--output_format all \
	--language en \
	$AUDIO

# If the source was a Video file, convert into the target MP4 file 
# with the subtitle track included. If the mode flag was set, then
# instead, bake the subtitles into the video stream.
SOURCE_EXTENSION=$(echo "$SOURCE" | rev | cut -d'.' -f1 | tr '[:upper:]' '[:lower:]' | rev)
VIDEO_EXTENSIONS=("mp4" "avi" "mkv" "mov" "wmv" "flv" "webm" "m4v" "mpg" "mpeg" "3gp")

for VIDEO_EXTENSION in "${VIDEO_EXTENSIONS[@]}"; do
    if [ "$SOURCE_EXTENSION" == "$VIDEO_EXTENSION" ]; then
    	
		# If the caller provides the 'bake-in flag' then we need
		# to remove the instruction to add a new subtitle track
		# and instead let FFMPEG back the subtitles into the video
		# stream.

		if [ ! -z "$MODE" ]; then
			ffmpeg -i "$SOURCE" \
				-y \
				-vf subtitles=audio.srt \
	    		-c:v libx264 \
				-profile:v high \
				-crf 22 \
				-strict experimental \
				-c:a aac \
				-q:a 6 \
				-filter:a dynaudnorm \
				-c:s mov_text \
	    		"$TARGET"
		else
			# https://superuser.com/questions/700082/is-there-an-option-in-ffmpeg-to-specify-a-subtitle-track-that-should-be-shown-by
			# Provided detail on the subtitle commands
			ffmpeg -i "$SOURCE" \
				-y \
				-i audio.srt \
				-c:v copy \
				-c:a copy \
				-c:s mov_text \
    			-metadata:s:s:0 language=eng \
    			-disposition:s:0 default \
    			"$TARGET"
		fi

        break
    fi
done

rm audio.json
rm audio.tsv
rm audio.vtt