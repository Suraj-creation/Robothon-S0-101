#!/usr/bin/env bash
# Task 2 — RECORD 90 CHARGER PLUG DEMOS via teleoperation.
#
# This is the hardest task. Plan ~100 minutes including resets.
# 90 demos because insertion is precision-critical (mm tolerance) and ACT
# needs more data than pick & place to learn the alignment.
#
# DEMO STRUCTURE — every episode follows the same 3 phases:
#   1) GRASP the connector body (top-down). 2-3 seconds.
#   2) APPROACH a way-point ~3 cm in front of the socket, oriented along
#      the socket axis. 3-4 seconds.
#   3) INSERT slowly (~1 cm/s) until contact / engagement. 5-8 seconds.
#
# DEMO DISCIPLINE (CRITICAL for this task):
#   1. Move ESPECIALLY slow during the INSERT phase — the policy will mimic
#      your insertion speed, and slow insertion = high success rate.
#   2. Vary connector position in CONNECTOR_ZONE (2 distinct positions, 20
#      demos each — for 40-episode plan). Same position every time -> policy
#      memorizes one trajectory and breaks when the connector starts elsewhere.
#   3. Same orientation each time at grasp. Don't rotate the connector
#      randomly — keep its axis aligned with the socket axis.
#   4. Look at the WRIST CAM in rerun during insertion. If you can't see the
#      connector tip in the wrist view, the policy can't either, and it will
#      fail at insertion. Aim the wrist cam if needed.
#   5. If you fumble (connector slips, wrong orientation, missed socket),
#      press LEFT ARROW to drop and re-record. Use this aggressively.
#
# Recording keybinds (only work if Accessibility permission granted):
#   - Right Arrow:  end episode early (use it the moment the plug seats)
#   - Left  Arrow:  drop and re-record current episode
#   - Esc:          abort entire session (saves everything recorded so far)
#
# Run: ./scripts/task2_record.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task2_env.sh"

# Pass --resume to continue an interrupted recording session.
# This appends new episodes to the existing dataset until it reaches
# TASK2_NUM_EPISODES total.
EXTRA_FLAGS=""
if [[ "$1" == "--resume" ]]; then
  EXTRA_FLAGS="--resume=true"
  echo "==> RESUME MODE: continuing existing dataset until ${TASK2_NUM_EPISODES} episodes total"
  echo ""
fi

cat <<INFO
==========================================================
  TASK 2 DEMO RECORDING — Charger Plug
==========================================================
  Episodes:        ${TASK2_NUM_EPISODES}
  Episode length:  ${TASK2_EPISODE_TIME_S}s
  Reset time:      ${TASK2_RESET_TIME_S}s
  Camera FPS:      ${CAM_FPS}
  Overhead index:  ${OVERHEAD_INDEX}
  Wrist index:     ${WRIST_INDEX}     <-- CRITICAL for insertion
  Max joint step:  ${MAX_RELATIVE_TARGET} deg/frame  ($((MAX_RELATIVE_TARGET * CAM_FPS)) deg/s peak)
  Dataset:         ${TASK2_REPO}
                   (saved to ~/.cache/huggingface/lerobot/${TASK2_REPO})

  Total expected wall-clock: ~$(( (TASK2_NUM_EPISODES * (TASK2_EPISODE_TIME_S + TASK2_RESET_TIME_S)) / 60 )) minutes
  (plus your reset/reposition time between episodes)

  Pre-flight checklist:
    [ ] Cameras still in EXACTLY the same position as Task 1 recording
    [ ] Socket fixture bolted/clamped — can NOT rotate or slide
    [ ] CONNECTOR_ZONE marked, 3 distinct positions chosen for demos
    [ ] Connector grip orientation is consistent (same axis every time)
    [ ] Wrist cam can see the connector tip during the last 5 cm of approach
    [ ] Accessibility permission granted to Terminal (so Right/Left arrows work)
    [ ] Laptop plugged in, lid open, hard surface
    [ ] No people moving in the overhead frame
==========================================================
INFO

read -r -p "Start recording ${TASK2_NUM_EPISODES} episodes? [y/N] " ans
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
    --dataset.repo_id="${TASK2_REPO}" \
    --dataset.root="${TASK2_ROOT}" \
    --dataset.num_episodes=${TASK2_NUM_EPISODES} \
    --dataset.episode_time_s=${TASK2_EPISODE_TIME_S} \
    --dataset.reset_time_s=${TASK2_RESET_TIME_S} \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="${TASK2_TASK_TEXT}" \
    ${EXTRA_FLAGS}
