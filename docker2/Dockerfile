# Standard light weight Python base image
FROM python:3.11-slim

# Install dependencies
# FFMPEG is required for audio conversion (pre-processing) and subtitle handling (post-processing)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-only torch + whisperx
# ChatGPT derived list of dependencies, considerably smaller than previous efforts.
# Lessons Learned: The torch version changed between whisperx 3.3.2 and 3.3.3 from torch>=2 to torch>=2.5.1
# Around the same time torch changed the way they packaged their cpu-only dependency.
# We use the -f flag to ensure that the wheel we get for torch is the CPU only version.

## Key Idea
# It appears that the whisperx dependency of 2.5.1 is arbitrary and should not be enforced in
# in the project. Instead, we are using the following to force whisperx to use 2.3.1+cpu to help
# keep the Docker image size down.
# We need to remove the ctranslate2 dependency, so that pip can resolve one that is compatible.
ARG WHISPER_VERSION
RUN pip install --no-cache-dir \
    "faster-whisper>=1.1.1" \
    "nltk>=3.9.1" \
    "numpy>=2.0.2" \
    "onnxruntime>=1.19" \
    "pandas>=2.2.3" \
    "pyannote-audio>=3.3.2" \
    "torchaudio>=2.3.1" \
    "transformers>=4.48.0" \
    torch==2.3.1+cpu -f https://download.pytorch.org/whl/cpu/torch_stable.html \
    backports.tarfile \
    matplotlib

RUN pip install --no-cache-dir \
    whisperx==${WHISPER_VERSION} --no-deps

# Pre-cache the model that the Docker image will use.
# The model size will be part of the image tag, and allow the user to control
# quality versus size of image download.
WORKDIR /tmp
COPY counting.mp3 /tmp/counting.mp3
ARG MODEL_SIZE
RUN echo "${MODEL_SIZE}" > /etc/model_size && \
    whisperx \
    --model ${MODEL_SIZE} \
    --compute_type int8 \
    --no_align \
    counting.mp3

# Fixing the warning: Lightning automatically upgraded your loaded checkpoint from v1.5.4 to v2.5.5
# We need to use the --map-to-cpu flag to ensure this works when we are in CPU only mode.
RUN python -m pytorch_lightning.utilities.upgrade_checkpoint \
        --map-to-cpu \
        /usr/local/lib/python3.11/site-packages/whisperx/assets/pytorch_model.bin \
    && echo "Checkpoint upgraded to Lightning v2.5.5 (CPU-safe)"

# Entrypoint for argument processing.
ADD entrypoint.sh /
RUN mkdir /audio
WORKDIR /audio
ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]