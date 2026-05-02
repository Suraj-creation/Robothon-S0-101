#!/usr/bin/env bash
# Task 2 — DEPLOY trained policy autonomously and record 10 eval episodes.
#
# The policy drives the follower. The leader sits there. You reset the
# connector position between episodes and watch insertion success rate.
#
# Run: ./scripts/task2_eval.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task2_env.sh"

POLICY_DIR="${REPO_ROOT}/${TASK2_OUTPUT_DIR}/checkpoints/last/pretrained_model"

if [[ ! -d "${POLICY_DIR}" ]]; then
  echo "ERROR: trained policy not found at ${POLICY_DIR}"
  echo "Run ./scripts/task2_train.sh first."
  exit 1
fi

cat <<INFO
==========================================================
  TASK 2 AUTONOMOUS EVAL — Charger Plug
==========================================================
  Policy:        ${POLICY_DIR}
  Eval episodes: 10
  Episode time:  30s

  The policy drives the follower autonomously — no leader input.
  After each episode, reset the connector to a different position
  in CONNECTOR_ZONE.

  Watch for:
    - Grasp success: did it pick up the connector?
    - Approach: did it align the axis with the socket?
    - Insertion: did it seat the connector? Was it slow & smooth?

  Common failure modes to log:
    - Misalignment >1mm at insertion
    - Connector slipping during approach
    - Stops short of insertion ("hovers" without inserting)

  Each failure mode tells you exactly what targeted demos to add
  for the next iteration.
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
    --dataset.repo_id="${TASK2_EVAL_REPO}" \
    --dataset.root="${TASK2_EVAL_ROOT}" \
    --dataset.num_episodes=10 \
    --dataset.episode_time_s=30 \
    --dataset.reset_time_s=10 \
    --dataset.fps=${CAM_FPS} \
    --dataset.push_to_hub=false \
    --dataset.single_task="Plug the charger connector into the socket." \
    --policy.path="${POLICY_DIR}"
