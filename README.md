# Overview

This is a Docker project to enable command line access to the [WhisperX](https://github.com/m-bain/whisperX) speech to text engine that can be run on CPU only.

> Whisper is a neural network that has been trained to achieve human levels of robustness and accuracy on English speech recognition. Any-to-English translation is supported as well. WhisperX expands on this by improving the speed of transcription, as well as adding features for automatic language detection and word-level subtitling.

Initial testing for a 4 minute 20 seconds video shows the following conversion times:
- Whisper: 7 minutes 20 seconds
- WhisperX: 1 minute 15 seconds

# Project Details

The architecture for this project consists of packaging together all tools required to generate a transcription of a media file. We make use of [`ffmpeg`](https://ffmpeg.org/) for audio conversion and subtitle processing. We use [`whisperx`](https://pypi.org/project/whisperx/) to provide the ASR (Automatic Speech Recognition) engine which performs the transcription.

Like Whisper, WhisperX is also packaged as a [Python project](https://pypi.org/project/whisperx/). All dependencies required to run the model are included in this Docker image.

When running the main steps are:

- Read media from STDIN
- Convert to 16kHz mono WAV for WhisperX
- Perform transcription using whisperx
- Stream transcript to STDOUT, or stream a subtitled MP4 to STDOUT

## WhisperX

`whisperx` represents an optimisation on top of the original work done by [OpenAI for Whisper](https://openai.com/index/whisper/) to produce a high quality, open source, speech to text AI model. `whisperx` extends this by dramatically decreasing the time it takes to process the audio.

WhisperX also supports translation which might be interesting in the future. English is supported for the moment, and other languages are available. See the `help.txt` file for more options to learn about the advanced options.

### Model Quality

The project builds using three versions of the OpenAI Whisper models. There are notable differences in the quality of the transcriptions for each version at the trade off in time.

For clear audio with well spoken English, the small model is usaully sufficient and represents the fastest model. This also applies in situations where the output transcription is not required to be completely accurate. However, if accuracy is required, or the audio conditions worsen, the large model is recommended. The medium model is clearly a balance of both objectives.

Sample video duration: 00:03:12
Transcription time for each model size:

* small: 29 seconds
* medium: 63 seconds
* large: 110 seconds

# Usage

The Docker image is designed to provide simple command line access to a high quality transcription model that is capabile of running locally. This project then unlocks potentail automation use cases for the automatic conversion of recorded meetings.

To help with this, two modes of operation are provided. One for simple transcription and the other for attaching those transcrptions to a video as subtitles.

In either mode, a `--model` argument is provided to the wrapper scripts (`transcribex`, `subtitlex`) to select which pre-built Docker image to use.

## Mode: Transcription

This mode is the simplest. Given any media file with spoken audio piped on STDIN, the Docker image will produce a transcription on STDOUT.

Both video and audio file formats are supported.

## Mode: Subtitles

This mode takes an input video piped on STDIN and generates a transcription. The mode is triggered by the `--output` flag. The output is a fragmented MP4 video written to STDOUT, containing the transcription as a subtitle track.

In addition, a `--bake` flag is included that will burn the subtitles into the video track (hardsubs).

# Run - Quick

The simplest way to run the project is to use the provided shell scripts which are included in this project.

```
curl -o transcribex https://raw.githubusercontent.com/GencoreOperative/whisperx-speech-to-text/main/transcribex
curl -o subtitlex   https://raw.githubusercontent.com/GencoreOperative/whisperx-speech-to-text/main/subtitlex
```

## transcribex

Transcribes any audio or video file to STDOUT. Defaults to the `small` model.

```
# Transcribe with the default (small) model
bash transcribex my-audio.mp3

# Choose a model size
bash transcribex --model small  my-audio.mp3
bash transcribex --model medium my-audio.mp3
bash transcribex --model large  my-audio.mp3

# Save the transcript to a file
bash transcribex --output transcript.txt my-audio.mp3

# Suppress FFMPEG/WhisperX progress output
bash transcribex --quiet my-audio.mp3
```

## subtitlex

Adds subtitles to a video, writing the result to a new MP4. Defaults to the `small` model.

```
# Add a subtitle track with the default (small) model
bash subtitlex my-video.mp4

# Choose a model size
bash subtitlex --model small  my-video.mp4
bash subtitlex --model medium my-video.mp4
bash subtitlex --model large  my-video.mp4

# Specify the output file name (default: subtitle-<input>)
bash subtitlex --output output.mp4 my-video.mp4

# Burn subtitles into the video stream (hardsubs)
bash subtitlex --bake --output output.mp4 my-video.mp4
```

# Run - Advanced

For direct Docker usage, the model size is selected by choosing the corresponding image tag.
The available tags are `small`, `medium`, and `large-v3`. The `latest` tag maps to `small`.

The Docker image supports the following command line arguments:
```
Media is read from STDIN. By default, the transcript is written to STDOUT.

If --output is provided, the input must be a video. An MP4 with a subtitle
track is written to STDOUT. Add --bake to burn the subtitles into the video
stream instead (hardsubs).

Usage: /entrypoint.sh [--output] [--bake] [--help]
  --output, -o: Trigger subtitle/video mode. Output MP4 is written to STDOUT.
  --bake,   -b: Used with --output. Burns subtitles into the video stream.
  --help,   -h: Display this help message.
```

The Docker image reads from STDIN and writes to STDOUT, so no volume mount is required.

```
# Transcribe — using each model size
docker run --rm -i gencore/whisperx-speech-to-text:small    < my-video-file.mp4
docker run --rm -i gencore/whisperx-speech-to-text:medium   < my-video-file.mp4
docker run --rm -i gencore/whisperx-speech-to-text:large-v3 < my-video-file.mp4

# Subtitles (soft track)
docker run --rm -i gencore/whisperx-speech-to-text:medium --output < my-video-file.mp4 > output.mp4

# Subtitles (baked in)
docker run --rm -i gencore/whisperx-speech-to-text:medium --output --bake < my-video-file.mp4 > output.mp4
```

## STDOUT/STDERR

The Docker image makes use of both `STDOUT` and `STDERR` outputs when running:
- `STDOUT`: Used for the transcript text (transcription mode) or the MP4 video bytes (subtitle mode)
- `STDERR`: Used for debugging output including FFMPEG and WhisperX output

For this reason, it is important to not use the docker run `-t` argument (Pseudo TTY) as this will combine both output streams into a single stream.

A `--quiet` argument is provided for the `transcribex` script to suppress STDERR output (FFMPEG and WhisperX progress), showing only the transcript on STDOUT.

# License

OpenAI has licensed their code and model under [MIT](https://github.com/openai/whisper/blob/main/LICENSE). Similarly, this project is licensed under the same MIT license.
