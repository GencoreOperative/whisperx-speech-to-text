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

.PHONY: build build-% clean publish check-hf-token

# The diarization model bake step needs a HuggingFace token for the gated
# pyannote models. Fail fast, before the long pip/model download steps,
# rather than discovering the problem part-way through the build.
check-hf-token:
	@if [ -z "$$HF_TOKEN" ]; then \
		echo "Error: HF_TOKEN is not set in your environment." >&2; \
		echo "Export it before building:  export HF_TOKEN=hf_..." >&2; \
		echo "The token needs accepted terms on BOTH gated model pages:" >&2; \
		echo "  https://hf.co/pyannote/speaker-diarization-3.1" >&2; \
		echo "  https://hf.co/pyannote/segmentation-3.0" >&2; \
		exit 1; \
	fi

build: check-hf-token $(addprefix build-,$(models))
	@echo "Tagging the '$(latest_model)' model as latest"
	docker tag $(project):$(whisper)-$(latest_model) $(project):latest

build-%: check-hf-token
	@echo "Building WhisperX Model: $*"
	DOCKER_BUILDKIT=1 docker build docker \
		--secret id=hf_token,env=HF_TOKEN \
		--build-arg MODEL_SIZE=$* \
		--build-arg WHISPER_VERSION=$(whisper) \
		$(foreach tag,$(call tags_for_model,$*),--tag $(tag))

clean:
	@echo "Cleaning up Docker images"
	docker rmi -f $(all_tags) $(project):latest

publish:
	@echo "Pushing to DockerHub"
	@sh utils/docker-login
	$(foreach tag,$(all_tags), docker push $(tag);)
	docker push $(project):latest