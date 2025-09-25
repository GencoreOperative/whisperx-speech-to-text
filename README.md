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

- (If required) convert media to WAV
- Perform transcription using whisperx
- (If required) output to STDOUT
- (alternatively) include subtitles in video

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

In either mode, a `--model` argument is provided to allow the user to control the quality of the model selected.

## Mode: Transcription

This mode is the simplest. Given a media file with spoken audio in it, the Docker image will produce a transcription to the STDOUT.

The Docker image will support video and audio file formats. The transcription will be sent to STDOUT unless a `--output` file argument is provided.

## Mode: Subtitles

This mode will take an input video file and then generate the transcription. The mode is triggered when the `--output` file is defined. In this mode the output video will contain a subtitle track that includes the transcription.

In addition, a `--bake` flag is included that will overlay the subtitles into the vido track.

# Run - Quick

The simplest way to run the project is to use the provided shell script `transcribex` which is included in this project.

```
curl -o transcribex https://raw.githubusercontent.com/GencoreOperative/whisperx-speech-to-text/main/transcribex
bash transcribex <my-video-file.mp4>
```

# Run - Advanced

The Docker image supports the following command line arguments:
```
By default, the command will perform audio transcript of the provided media. 
Media that is not in MP3 format will be converted first. The transcription 
will be output to STDOUT.

If the --output argument is provided, and the input is a video, then an MP4 
video will be created that contains the transcription as a subtitle track. 
Lastly, if the --bake option is included, then the subtitles will be drawn 
on top of the video stream (hardsubs).

Usage: /entrypoint.sh <input> [--output <output>] [--bake] [--help]
  <input>: Required. A media file that must exist.
  --output, -o: Optional. When provided with a video, an MP4 will be created 
                that has subtitles from the transcript.
  --bake,   -b: Optional. Used with --output. When generating a video, rather 
                than a separate subtitle track, the subtitles will be drawn 
                over the video.
  --help,   -h: Display this help message.
```

The Docker image expects a folder called `/audio` to be mounted containing the media file to be transcribed.

```
docker run -v $PWD:/audio --rm -i gencore/whisperx-speech-to-text <my-video-file.mp4>
```

## STDOUT/STDERR

The Docker image makes use of both `STDOUT` and `STDERR` outputs when running:
- `STDOUT`: Used for the transcription output
- `STDERR`: Used for debugging output including FFMPEG and WhisperX output

For this reason, it is important to not use the docker run `-t` argument (Pseudo TTY) as this will combine both output streams into a single stream.

A `--quiet` argument is provided for both scripts to only show the STDERR output.

# License

OpenAI has licensed their code and model under [MIT](https://github.com/openai/whisper/blob/main/LICENSE). Similarly, this project is licensed under the same MIT license.
