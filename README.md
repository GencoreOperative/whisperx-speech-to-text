# Overview

This is a Docker project to enable command line access to the [WhisperX](https://github.com/m-bain/whisperX)
library. This library is an optimisation on top of the original work done by [OpenAI for Whisper](https://openai.com/index/whisper/).

> Whisper is a neural network that has been trained to achieve human levels of robustness and accuracy on English speech recognition. Any-to-English translation is supported as well. WhisperX expands on this by improving the speed of transcription, as well as adding features for automatic language detection and word-level subtitling.

Initial testing for a 4 minute 20 seconds video:
- Whisper: 7 minutes 20 seconds
- WhisperX: 1 minute 15 seconds

## Project Details

Like Whisper, WhisperX is also packaged as a [Python project](https://pypi.org/project/whisperx/). All dependencies required to run the model are included in this Docker image.

## Transcription

The primary use case I wanted to solve for this project was to take a recording of a meeting and generate the transcription of the spoken audio. This is then stored as subtitles on the video. Once we have the subtitles of a video, we can use that for multiple downstream AI processing tasks like creating meeting minutes.

WhisperX also supports translation which might be interesting in the future. English is supported for the moment, and other languages are available. See the `help.txt` file for more options to learn about the advanced options.

The Docker image will support video and audio file formats. The transcription will be stored in audio.txt. If a video file format is provided, then the subtitles will be included in the video.

# Build

A makefile has been provided for all operations:

```
make build
```

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
# License

OpenAI has licensed their code and model under [MIT](https://github.com/openai/whisper/blob/main/LICENSE). Similarly, this project is licensed under the same MIT license.
