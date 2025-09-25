project=gencore/whisperx-speech-to-text

git = $(shell git rev-parse --short HEAD)

# WhisperX versions from: https://pypi.org/project/whisperx/#history
whisper = 3.4.2

# Model sizes are based on the OpenAI released models: https://huggingface.co/openai/whisper-large-v3#model-details
models = small medium large-v3
latest_model = small

# --- Tagging Scheme ---
# This is the single source of truth for the tagging scheme.
# To add/remove/change tags, you only need to modify the variables below.

# Tags for a specific model
define tags_for_model
$(project):$(whisper)-$(1)-$(git)
$(project):$(whisper)-$(1)
$(project):$(1)
endef

# --- Generated tag lists ---
all_tags = $(foreach model,$(models),$(call tags_for_model,$(model)))


# --- Targets ---
all: build

.PHONY: build clean publish

build:
	@echo "Building the WhisperX images"
	$(foreach model,$(models), \
		echo "Building WhisperX Model: $(model)"; \
		DOCKER_BUILDKIT=1 docker build docker2 \
			--build-arg MODEL_SIZE=$(model) \
			--build-arg WHISPER_VERSION=$(whisper) \
			$(foreach tag,$(call tags_for_model,$(model)),--tag $(tag)) ; \
	)
	@echo "Tagging the '$(latest_model)' model as latest"
	docker tag $(project):$(whisper)-$(latest_model) $(project):latest

clean:
	@echo "Cleaning up Docker images"
	docker rmi -f $(all_tags) $(project):latest

publish:
	@echo "Pushing to DockerHub"
	@sh utils/docker-login
	$(foreach tag,$(all_tags), docker push $(tag);)
	docker push $(project):latest