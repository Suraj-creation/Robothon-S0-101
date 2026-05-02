#!/usr/bin/env bash
# Task 1 — RECORD 50 PICK & PLACE DEMOS via teleoperation.
#
# This is the real demo collection. Plan ~75 minutes including resets.
# You'll be at the leader arm doing pick & place 50 times.
#
# DEMO DISCIPLINE (matters more than the model):
#   1. Move SLOWLY and SMOOTHLY with the leader. Robot's autonomous speed
#      will roughly match your demo speed.
#   2. Same trajectory shape every time. Only the cube's start position
#      should vary.
#   3. Vary cube position deliberately. Use a 3x3 = 9-position grid in
#      PICK_ZONE; do 5-6 demos at each position.
#   4. Reset cleanly between episodes — return arm to HOME, place cube at
#      next grid position, then continue.
#   5. If you fumble an episode, mark it bad in the rerun UI (drop it).
#      Bad demos poison the model.
#   6. Lighting must not change during the session. Don't record half
#      morning, half evening.
#
# LeRobot keybinds during recording (look for them in the rerun window):
#   - Right Arrow: end current episode early, save it
#   - Left  Arrow: re-record current episode (drops the previous attempt)
#   - Esc:         end the entire session early
#
# Run: ./scripts/task1_record.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task1_env.sh"

# Pass --resume to continue an interrupted recording session.
EXTRA_FLAGS=""
if [[ "$1" == "--resume" ]]; then
  EXTRA_FLAGS="--resume=true"
  echo "==> RESUME MODE: continuing existing dataset until ${TASK1_NUM_EPISODES} episodes total"
  echo ""
fi

cat <<INFO
==========================================================
  TASK 1 DEMO RECORDING — Pick & Place
==========================================================
  Episodes:        ${TASK1_NUM_EPISODES}
  Episode length:  ${TASK1_EPISODE_TIME_S}s
  Reset time:      ${TASK1_RESET_TIME_S}s
  Camera FPS:      ${CAM_FPS}
  Overhead index:  ${OVERHEAD_INDEX}
  Wrist index:     ${WRIST_INDEX}
  Dataset:         ${TASK1_REPO}
                   (saved to ~/.cache/huggingface/lerobot/${TASK1_REPO})

  Total expected wall-clock: ~$(( (TASK1_NUM_EPISODES * (TASK1_EPISODE_TIME_S + TASK1_RESET_TIME_S)) / 60 )) minutes
  (plus your reset/reposition time between episodes)

  Pre-flight checklist:
    [ ] Both cameras aimed (overhead at worktop, wrist on follower)
    [ ] Workspace mat + zones taped
    [ ] Cube in PICK_ZONE, target marked in DROP_ZONE
    [ ] Leader arm powered (5V/6A), follower arm powered (12V/8A)
    [ ] Constant lighting; close blinds if daylight changes
    [ ] No people moving in the overhead frame
    [ ] Laptop plugged in
==========================================================
INFO

read -r -p "Start recording ${TASK1_NUM_EPISODES} episodes? [y/N] " ans
[[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

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
    --dataset.repo_id="${TASK1_REPO}" \
    --dataset.root="${TASK1_ROOT}" \
    --dataset.num_episodes=${TASK1_NUM_EPISODES} \
    --dataset.episode_time_s=${TASK1_EPISODE_TIME_S} \
    --dataset.reset_time_s=${TASK1_RESET_TIME_S} \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="${TASK1_TASK_TEXT}" \
    ${EXTRA_FLAGS}
