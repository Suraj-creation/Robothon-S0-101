#!/usr/bin/env bash
# Task 3 SMOKE TEST — record 2 dummy episodes to verify the pouring workspace,
# cameras, and bottle/cup placement before committing to the 35-demo session.
#
# What to verify during the 2 episodes:
#   - Overhead cam shows BOTH the BOTTLE_ZONE and the CUP_ZONE
#   - Wrist cam can see the bottle neck during tilt (so it sees the pour stream)
#   - Robot can reach above the cup with the bottle in hand at full upright pose
#   - When tilted ~90°, the bottle mouth is centered over the cup
#   - The bottle does NOT collide with the wrist cam mount when tilted
#
# SAFETY for the smoke test:
#   USE A DRY MEDIUM — uncooked rice, lentils, or small beads. NOT WATER.
#   Cover the laptop and robot base with a towel anyway.
#
# Run: ./scripts/task3_smoketest.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task3_env.sh"

# Auto-clean any previous smoke-test dataset so the run never fails with
# FileExistsError. Smoke data is throwaway by definition.
SMOKE_DIR="${HOME}/.cache/huggingface/lerobot/local/so101_pour_smoke"
if [[ -d "${SMOKE_DIR}" ]]; then
  echo "==> Removing stale smoke dataset at ${SMOKE_DIR}"
  rm -rf "${SMOKE_DIR}"
fi

echo "==> SMOKE TEST: 2 episodes, 25s each"
echo "    Overhead cam = index ${OVERHEAD_INDEX}"
echo "    Wrist cam    = index ${WRIST_INDEX}    <-- MUST see the pour stream"
echo "    Follower     = ${FOLLOWER_PORT}"
echo "    Leader       = ${LEADER_PORT}"
echo ""
echo "    Use DRY RICE or DRY LENTILS in the bottle for this smoke test."
echo "    Do one full pour cycle (grasp -> over cup -> tilt -> return -> place)"
echo "    so you can confirm wrist-cam coverage and that the bottle clears the"
echo "    cam mount when tilted."
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
    --dataset.repo_id="local/so101_pour_smoke" \
    --dataset.root="${HOME}/.cache/huggingface/lerobot/local/so101_pour_smoke" \
    --dataset.num_episodes=2 \
    --dataset.episode_time_s=25 \
    --dataset.reset_time_s=10 \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="task 3 smoke test"
