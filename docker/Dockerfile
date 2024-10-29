FROM continuumio/anaconda3@sha256:2936bbcc87821528d9741fa09351c17fb5ff78b1a33e024c09f05e8c59826521

# Whisper depends on FFMPEG being present.
RUN apt-get update \
    && apt-get install -y ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Installing dependencies required for WhisperX
# These are broken down into steps to ease connection 
# timeouts on the longer downloads.

# Normally, we might try and use Torch in CPU mode. However
# this approach will not work because of the following error
# OSError: libtorch_cuda.so: cannot open shared object file: No such file or directory
#RUN pip install torch==2.2.2+cpu -f https://download.pytorch.org/whl/cpu/torch_stable.html

# Install the largest dependencies specifically so that we make the build process easier
# to manage on slower, poorer, connections.
RUN pip install --no-deps nvidia_cudnn_cu12==9.1.0.70
RUN pip install --no-deps nvidia_cublas_cu12==12.4.5.8
RUN pip install --no-deps triton==3.1.0
RUN pip install --no-deps nvidia_cusparse_cu12==12.3.1.170
RUN pip install --no-deps nvidia_nccl_cu12==2.21.5
RUN pip install --no-deps nvidia_cusolver_cu12==11.6.1.9
RUN pip install --no-deps nvidia_cufft_cu12==11.2.1.3
RUN pip install --no-deps torch==2.5.0

# Then the project
RUN pip install whisperx==3.1.3
RUN pip install backports.tarfile

# Exercise the program as part of build to pre-cache dependencies
WORKDIR /tmp
COPY counting.mp3 /tmp/counting.mp3

RUN whisperx --compute_type int8 counting.mp3

ADD entrypoint.sh /

RUN mkdir /audio
WORKDIR /audio

ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]