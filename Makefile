project=gencore/whisperx-speech-to-text
git = $(shell git rev-parse --short HEAD)
whisper = 3.4.2
models = small medium large-v3

all: build

.PHONY: build clean

build:
	@echo "Building the WhisperX images"
	for model in $(models); do \
		echo "Building WhisperX Model: $$model"; \
		DOCKER_BUILDKIT=1 docker build docker2 \
			--build-arg MODEL_SIZE=$$model \
			--build-arg WHISPER_VERSION=$(whisper) \
			--tag $(project):$(whisper)-$$model; \
	done
	@echo "Tagging the 'small' model as latest"
	docker tag $(project):$(whisper)-small $(project):latest

clean:
	@echo "Cleaning up Docker images"
	docker rmi -f $(project):$(whisper)
	docker rmi -f $(project):latest

publish:
	@echo "Pushing to DockerHub"
	@sh utils/docker-login
	docker push $(project):$(whisper)
	docker push $(project):latest