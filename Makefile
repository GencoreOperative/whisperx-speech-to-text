project=gencore/whisperx-speech-to-text

git = $(shell git rev-parse --short HEAD)

# WhisperX versions from: https://pypi.org/project/whisperx/#history
whisper = 3.4.2

# Model sizes are based on the OpenAI released models: https://huggingface.co/openai/whisper-large-v3#model-details
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
			--tag $(project):$(whisper)-$$model-$(git) \
			--tag $(project):$(whisper)-$$model \
			--tag $(project):$$model; \
	done
	@echo "Tagging the 'small' model as latest"
	docker tag $(project):$(whisper)-small-$(git) $(project):latest

clean:
	@echo "Cleaning up Docker images"
	for model in $(models); do \
		docker rmi -f $(project):$(whisper)-$$model-$(git); \
		docker rmi -f $(project):$(whisper)-$$model; \
		docker rmi -f $(project):$$model; \
	done
	docker rmi -f $(project):latest

publish:
	@echo "Pushing to DockerHub"
	@sh utils/docker-login
	for model in $(models); do \
		docker push $(project):$(whisper)-$$model; \
		docker push $(project):$$model; \
	done
	docker push $(project):latest