#!/usr/bin/env bash
# Task 1 — AUTONOMOUS PICK & PLACE using the policy vendored under models/
# (GitHub clone or scripts/sync_models_from_hf.py), NOT outputs/act_pick_v1.
#
# This is separate from task1_autonomous_pick_place.sh which uses training checkpoints.
#
# Prerequisites:
#   models/act_pick_v1/  must contain config.json, model.safetensors, preprocessor/postprocessor
#
# Example:
#   ./scripts/task1_autonomous_github_models.sh --yes

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task1_env.sh"

REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
POLICY_DIR="${REPO_ROOT}/models/act_pick_v1"
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

Runs Task 1 autonomous pick using models/act_pick_v1 (from GitHub / HF sync),
not outputs/act_pick_v1.

Options:
  --policy-dir PATH            Override policy folder (default: \${REPO_ROOT}/models/act_pick_v1)
  --episodes N                 Number of autonomous episodes (default: ${EPISODES})
  --episode-time-s SECONDS     Seconds per episode (default: ${EPISODE_TIME_S})
  --reset-time-s SECONDS       Reset time between episodes (default: ${RESET_TIME_S})
  --repo-id REPO               Eval repo id (must start with eval_). Default timestamped.
  --display-data true|false    Rerun viewer (default: ${DISPLAY_DATA})
  --no-home                    Skip Task 1 start pose from home_pose.json
  --no-vision-check            Skip YOLO overhead preflight
  --require-colored-object     Require colored blob in overhead frame
  --hold-torque-after-run      Keep torque enabled after run
  --max-relative-target VALUE  Override max joint step (default: ${RUN_MAX_RELATIVE_TARGET})
  --allow-while-training       Allow even if lerobot-train is running
  --yes, -y                    Skip confirmation
  --help, -h                   This help

Populate models/act_pick_v1 first:
  git pull   # if cloned from GitHub
  # or: .conda/bin/python scripts/sync_models_from_hf.py --pick-only

Examples:
  $0 --yes
  $0 --allow-while-training --display-data false --yes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy-dir)
      POLICY_DIR="$2"
      shift 2
      ;;
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
  REPO_ID="local/eval_so101_pick_v1_models_$(date +%Y%m%d_%H%M%S)"
fi
REPO_NAME="${REPO_ID##*/}"
if [[ "${REPO_NAME}" != eval_* ]]; then
  echo "ERROR: repo id must start with eval_ (LeRobot requirement with --policy.path)."
  echo "  Got: ${REPO_ID}"
  echo "  Example: local/eval_so101_pick_v1_models_run"
  exit 1
fi
EVAL_ROOT="${HOME}/.cache/huggingface/lerobot/${REPO_ID}"

if [[ ! -d "${POLICY_DIR}" ]]; then
  echo "ERROR: policy folder not found:"
  echo "  ${POLICY_DIR}"
  echo "Clone the repo with models/act_pick_v1 or run:"
  echo "  .conda/bin/python scripts/sync_models_from_hf.py --pick-only"
  exit 1
fi

for required in config.json model.safetensors policy_preprocessor.json policy_postprocessor.json; do
  if [[ ! -f "${POLICY_DIR}/${required}" ]]; then
    echo "ERROR: incomplete policy; missing ${required}"
    echo "  ${POLICY_DIR}"
    exit 1
  fi
done

if [[ "${GO_HOME}" == "true" && ! -f "${HOME_JSON}" ]]; then
  echo "ERROR: HOME pose file not found: ${HOME_JSON}"
  exit 1
fi

if [[ -e "${EVAL_ROOT}" ]]; then
  echo "ERROR: eval dataset already exists: ${EVAL_ROOT}"
  exit 1
fi

if [[ "${ALLOW_WHILE_TRAINING}" -eq 0 ]] && pgrep -f "lerobot-train" >/dev/null 2>&1; then
  cat <<WARN
WARNING: lerobot-train is running. Inference will compete for CPU.

Run with:  $0 --allow-while-training
WARN
  exit 1
fi

cat <<INFO
==========================================================
  TASK 1 AUTONOMOUS (models/act_pick_v1 — GitHub / HF bundle)
==========================================================
  Policy:        ${POLICY_DIR}
  Output repo:   ${REPO_ID}
  Episodes:      ${EPISODES}
  Cameras:       overhead ${OVERHEAD_INDEX}, wrist ${WRIST_INDEX}
  Follower:      ${FOLLOWER_PORT}
==========================================================
INFO

if [[ "${SKIP_PROMPT}" -eq 0 ]]; then
  read -r -p "Start now? [y/N] " ans
  [[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

cd "${REPO_ROOT}"

if [[ "${VISION_CHECK}" == "true" ]]; then
  echo ""
  echo "[vision] Overhead camera preflight..."
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
  echo "[home] Task 1 start pose..."
  "${LEROBOT}/python" "${SCRIPT_DIR}/go_home.py" --task pick --duration 3.0 --quiet
fi

echo ""
echo "[run] lerobot-record (startup may take 30–90 s)..."
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
  "${LEROBOT}/python" "${SCRIPT_DIR}/so101_release_torque.py" \
    --port "${FOLLOWER_PORT}" \
    --id "${ROBOT_ID}" || true
fi

exit "${status}"
