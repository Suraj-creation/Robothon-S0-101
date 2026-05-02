#!/usr/bin/env bash
# Task 2 SMOKE TEST — record 2 dummy episodes to verify the workspace + cameras
# are still aligned after adding the socket fixture, before committing 100 minutes
# to the real 90-demo session.
#
# What to test during the 2 episodes:
#   - Wrist cam can see the connector + socket during insertion
#   - Overhead cam still shows the whole worktop
#   - Robot can reach the SOCKET_ZONE without joint-limit warnings
#
# Run: ./scripts/task2_smoketest.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task2_env.sh"

# Auto-clean any previous smoke-test dataset so the run never fails with
# FileExistsError. Smoke data is throwaway by definition.
SMOKE_DIR="${HOME}/.cache/huggingface/lerobot/local/so101_plug_smoke"
if [[ -d "${SMOKE_DIR}" ]]; then
  echo "==> Removing stale smoke dataset at ${SMOKE_DIR}"
  rm -rf "${SMOKE_DIR}"
fi

echo "==> SMOKE TEST: 2 episodes, 20s each"
echo "    Overhead cam = index ${OVERHEAD_INDEX}"
echo "    Wrist cam    = index ${WRIST_INDEX}"
echo "    Follower     = ${FOLLOWER_PORT}"
echo "    Leader       = ${LEADER_PORT}"
echo ""
echo "    Do one full plug attempt (grasp -> approach -> insert) so you can"
echo "    confirm the wrist cam sees the connector tip during insertion."
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
    --dataset.repo_id="local/so101_plug_smoke" \
    --dataset.root="${HOME}/.cache/huggingface/lerobot/local/so101_plug_smoke" \
    --dataset.num_episodes=2 \
    --dataset.episode_time_s=20 \
    --dataset.reset_time_s=8 \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="task 2 smoke test"
