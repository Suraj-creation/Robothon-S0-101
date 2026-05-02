#!/usr/bin/env bash
# Task 3 — RECORD 35 LIQUID POURING DEMOS via teleoperation.
#
# DEMO STRUCTURE — every episode follows the same 6 phases:
#   1) GRASP the bottle (top-down, gripper closes around bottle body). 3s.
#   2) LIFT and TRANSPORT to a way-point ~5 cm above CUP_ZONE. 4s.
#   3) ALIGN: position the bottle mouth directly over the cup. 2s.
#   4) TILT slowly using wrist_roll until contents start pouring. Hold for
#      ~3-4s (the "pour duration" — keep this CONSISTENT every demo). 5s.
#   5) RETURN bottle to upright (reverse wrist_roll). 2s.
#   6) PLACE the bottle back near the start position and release. 3s.
#
# DEMO DISCIPLINE (CRITICAL for this task):
#   1. KEEP POUR DURATION CONSTANT (e.g., always 3 seconds tilted past 75°).
#      The policy will mimic your pour timing — inconsistent timing teaches it
#      to pour for variable lengths and risks under/over-pour.
#   2. KEEP TILT ANGLE CONSTANT (e.g., always rotate wrist_roll by ~90°).
#      Don't randomize the tilt angle. Pour rate depends on it.
#   3. SLOW the tilt phase. Fast tilt = splash + spill. Tilt at ~45°/sec max.
#   4. Vary CUP POSITION across demos (3 distinct spots in CUP_ZONE, ~12 demos
#      each). Bottle position can stay fixed OR vary mildly (2 spots OK).
#   5. Same grasp orientation every time — bottle vertical, gripper around the
#      neck or upper-third of the body. Don't grasp the bottom (CG too high
#      when tilted, will tip out of grip).
#   6. WATCH THE WRIST CAM in rerun during phases 3-5. If you can't see the
#      cup or the pour stream, the policy can't either.
#   7. If you fumble (bottle slips, miss the cup, big spill), press LEFT ARROW
#      to drop and re-record. Use this aggressively for Task 3.
#
# MEDIUM RECOMMENDATION (start dry, graduate to liquid):
#   FIRST 25 DEMOS: dry rice or lentils — same physics as liquid for ACT, zero
#                  spill risk if anything goes wrong. Refill the bottle and
#                  empty the cup between episodes.
#   LAST 10 DEMOS: water with a few drops of food coloring (so it's visible to
#                  the wrist cam). Towel under everything.
#
# Recording keybinds (only work if Accessibility permission granted):
#   - Right Arrow:  end episode early (use it the moment the bottle is back home)
#   - Left  Arrow:  drop and re-record current episode (use for any spill)
#   - Esc:          abort entire session (saves everything recorded so far)
#
# Run:                 ./scripts/task3_record.sh
# Resume interrupted:  ./scripts/task3_record.sh --resume
# Override episodes:   TASK3_NUM_EPISODES=10 ./scripts/task3_record.sh
# Both:                TASK3_NUM_EPISODES=40 ./scripts/task3_record.sh --resume

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task3_env.sh"

EXTRA_FLAGS=""
if [[ "$1" == "--resume" ]]; then
  EXTRA_FLAGS="--resume=true"
  echo "==> RESUME MODE: continuing existing dataset until ${TASK3_NUM_EPISODES} episodes total"
  echo ""
fi

cat <<INFO
==========================================================
  TASK 3 DEMO RECORDING — Liquid Pouring
==========================================================
  Episodes:        ${TASK3_NUM_EPISODES}
  Episode length:  ${TASK3_EPISODE_TIME_S}s
  Reset time:      ${TASK3_RESET_TIME_S}s
  Camera FPS:      ${CAM_FPS}
  Overhead index:  ${OVERHEAD_INDEX}
  Wrist index:     ${WRIST_INDEX}     <-- watches the pour stream
  Max joint step:  ${MAX_RELATIVE_TARGET} deg/frame  ($((MAX_RELATIVE_TARGET * CAM_FPS)) deg/s peak)
  Dataset:         ${TASK3_REPO}
                   (saved to ${TASK3_ROOT})

  Total expected wall-clock: ~$(( (TASK3_NUM_EPISODES * (TASK3_EPISODE_TIME_S + TASK3_RESET_TIME_S)) / 60 )) minutes
  (plus your refill / cup-empty / reposition time between episodes)

  Pre-flight checklist:
    [ ] Cameras still in EXACTLY the same position as Task 1/2 recording
    [ ] Bottle and cup are PLASTIC (not glass — drop-safe if spill happens)
    [ ] Cup is taped/weighted down (must NOT slide when bottle bumps it)
    [ ] BOTTLE_ZONE marked, 1-2 starting positions chosen
    [ ] CUP_ZONE marked, 3 distinct positions chosen (~12 demos per position)
    [ ] Towel under the workspace (catches any spill)
    [ ] First 25 demos use DRY RICE/LENTILS (zero spill risk)
    [ ] Wrist cam can see the bottle mouth + cup during the tilt phase
    [ ] Accessibility permission granted to Terminal (so Right/Left arrows work)
    [ ] Laptop plugged in, lid open, hard surface
    [ ] No people moving in the overhead frame
==========================================================
INFO

read -r -p "Start recording ${TASK3_NUM_EPISODES} episodes? [y/N] " ans
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
    --dataset.repo_id="${TASK3_REPO}" \
    --dataset.root="${TASK3_ROOT}" \
    --dataset.num_episodes=${TASK3_NUM_EPISODES} \
    --dataset.episode_time_s=${TASK3_EPISODE_TIME_S} \
    --dataset.reset_time_s=${TASK3_RESET_TIME_S} \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="${TASK3_TASK_TEXT}" \
    ${EXTRA_FLAGS}
