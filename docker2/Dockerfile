# Standard light weight Python base image
FROM python:3.11-slim

# --------------------
# Install dependencies
# --------------------
# FFMPEG is required for audio conversion (pre-processing) and subtitle handling (post-processing)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------
# Install CPU-only torch + whisperx
# ---------------------------------
# Using ChatGPT, we have derived a list of dependencies that is considerably smaller than
# the previous efforts.
# 
# When whisperx up-versioned from 3.3.2 to 3.3.3, the torch version changed from torch>=2
# to torch>=2.5.1. Around the same time torch changed the way they packaged their cpu-only 
# dependency and it appears the last version of the cpu variant of torch (much smaller
# dependency size) was 2.3.1+cpu.
#
# We have tested and found that whisperx does not actually use any 2.5.1 features, so we
# are safe to force the version to be lower.
#
# As such, we will use most of the dependencies derived from the whisperx project
# with the torch version fixed at 2.3.1+cpu. We needed to remove the ctranslate2 dependency
# so that pip could derive one that was compatible.
#
# Lastly, we will install whisperx, but skip its dependencies to achieve the desired result.

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

# ----------------
# Fixing a warning
# ----------------
# Lightning automatically upgraded your loaded checkpoint from v1.5.4 to v2.5.5
# We need to use the --map-to-cpu flag to ensure this works when we are in CPU only mode.

RUN python -m pytorch_lightning.utilities.upgrade_checkpoint \
        --map-to-cpu \
        /usr/local/lib/python3.11/site-packages/whisperx/assets/pytorch_model.bin \
    && echo "Checkpoint upgraded to Lightning v2.5.5 (CPU-safe)"

# -------------------
# Pre-cache the model
# -------------------
# By running whisperx with the desired model size, we will pre-cache the model size inside
# the docker image. This means the user will have everything they need to use this image
# offline.
# Also - be sure to no include the --no-align flag, so that the correspodning alignment model
# is also downloaded.
WORKDIR /tmp
COPY jfk.wav /tmp/
ARG MODEL_SIZE
RUN echo "${MODEL_SIZE}" > /etc/model_size && \
    whisperx \
    --model ${MODEL_SIZE} \
    --compute_type int8 \
    jfk.wav

# ----------------------------------
# Entrypoint for argument processing
# ----------------------------------
ADD entrypoint.sh /
RUN mkdir /audio
WORKDIR /audio
ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]