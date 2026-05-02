#!/usr/bin/env bash
# Inspect the most recent state of a LeRobot dataset on disk.
# Use after a recording session (or after a crash) to see how many
# episodes were saved before the script exited.
#
# Run: ./scripts/check_dataset.sh                 # shows so101_pick_v1
#      ./scripts/check_dataset.sh <repo_path>     # custom path

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task1_env.sh"

REPO="${1:-${TASK1_REPO}}"
DIR="${HOME}/.cache/huggingface/lerobot/${REPO}"

if [[ ! -d "${DIR}" ]]; then
  echo "No dataset at ${DIR}"
  exit 1
fi

echo "==> Dataset: ${REPO}"
echo "    Path:    ${DIR}"
echo ""

if [[ -f "${DIR}/meta/info.json" ]]; then
  ${LEROBOT}/python -c "
import json
m = json.load(open('${DIR}/meta/info.json'))
print(f\"  episodes: {m['total_episodes']}\")
print(f\"  frames:   {m['total_frames']}\")
print(f\"  fps:      {m['fps']}\")
print(f\"  cameras:  {[k for k in m['features'] if k.startswith('observation.images')]}\")
print(f\"  state shape: {m['features']['observation.state']['shape']}\")
"
fi

echo ""
echo "    Disk usage:"
du -sh "${DIR}" "${DIR}/data" "${DIR}/videos" "${DIR}/meta" 2>/dev/null | sed 's/^/      /'

echo ""
echo "    Video files:"
find "${DIR}/videos" -name "*.mp4" -exec ls -lh {} \; 2>/dev/null | awk '{printf "      %-8s %s\n", $5, $9}'
