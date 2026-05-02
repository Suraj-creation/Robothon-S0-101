#!/usr/bin/env bash
# Copy Task 2 pretrained checkpoint from local training into models/act_plug_v1/
# Use when Hugging Face has no act_plug_v1 repo yet (404 on sync).
#
# Requires: outputs/act_plug_v1/checkpoints/last/pretrained_model after ./scripts/task2_train.sh
#
# Run: ./scripts/stage_plug_model_from_outputs.sh

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
SRC="${REPO_ROOT}/outputs/act_plug_v1/checkpoints/last/pretrained_model"
DST="${REPO_ROOT}/models/act_plug_v1"

if [[ ! -d "${SRC}" ]]; then
  echo "ERROR: No local plug checkpoint at:"
  echo "  ${SRC}"
  echo ""
  echo "Train Task 2 first:  ./scripts/task2_train.sh"
  echo "Or upload a pretrained_model bundle to Hugging Face and sync with:"
  echo "  HF_TOKEN=... .conda/bin/python scripts/sync_models_from_hf.py --plug-only --repo-id YOUR_ORG/YOUR_REPO_NAME"
  exit 1
fi

rm -rf "${DST}"
mkdir -p "${DST}"
cp -R "${SRC}/." "${DST}/"
echo "OK — staged plug policy for inference:"
echo "  ${DST}"
echo ""
echo "Run Task 2:"
echo "  ./scripts/task2_autonomous_github_models.sh --yes"
