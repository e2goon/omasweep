#!/usr/bin/env bash

target huggingface "AI" review 0 "Hugging Face model cache" "models download again when used" "match:huggingface"
paths huggingface "${HF_HOME:-$CACHE/huggingface}/hub" "${HF_HOME:-$CACHE/huggingface}/xet"
target ml-models "AI" review 0 "PyTorch and Whisper models" "models download again when used"
paths ml-models "$CACHE/torch" "$CACHE/whisper"
target lmstudio "AI" review 0 "LM Studio models" "models you downloaded in LM Studio" "lm-studio match:LM%20Studio"
paths lmstudio "$HOME/.lmstudio/models" "$CACHE/lm-studio/models"
target opencode "AI" safe 0 "OpenCode cache" "provider packages and tools, downloaded again on start, sessions stay" "opencode"
paths opencode "$CACHE/opencode"
