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
ARG WHISPER_VERSION
RUN pip install --no-cache-dir \
    "numpy<2" \
    torch==2.2.2+cpu -f https://download.pytorch.org/whl/cpu/torch_stable.html \
    whisperx==${WHISPER_VERSION} \
    backports.tarfile \
    matplotlib

# Pre-cache the model that the Docker image will use.
# The model size will be part of the image tag, and allow the user to control
# quality versus size of image download.
WORKDIR /tmp
COPY counting.mp3 /tmp/counting.mp3
ARG MODEL_SIZE
RUN echo "${MODEL_SIZE}" > /etc/model_size && \
    whisperx --model ${MODEL_SIZE} --compute_type int8 counting.mp3 || true

# Entrypoint for argument processing.
ADD entrypoint.sh /
RUN mkdir /audio
WORKDIR /audio
ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]