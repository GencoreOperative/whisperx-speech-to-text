project=gencore/whisperx-speech-to-text
git = $(shell git rev-parse --short HEAD)
pip-version = 3.3.2
models = small medium

all: build

.PHONY: build clean

build:
	@echo "Building the WhisperX images"
	for model in $(models); do \
		echo "Building WhisperX Model: $$model"; \
		docker build docker \
			--build-arg MODEL_SIZE=$$model \
			--tag $(project):$(pip-version)-$$model; \
	done
	@echo "Tagging the 'small' model as latest"
	docker tag $(project):$(pip-version)-small $(project):latest

clean:
	@echo "Cleaning up Docker images"
	docker rmi -f $(project):$(pip-version)
	docker rmi -f $(project):latest

publish:
	@echo "Pushing to DockerHub"
	@sh utils/docker-login
	docker push $(project):$(pip-version)
	docker push $(project):latest