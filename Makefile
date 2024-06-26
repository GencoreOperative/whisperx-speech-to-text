project=gencore/whisperx-speech-to-text
git= $(shell git rev-parse --short HEAD)
pip-version = 3.1.3

all: build

.PHONY: build clean

build:
	@echo "Building Base Image"
	docker build docker \
		--tag $(project):$(pip-version) \
		--tag $(project):latest

clean:
	@echo "Cleaning up Docker images"
	docker rmi -f $(project):$(pip-version)
	docker rmi -f $(project):latest

publish:
	@echo "Pushing to DockerHub"
	@sh utils/docker-login
	docker push $(project):$(pip-version)
	docker push $(project):latest