#!/usr/bin/env bash
# Upload local SO-101 demo datasets to your HuggingFace Hub account so a
# Colab/Modal/RunPod runner can pull them down for training.
#
# This script does NOT touch your local datasets or the running training.
# It only reads ~/.cache/huggingface/lerobot/local/* and pushes copies
# under <your-hf-username>/<dataset-name> on huggingface.co.
#
# Usage:
#   ./cloud/upload_datasets_to_hf.sh <hf-username> [pick|plug|pour|all]
#
# Prereqs:
#   1. pip install huggingface_hub  (already in your .conda env)
#   2. huggingface-cli login        (paste a *write* token from
#                                    https://huggingface.co/settings/tokens)
#
# Examples:
#   ./cloud/upload_datasets_to_hf.sh udbhav-k all
#   ./cloud/upload_datasets_to_hf.sh udbhav-k plug

set -euo pipefail

HF_USER="${1:-}"
WHICH="${2:-all}"

if [[ -z "${HF_USER}" ]]; then
  echo "ERROR: missing HuggingFace username."
  echo "Usage: $0 <hf-username> [pick|plug|pour|all]"
  exit 1
fi

REPO_ROOT="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
LEROBOT_BIN="${REPO_ROOT}/.conda/bin"
export PATH="${LEROBOT_BIN}:${PATH}"

# Map task -> local dataset path
declare -A LOCAL_PATH=(
  [pick]="${HOME}/.cache/huggingface/lerobot/local/so101_pick_v1"
  [plug]="${HOME}/.cache/huggingface/lerobot/local/so101_plug_v1"
  [pour]="${HOME}/.cache/huggingface/lerobot/local/so101_pour_v1"
)

declare -A REMOTE_NAME=(
  [pick]="so101_pick_v1"
  [plug]="so101_plug_v1"
  [pour]="so101_pour_v1"
)

upload_one() {
  local key="$1"
  local local_dir="${LOCAL_PATH[$key]}"
  local remote_repo="${HF_USER}/${REMOTE_NAME[$key]}"

  if [[ ! -d "${local_dir}" ]]; then
    echo "SKIP: ${key} — not found at ${local_dir}"
    return
  fi

  echo "================================================================"
  echo "Uploading ${key} dataset"
  echo "  local : ${local_dir}"
  echo "  remote: ${remote_repo}  (private)"
  echo "================================================================"

  python - <<PYEOF
from huggingface_hub import HfApi, create_repo
api = HfApi()
create_repo("${remote_repo}", repo_type="dataset", exist_ok=True, private=True)
api.upload_folder(
    folder_path="${local_dir}",
    repo_id="${remote_repo}",
    repo_type="dataset",
    commit_message="Upload SO-101 ${key} demos for cloud training",
)
print("Pushed ${remote_repo}")
PYEOF
}

case "${WHICH}" in
  pick|plug|pour)
    upload_one "${WHICH}"
    ;;
  all)
    for k in pick plug pour; do
      upload_one "${k}"
    done
    ;;
  *)
    echo "ERROR: second arg must be one of: pick | plug | pour | all"
    exit 1
    ;;
esac

echo
echo "Datasets are now on the Hub. In the Colab notebook set:"
echo "  HF_USERNAME = \"${HF_USER}\""
