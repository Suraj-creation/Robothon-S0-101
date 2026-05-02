#!/usr/bin/env bash
# Task 1 — AUTONOMOUS PICK & PLACE launcher.
#
# This is a Task-1-only deployment script. It does not train, does not touch
# the original demo dataset, and does not modify Task 2/3 assets.
#
# Default behavior:
#   1. Source scripts/task1_env.sh for the known ports, cameras, and policy IDs.
#   2. Verify the trained ACT policy exists.
#   3. Warn if another lerobot training process is currently running.
#   4. Drive the follower to the Task 1 starting pose from scripts/home_pose.json.
#   5. Run the Task 1 ACT policy autonomously with lerobot-record.
#   6. Save the run into a new timestamped local eval dataset.
#
# Typical run, after the current Task 2 training is finished:
#   ./scripts/task1_autonomous_pick_place.sh
#
# Non-interactive:
#   ./scripts/task1_autonomous_pick_place.sh --yes
#
# If you intentionally want to run while Task 2 training is still using CPU:
#   ./scripts/task1_autonomous_pick_place.sh --allow-while-training

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task1_env.sh"

POLICY_DIR="${REPO_ROOT}/${TASK1_OUTPUT_DIR}/checkpoints/last/pretrained_model"
HOME_JSON="${SCRIPT_DIR}/home_pose.json"

EPISODES=1
EPISODE_TIME_S=25
RESET_TIME_S=2
DISPLAY_DATA=true
GO_HOME=true
VISION_CHECK=true
REQUIRE_COLORED_OBJECT=false
RUN_DISABLE_TORQUE_ON_DISCONNECT=false
RELEASE_TORQUE_AFTER_RUN=true
SKIP_PROMPT=0
ALLOW_WHILE_TRAINING=0
REPO_ID=""
RUN_MAX_RELATIVE_TARGET="${MAX_RELATIVE_TARGET}"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --episodes N                 Number of autonomous episodes to run (default: ${EPISODES})
  --episode-time-s SECONDS     Seconds per episode (default: ${EPISODE_TIME_S})
  --reset-time-s SECONDS       Reset time between episodes (default: ${RESET_TIME_S})
  --repo-id REPO               Local eval repo id to write. Default is timestamped.
  --display-data true|false    Show rerun live data viewer (default: ${DISPLAY_DATA})
  --no-home                    Do not drive to the Task 1 start pose first.
  --no-vision-check            Skip overhead camera/Yolo preflight.
  --require-colored-object     Abort if the preflight cannot see a saturated colored blob.
  --hold-torque-after-run      Leave follower torque enabled after the run exits.
  --max-relative-target VALUE  Override max joint step per command (default: ${RUN_MAX_RELATIVE_TARGET})
  --allow-while-training       Allow running even if lerobot-train is active.
  --yes, -y                    Skip confirmation prompt.
  --help, -h                   Show this help.

Examples:
  $0
  $0 --episodes 3 --episode-time-s 25
  $0 --repo-id local/eval_so101_pick_v1_autonomous_test --yes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --episodes)
      EPISODES="$2"
      shift 2
      ;;
    --episode-time-s)
      EPISODE_TIME_S="$2"
      shift 2
      ;;
    --reset-time-s)
      RESET_TIME_S="$2"
      shift 2
      ;;
    --repo-id)
      REPO_ID="$2"
      shift 2
      ;;
    --display-data)
      DISPLAY_DATA="$2"
      shift 2
      ;;
    --no-home)
      GO_HOME=false
      shift
      ;;
    --no-vision-check)
      VISION_CHECK=false
      shift
      ;;
    --require-colored-object)
      REQUIRE_COLORED_OBJECT=true
      shift
      ;;
    --hold-torque-after-run)
      RELEASE_TORQUE_AFTER_RUN=false
      shift
      ;;
    --max-relative-target)
      RUN_MAX_RELATIVE_TARGET="$2"
      shift 2
      ;;
    --allow-while-training)
      ALLOW_WHILE_TRAINING=1
      shift
      ;;
    --yes|-y)
      SKIP_PROMPT=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${REPO_ID}" ]]; then
  REPO_ID="local/eval_so101_pick_v1_autonomous_$(date +%Y%m%d_%H%M%S)"
fi
REPO_NAME="${REPO_ID##*/}"
if [[ "${REPO_NAME}" != eval_* ]]; then
  echo "ERROR: LeRobot requires eval dataset names to start with 'eval_' when --policy.path is used."
  echo "Your repo id was: ${REPO_ID}"
  echo "Use for example: local/eval_so101_pick_v1_autonomous_test"
  exit 1
fi
EVAL_ROOT="${HOME}/.cache/huggingface/lerobot/${REPO_ID}"

if [[ ! -d "${POLICY_DIR}" ]]; then
  echo "ERROR: Task 1 policy not found at:"
  echo "  ${POLICY_DIR}"
  echo "Train Task 1 first, or check ${TASK1_OUTPUT_DIR}/checkpoints/last."
  exit 1
fi

for required in config.json model.safetensors policy_preprocessor.json policy_postprocessor.json; do
  if [[ ! -f "${POLICY_DIR}/${required}" ]]; then
    echo "ERROR: Task 1 policy is incomplete; missing ${required}"
    echo "  ${POLICY_DIR}"
    exit 1
  fi
done

if [[ "${GO_HOME}" == "true" && ! -f "${HOME_JSON}" ]]; then
  echo "ERROR: HOME pose file not found:"
  echo "  ${HOME_JSON}"
  echo "Run: .conda/bin/python scripts/capture_home.py"
  exit 1
fi

if [[ -e "${EVAL_ROOT}" ]]; then
  echo "ERROR: output eval dataset already exists:"
  echo "  ${EVAL_ROOT}"
  echo "Choose a fresh --repo-id, or remove that folder yourself if it is throwaway."
  exit 1
fi

if [[ "${ALLOW_WHILE_TRAINING}" -eq 0 ]] && pgrep -f "lerobot-train" >/dev/null 2>&1; then
  cat <<WARN
WARNING: an active lerobot-train process is running.

Running autonomous inference while Task 2 is training will not stop training,
but both jobs compete for CPU. The follower may lag, and training may slow down.

Recommended: wait until Task 2 training finishes.

To run anyway:
  $0 --allow-while-training
WARN
  exit 1
fi

cat <<INFO
==========================================================
  TASK 1 AUTONOMOUS PICK & PLACE
==========================================================
  Policy:        ${POLICY_DIR}
  Output repo:   ${REPO_ID}
  Output root:   ${EVAL_ROOT}
  Episodes:      ${EPISODES}
  Episode time:  ${EPISODE_TIME_S}s
  Reset time:    ${RESET_TIME_S}s
  Cameras:       overhead index ${OVERHEAD_INDEX}, wrist index ${WRIST_INDEX}
  Follower:      ${FOLLOWER_PORT}
  Max step:      ${RUN_MAX_RELATIVE_TARGET} deg/update
  Go HOME first: ${GO_HOME}
  Vision check:  ${VISION_CHECK}
  Hold during startup: yes
  Release after run:  ${RELEASE_TORQUE_AFTER_RUN}

  Initial scene required:
    [ ] Cube in PICK_ZONE
    [ ] DROP_ZONE visible and unchanged from recording
    [ ] Cameras locked exactly as during Task 1 demos
    [ ] Follower powered, workspace clear, hand near power switch
==========================================================
INFO

if [[ "${SKIP_PROMPT}" -eq 0 ]]; then
  read -r -p "Start autonomous Task 1 now? [y/N] " ans
  [[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

cd "${REPO_ROOT}"

if [[ "${VISION_CHECK}" == "true" ]]; then
  echo ""
  echo "[vision] Checking overhead camera before motion..."
  VISION_ARGS=(
    --camera-index "${OVERHEAD_INDEX}"
    --width "${CAM_W}"
    --height "${CAM_H}"
    --yolo-weights "${REPO_ROOT}/yolo11n.pt"
  )
  if [[ "${REQUIRE_COLORED_OBJECT}" == "true" ]]; then
    VISION_ARGS+=(--require-colored-object)
  fi
  "${LEROBOT}/python" "${SCRIPT_DIR}/task1_vision_gate.py" "${VISION_ARGS[@]}"
fi

if [[ "${GO_HOME}" == "true" ]]; then
  echo ""
  echo "[home] Driving follower to Task 1 start pose..."
  "${LEROBOT}/python" "${SCRIPT_DIR}/go_home.py" --task pick --duration 3.0 --quiet
  echo "[home] Settled."
fi

echo ""
echo "[run] Starting autonomous pick policy..."
echo "[run] LeRobot startup can take 30-90 seconds; wait for policy control before judging motion."
set +e
"${LEROBOT}/lerobot-record" \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${ROBOT_ID}" \
    --robot.disable_torque_on_disconnect="${RUN_DISABLE_TORQUE_ON_DISCONNECT}" \
    --robot.max_relative_target=${RUN_MAX_RELATIVE_TARGET} \
    --robot.cameras="${CAMERAS_SPEC}" \
    --display_data="${DISPLAY_DATA}" \
    --dataset.repo_id="${REPO_ID}" \
    --dataset.root="${EVAL_ROOT}" \
    --dataset.num_episodes="${EPISODES}" \
    --dataset.episode_time_s="${EPISODE_TIME_S}" \
    --dataset.reset_time_s="${RESET_TIME_S}" \
    --dataset.fps="${CAM_FPS}" \
    --dataset.push_to_hub=false \
    --dataset.single_task="Pick the cube and place it in the green target zone." \
    --policy.path="${POLICY_DIR}"
status=$?
set -e

if [[ "${RELEASE_TORQUE_AFTER_RUN}" == "true" ]]; then
  echo ""
  echo "[cleanup] Releasing follower torque..."
  "${LEROBOT}/python" "${SCRIPT_DIR}/so101_release_torque.py" \
    --port "${FOLLOWER_PORT}" \
    --id "${ROBOT_ID}" || true
fi

exit "${status}"
