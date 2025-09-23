# Overview

This is a Docker project to enable command line access to the [WhisperX](https://github.com/m-bain/whisperX) speech to text engine that can be run on CPU only.

> Whisper is a neural network that has been trained to achieve human levels of robustness and accuracy on English speech recognition. Any-to-English translation is supported as well. WhisperX expands on this by improving the speed of transcription, as well as adding features for automatic language detection and word-level subtitling.

Initial testing for a 4 minute 20 seconds video:
- Whisper: 7 minutes 20 seconds
- WhisperX: 1 minute 15 seconds

# Project Details

The overall architecture for this project consists of packaging together all tools required to generate a transcription of a media file. We make use of [`ffmpeg`](https://ffmpeg.org/) for audio conversion and subtitle processing. Next, we use [`whisperx`](https://pypi.org/project/whisperx/) to provide the ASR (Automatic Speech Recognition) engine which performs the transcription.

Like Whisper, WhisperX is also packaged as a [Python project](https://pypi.org/project/whisperx/). All dependencies required to run the model are included in this Docker image.

When running the main steps are:

- (If required) convert media to MP3
- Perform transcription
- (If required) output to STDOUT
- (alternatively) include subtitles in video

## WhisperX

`whisperx` represents an optimisation on top of the original work done by [OpenAI for Whisper](https://openai.com/index/whisper/) to produce a high quality, open source, speech to text AI model. `whisperx` extends this by dramatically increasing the speed of the process.

WhisperX also supports translation which might be interesting in the future. English is supported for the moment, and other languages are available. See the `help.txt` file for more options to learn about the advanced options.

### WhisperX Version

The project is currently stuck at WhisperX 3.3.2. This is due to the current version of Torch that the project depends on. In version 3.3.2, the project depended on `torch>=2` which allowed us to make use of the rather compact `torch==2.2.2+cpu -f https://download.pytorch.org/whl/cpu/torch_stable.html` dependency. However, after torch version `2.3.1+cpu` there is no CPU release.

```
from versions: 1.13.0, 1.13.0+cpu, 1.13.1, 1.13.1+cpu, 2.0.0, 2.0.0+cpu, 2.0.1, 2.0.1+cpu, 2.1.0, 2.1.0+cpu, 2.1.1, 2.1.1+cpu, 2.1.2, 2.1.2+cpu, 2.2.0, 2.2.0+cpu, 2.2.1, 2.2.1+cpu, 2.2.2, 2.2.2+cpu, 2.3.0, 2.3.0+cpu, 2.3.1, 2.3.1+cpu, 2.4.0, 2.4.1, 2.5.0, 2.5.1, 2.6.0, 2.7.0, 2.7.1, 2.8.0
```

Testing 2.5.1, with the ChatGPT recommended command `pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu` we find the pip install downloads CUDA dependencies which add a lot of size to the project.

### Model Quality

The project builds using three versions of the OpenAI Whisper models. There are notable differences in the quality of the transcriptions for each version at the trade off in time.

[TODO - Add a table demonstrating the time differences]

# Usage

The Docker image is designed to provide simple command line access to a high quality transcription model that is capabile of running locally. This project then unlocks potentail automation use cases for the automatica conversion of recorded meetings.

To help with this, two modes of operation are provided. One for simple transcription and the other for attaching those transcrptions to a video as subtitles.

## Mode: Transcription

This mode is the simplest. Given a media file with spoken audio in it, the Docker image will produce a transcription to the STDOUT.

The Docker image will support video and audio file formats. The transcription will be stored in audio.txt. If a video file format is provided, then the subtitles will be included in the video.

## Mode: Subtitles

# Build

A makefile has been provided for all operations:

```
make build
```

This will build Docker images for the different sizes that targetted in this project.

# Run - Quick

The simplest way to run the project is to use the provided shell script `subtitlex` which is included in this project.

```
curl -o subtitlex https://raw.githubusercontent.com/GencoreOperative/whisperx-speech-to-text/main/subtitlex
bash subtitlex <my-video-file.mp4>
```

# Run - Advanced

The Docker image supports the following command line arguments:
```
  <input>: Required. A media file that must exist.
  --output, -o: Optional output file to store the output video. If no file name is provided, then one will be generated.
  --bake, -b: Optional. Bake-in selector flag that will cause the subtitles to be baked into the video.
  --help, -h: Display this help message."
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

# License

OpenAI has licensed their code and model under [MIT](https://github.com/openai/whisper/blob/main/LICENSE). Similarly, this project is licensed under the same MIT license.
