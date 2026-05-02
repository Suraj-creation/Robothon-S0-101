#!/usr/bin/env bash
# Task 1 — DEPLOY trained policy autonomously and record 10 eval episodes.
#
# The policy drives the follower. The leader can sit there. You're just
# watching success/failure and resetting the cube between episodes.
#
# Run: ./scripts/task1_eval.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task1_env.sh"

POLICY_DIR="${REPO_ROOT}/${TASK1_OUTPUT_DIR}/checkpoints/last/pretrained_model"

if [[ ! -d "${POLICY_DIR}" ]]; then
  echo "ERROR: trained policy not found at ${POLICY_DIR}"
  echo "Run ./scripts/task1_train.sh first."
  exit 1
fi

cat <<INFO
==========================================================
  TASK 1 AUTONOMOUS EVAL — Pick & Place
==========================================================
  Policy:        ${POLICY_DIR}
  Eval episodes: 10
  Episode time:  25s

  The policy drives the follower autonomously — no leader input.
  After each episode, reset the cube to a new position in PICK_ZONE.

  Watch for: grasp success, lift smoothness, transport stability,
  release accuracy. Any failure mode you spot is a clue for what
  demos to add and re-train with.
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
    --dataset.repo_id="${TASK1_EVAL_REPO}" \
    --dataset.root="${TASK1_EVAL_ROOT}" \
    --dataset.num_episodes=10 \
    --dataset.episode_time_s=25 \
    --dataset.reset_time_s=8 \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="Pick and place the cube." \
    --policy.path="${POLICY_DIR}"
