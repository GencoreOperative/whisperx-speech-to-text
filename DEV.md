### WhisperX and Torch Versions

This project makes use of the PyTorch library for AI processing. We are operating in CPU only mode to ensure that this Docker image has no dependencies on hardware to operate. The other major advantage of this us that the size of the PyTorch dependency and sub-dependencies are considerably smaller than if the entire CUDA framework was included.

The PyTorch project appears to have stopped shipping CPU specific releases from version `2.3.0+cpu`.

```
from versions: 1.13.0, 1.13.0+cpu, 1.13.1, 1.13.1+cpu, 2.0.0, 2.0.0+cpu, 2.0.1, 2.0.1+cpu, 2.1.0, 2.1.0+cpu, 2.1.1, 2.1.1+cpu, 2.1.2, 2.1.2+cpu, 2.2.0, 2.2.0+cpu, 2.2.1, 2.2.1+cpu, 2.2.2, 2.2.2+cpu, 2.3.0, 2.3.0+cpu, 2.3.1, 2.3.1+cpu, 2.4.0, 2.4.1, 2.5.0, 2.5.1, 2.6.0, 2.7.0, 2.7.1, 2.8.0
```

The `whisperx` project declares that it depends on torch `2.5.1`. The best option I have concluded for this so far is to downgrade the version of torch that `whisperx` uses and hope that the project maintainers do not introduce changes that depend on `2.5.1` or greater features. This approach appears to work successfully in all testing I have performed so far.

# Building

A `Makefile` has been provided that covers the building of the project.

```
make build
```

The project supports three model sizes to provide users with a range of choice when it comes to STT (Speech to Text). The built Docker image sizes vary based on the model size.

```
gencore/whisperx-speech-to-text    3.4.2-large-v3    f71053d64850   15 minutes ago   8.66GB
gencore/whisperx-speech-to-text    3.4.2-medium      e9ad38c83d4b   15 minutes ago   5.54GB
gencore/whisperx-speech-to-text    3.4.2-small       399d286e00f1   15 minutes ago   3.45GB
```
