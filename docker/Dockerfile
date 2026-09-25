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
    "transformers>=4.48.0,<5.0" \
    torch==2.3.1+cpu \
    torchaudio==2.3.1+cpu \
    -f https://download.pytorch.org/whl/cpu/torch_stable.html \
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
# Pre-cache the models
# -------------------
# Rather than running whisperx end-to-end on a sample file, we trigger the
# downloads directly (same pattern as the pyannote step below). The entrypoint
# pins --language en, so only the English alignment model is needed.
# The models land in the standard caches (/root/.cache/huggingface/hub and
# /root/.cache/torch/hub/checkpoints), which the entrypoint consumes offline.
ARG MODEL_SIZE
RUN echo "${MODEL_SIZE}" > /etc/model_size && \
    python -c "from faster_whisper import WhisperModel; \
    WhisperModel('${MODEL_SIZE}', device='cpu', compute_type='int8')" && \
    python -c "import whisperx; \
    whisperx.load_align_model('en', 'cpu')"

# ----------------------------------
# Bake in the pyannote diarization models
# ----------------------------------
# Downloads the gated pyannote pipeline at build time into the image, so the
# finished image is fully offline for diarization (DIARIZE-PLAN.md Step 2).
# Requires HF_TOKEN in the builder's environment, with terms accepted on BOTH
# gated model pages:
#   https://hf.co/pyannote/speaker-diarization-3.1
#   https://hf.co/pyannote/segmentation-3.0
# The token is supplied via a BuildKit secret mount: it exists only in
# /run/secrets during this step and never enters image layers, build cache,
# or docker history. A build without HF_TOKEN fails here by design.
# The models land in pyannote's native cache (PYANNOTE_CACHE default),
# which the entrypoint consumes offline via HF_HUB_OFFLINE=1.
# NB: pyannote's from_pretrained catches the download failure and only prints
# a warning (exit code 0), so a missing or invalid token would otherwise slip
# through silently. The find below asserts the models actually landed.
# Since pyannote 3.4.0 the models go to /root/.cache/torch/pyannote (the
# huggingface/hub location was used by pyannote <= 3.3.x); accept either.
RUN --mount=type=secret,id=hf_token \
    python -c "from pyannote.audio import Pipeline; \
    Pipeline.from_pretrained('pyannote/speaker-diarization-3.1', \
    use_auth_token=open('/run/secrets/hf_token').read().strip())" && \
    test -n "$(find /root/.cache/torch/pyannote /root/.cache/huggingface/hub \
        -maxdepth 1 -type d -name 'models--pyannote--*' 2>/dev/null)"

COPY PYANNOTE-NOTICE /etc/PYANNOTE-NOTICE

# ----------------------------------
# Entrypoint for argument processing
# ----------------------------------
ADD entrypoint.sh /
WORKDIR /tmp
ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]