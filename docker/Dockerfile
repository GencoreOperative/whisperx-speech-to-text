FROM continuumio/anaconda3@sha256:2936bbcc87821528d9741fa09351c17fb5ff78b1a33e024c09f05e8c59826521

# Whisper depends on FFMPEG being present.
RUN apt-get update \
    && apt-get install -y ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Installing dependencies required for WhisperX
# These are broken down into steps to ease connection 
# timeouts on the longer downloads.

RUN pip install typing-extensions triton==2.2.0
RUN pip install nvidia-cudnn-cu12==8.9.2.26 \
            nvidia-curand-cu12==10.3.2.106 \
            nvidia-nvtx-cu12==12.1.105 \
            nvidia-cublas-cu12==12.1.3.1 \
            nvidia-cufft-cu12==11.0.2.54 \
            nvidia-cuda-runtime-cu12==12.1.105 \
            nvidia-cusolver-cu12==11.4.5.107 \
            nvidia-cuda-nvrtc-cu12==12.1.105 \
            nvidia-cusparse-cu12==12.1.0.106

# Normally, we might try and use Torch in CPU mode. However
# this approach will not work because of the following error
# OSError: libtorch_cuda.so: cannot open shared object file: No such file or directory
#RUN pip install torch==2.2.2+cpu -f https://download.pytorch.org/whl/cpu/torch_stable.html

# Therefore, we will use the GPU enabled Torch even though we 
# will be running in CPU mode.
RUN pip install torch==2.2.2

# Then the project
RUN pip install whisperx==3.1.3

# Exercise the program as part of build to pre-cache dependencies
WORKDIR /tmp
COPY counting.mp3 /tmp/counting.mp3

RUN whisperx --compute_type int8 counting.mp3

ADD entrypoint.sh /

RUN mkdir /audio
WORKDIR /audio

ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]