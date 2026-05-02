#!/usr/bin/env bash
# Task 2 — AUTONOMOUS CHARGER PLUG using the ACT policy under models/ (Hugging Face sync)
# or local training checkpoints under outputs/act_plug_v1.
#
# Resolution order when --policy-dir is omitted:
#   1) models/act_plug_v1/
#   2) outputs/act_plug_v1/checkpoints/last/pretrained_model
#
# Populate models/act_plug_v1 from Hub (when the repo exists):
#   HF_HUB_DISABLE_XET=1 HF_TOKEN=... .conda/bin/python scripts/sync_models_from_hf.py --plug-only
#
# Example:
#   ./scripts/task2_autonomous_github_models.sh --yes

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task2_env.sh"

REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
POLICY_DIR=""
HOME_JSON="${SCRIPT_DIR}/home_pose.json"

EPISODES=1
EPISODE_TIME_S=30
RESET_TIME_S=10
DISPLAY_DATA=true
GO_HOME=true
RUN_DISABLE_TORQUE_ON_DISCONNECT=false
RELEASE_TORQUE_AFTER_RUN=true
SKIP_PROMPT=0
ALLOW_WHILE_TRAINING=0
REPO_ID=""
RUN_MAX_RELATIVE_TARGET="${MAX_RELATIVE_TARGET}"

usage() {
  cat <<EOF
Usage: $0 [options]

Runs Task 2 autonomous plug using models/act_plug_v1 (HF / GitHub bundle) when present,
otherwise outputs/act_plug_v1/checkpoints/last/pretrained_model.

Options:
  --policy-dir PATH            Force policy folder (skip auto-resolution)
  --episodes N                 Number of autonomous episodes (default: ${EPISODES})
  --episode-time-s SECONDS     Seconds per episode (default: ${EPISODE_TIME_S})
  --reset-time-s SECONDS       Reset between episodes (default: ${RESET_TIME_S})
  --repo-id REPO               Eval repo id (must start with eval_). Default timestamped.
  --display-data true|false    Rerun viewer (default: ${DISPLAY_DATA})
  --no-home                    Skip plug start pose from home_pose.json
  --hold-torque-after-run      Keep torque enabled after run
  --max-relative-target VALUE  Override max joint step (default: ${RUN_MAX_RELATIVE_TARGET})
  --allow-while-training       Allow even if lerobot-train is running
  --yes, -y                    Skip confirmation
  --help, -h                   This help

Sync plug weights from Hugging Face:
  HF_HUB_DISABLE_XET=1 HF_TOKEN=... .conda/bin/python scripts/sync_models_from_hf.py --plug-only

Examples:
  $0 --yes
  $0 --policy-dir "\${REPO_ROOT}/models/act_plug_v1" --yes
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

if [[ -z "${POLICY_DIR}" ]]; then
  if [[ -d "${REPO_ROOT}/models/act_plug_v1" ]]; then
    POLICY_DIR="${REPO_ROOT}/models/act_plug_v1"
  elif [[ -d "${REPO_ROOT}/outputs/act_plug_v1/checkpoints/last/pretrained_model" ]]; then
    POLICY_DIR="${REPO_ROOT}/outputs/act_plug_v1/checkpoints/last/pretrained_model"
  fi
fi

if [[ -z "${REPO_ID}" ]]; then
  REPO_ID="local/eval_so101_plug_v1_models_$(date +%Y%m%d_%H%M%S)"
fi
REPO_NAME="${REPO_ID##*/}"
if [[ "${REPO_NAME}" != eval_* ]]; then
  echo "ERROR: repo id must start with eval_ (LeRobot requirement with --policy.path)."
  echo "  Got: ${REPO_ID}"
  echo "  Example: local/eval_so101_plug_v1_models_run"
  exit 1
fi
EVAL_ROOT="${HOME}/.cache/huggingface/lerobot/${REPO_ID}"

if [[ -z "${POLICY_DIR}" || ! -d "${POLICY_DIR}" ]]; then
  echo "ERROR: Task 2 ACT policy not found."
  echo "  Expected one of:"
  echo "    ${REPO_ROOT}/models/act_plug_v1   (HF: SurajCreation/act_plug_v1 — run sync_models_from_hf.py --plug-only)"
  echo "    ${REPO_ROOT}/outputs/act_plug_v1/checkpoints/last/pretrained_model"
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
  TASK 2 AUTONOMOUS — Charger plug (ACT, models/ or outputs/)
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

if [[ "${GO_HOME}" == "true" ]]; then
  echo ""
  echo "[home] Task 2 (plug) start pose..."
  "${LEROBOT}/python" "${SCRIPT_DIR}/go_home.py" --task plug --duration 3.0 --quiet
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
    --dataset.single_task="Plug the charger connector into the socket." \
    --policy.path="${POLICY_DIR}"
status=$?
set -e

if [[ "${RELEASE_TORQUE_AFTER_RUN}" == "true" ]]; then
  "${LEROBOT}/python" "${SCRIPT_DIR}/so101_release_torque.py" \
    --port "${FOLLOWER_PORT}" \
    --id "${ROBOT_ID}" || true
fi

exit "${status}"
