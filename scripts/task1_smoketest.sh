#!/usr/bin/env bash
# Task 1 SMOKE TEST — record 2 dummy episodes to verify the full pipeline:
# - both cameras open and stream to rerun
# - follower receives leader commands
# - dataset writes to ~/.cache/huggingface/lerobot/local/so101_smoke
#
# DO NOT USE THIS DATA for training. It's just a plumbing check.
#
# Run: ./scripts/task1_smoketest.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task1_env.sh"

# Auto-clean any previous smoke-test dataset so the run never fails with
# FileExistsError. Smoke data is throwaway by definition.
SMOKE_DIR="${HOME}/.cache/huggingface/lerobot/local/so101_smoke"
if [[ -d "${SMOKE_DIR}" ]]; then
  echo "==> Removing stale smoke dataset at ${SMOKE_DIR}"
  rm -rf "${SMOKE_DIR}"
fi

echo "==> SMOKE TEST: 2 episodes, ${TASK1_EPISODE_TIME_S}s each"
echo "    Overhead cam = index ${OVERHEAD_INDEX}"
echo "    Wrist cam    = index ${WRIST_INDEX}"
echo "    Follower     = ${FOLLOWER_PORT}"
echo "    Leader       = ${LEADER_PORT}"
echo ""
echo "    A rerun window will open showing both camera streams + 6 joint values."
echo "    Use the leader to do anything (just wave it around) — this is plumbing only."
echo "    Press Ctrl+C if it hangs at startup."
echo ""

cd "${REPO_ROOT}"
exec "${LEROBOT}/lerobot-record" \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${ROBOT_ID}" \
    --robot.max_relative_target=${MAX_RELATIVE_TARGET} \
    --robot.cameras="${CAMERAS_SPEC}" \
    --teleop.type=so101_leader \
    --teleop.port="${LEADER_PORT}" \
    --teleop.id="${TELEOP_ID}" \
    --display_data=true \
    --dataset.repo_id="local/so101_smoke" \
    --dataset.root="${HOME}/.cache/huggingface/lerobot/local/so101_smoke" \
    --dataset.num_episodes=2 \
    --dataset.episode_time_s=15 \
    --dataset.reset_time_s=5 \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="smoke test"
