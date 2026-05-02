#!/usr/bin/env bash
# Task 3 — DEPLOY trained policy autonomously and record 10 eval episodes.
#
# The policy drives the follower. The leader sits there. You refill the
# bottle and reset the cup position between episodes and watch pour success
# rate.
#
# SAFETY: Use water for eval (the real task is liquid pouring). Towel
# under the workspace. Have a second cup ready to catch overflow.
#
# Run: ./scripts/task3_eval.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task3_env.sh"

POLICY_DIR="${REPO_ROOT}/${TASK3_OUTPUT_DIR}/checkpoints/last/pretrained_model"

if [[ ! -d "${POLICY_DIR}" ]]; then
  echo "ERROR: trained policy not found at ${POLICY_DIR}"
  echo "Run ./scripts/task3_train.sh first."
  exit 1
fi

cat <<INFO
==========================================================
  TASK 3 AUTONOMOUS EVAL — Liquid Pouring
==========================================================
  Policy:        ${POLICY_DIR}
  Eval episodes: 10
  Episode time:  30s

  The policy drives the follower autonomously — no leader input.
  Between episodes:
    - Refill the bottle (same level every time for fair comparison).
    - Empty the cup.
    - Move the cup to a different position in CUP_ZONE.

  Score each episode on:
    - Grasp success: did it pick up the bottle cleanly?
    - Transport: did it reach above the cup without bumping it?
    - Pour: did liquid land in the cup? (vs. beside the cup = miss)
    - Volume: roughly correct fill level? (under-pour / over-pour)
    - Return: did it place the bottle back without dropping it?

  Common failure modes to log:
    - Pour misses cup (alignment off)
    - Tilt too fast -> splash
    - Tilt too far -> empties the bottle
    - Tilt too little -> nothing pours
    - Bottle slips during transport

  Each failure mode tells you what targeted demos to add for retraining.
==========================================================
INFO

cd "${REPO_ROOT}"
exec "${LEROBOT}/lerobot-record" \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${ROBOT_ID}" \
    --robot.max_relative_target=${MAX_RELATIVE_TARGET} \
    --robot.cameras="${CAMERAS_SPEC}" \
    --display_data=true \
    --dataset.repo_id="${TASK3_EVAL_REPO}" \
    --dataset.root="${TASK3_EVAL_ROOT}" \
    --dataset.num_episodes=10 \
    --dataset.episode_time_s=30 \
    --dataset.reset_time_s=15 \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="Pour the contents of the bottle into the cup." \
    --policy.path="${POLICY_DIR}"
