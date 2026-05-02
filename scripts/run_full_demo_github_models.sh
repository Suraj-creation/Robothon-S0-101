#!/usr/bin/env bash
# Robothon FULL AUTONOMOUS DEMO — Pick → Plug → Pour.
#
# Policy resolution (first match wins for each task):
#   1) models/act_<pick|plug|pour>_v1/          (HF sync / GitHub clone)
#   2) outputs/act_<task>_v1/checkpoints/last/pretrained_model  (local training)
#
# Prerequisites:
#   Pick checkpoint required: models/act_pick_v1 or outputs/act_pick_v1/.../pretrained_model
#   Plug & pour: required unless you pass --available-only (then missing phases are skipped).
#   scripts/home_pose.json
#
# Populate models/ from Hub when repos exist:
#   HF_HUB_DISABLE_XET=1 HF_TOKEN=... .conda/bin/python scripts/sync_models_from_hf.py
#
# Run:
#   ./scripts/run_full_demo_github_models.sh
# With only pick trained / synced (skip missing plug & pour):
#   ./scripts/run_full_demo_github_models.sh --available-only
#   ./scripts/run_full_demo_github_models.sh -a --yes

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
LEROBOT="${REPO_ROOT}/.conda/bin"
export PATH="${LEROBOT}:${PATH}"

AVAILABLE_ONLY=0
SKIP_CONFIRM=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --available-only|-a) AVAILABLE_ONLY=1; shift ;;
    --yes|-y) SKIP_CONFIRM=1; shift ;;
    -h|--help)
      sed -n '1,20p' "$0" | tail -n +2
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

source "${SCRIPT_DIR}/task1_env.sh"

HOME_JSON="${SCRIPT_DIR}/home_pose.json"

# shellcheck disable=SC2317
resolve_policy_dir() {
  local task="$1"
  local m="${REPO_ROOT}/models/act_${task}_v1"
  local o="${REPO_ROOT}/outputs/act_${task}_v1/checkpoints/last/pretrained_model"
  if [[ -d "${m}" ]]; then
    echo "${m}"
    return 0
  fi
  if [[ -d "${o}" ]]; then
    echo "${o}"
    return 0
  fi
  echo ""
}

PICK_POLICY="$(resolve_policy_dir pick)"
PLUG_POLICY="$(resolve_policy_dir plug)"
POUR_POLICY="$(resolve_policy_dir pour)"

missing=0
if [[ -z "${PICK_POLICY}" ]]; then
  echo "  [missing pick] ${REPO_ROOT}/models/act_pick_v1"
  echo "              or ${REPO_ROOT}/outputs/act_pick_v1/checkpoints/last/pretrained_model"
  missing=1
fi
if [[ "${AVAILABLE_ONLY}" -eq 0 ]]; then
  if [[ -z "${PLUG_POLICY}" ]]; then
    echo "  [missing plug] ${REPO_ROOT}/models/act_plug_v1"
    echo "              or ${REPO_ROOT}/outputs/act_plug_v1/checkpoints/last/pretrained_model"
    missing=1
  fi
  if [[ -z "${POUR_POLICY}" ]]; then
    echo "  [missing pour] ${REPO_ROOT}/models/act_pour_v1"
    echo "              or ${REPO_ROOT}/outputs/act_pour_v1/checkpoints/last/pretrained_model"
    missing=1
  fi
fi
if [[ ! -f "${HOME_JSON}" ]]; then
  echo "  [missing] ${HOME_JSON}"
  echo "  (run: .conda/bin/python scripts/capture_home.py)"
  missing=1
fi
if [[ "${missing}" -eq 1 ]]; then
  echo ""
  echo "ERROR: pre-requisites not met."
  echo "  Train locally (outputs/...) and/or sync HF: .conda/bin/python scripts/sync_models_from_hf.py"
  echo "  Or run pick-only / partial pipeline: $0 --available-only"
  exit 1
fi

PLUG_LINE="  Phase 2: Charger Plug    (30s)   ${PLUG_POLICY:-SKIPPED — no checkpoint}"
POUR_LINE="  Phase 3: Liquid Pour     (30s)   ${POUR_POLICY:-SKIPPED — no checkpoint}"
if [[ "${AVAILABLE_ONLY}" -eq 1 ]]; then
  if [[ -z "${PLUG_POLICY}" ]]; then PLUG_LINE="  Phase 2: Charger Plug    — SKIPPED (no checkpoint)"; fi
  if [[ -z "${POUR_POLICY}" ]]; then POUR_LINE="  Phase 3: Liquid Pour     — SKIPPED (no checkpoint)"; fi
fi

cat <<INFO
==========================================================
  ROBOTHON FULL AUTONOMOUS DEMO (models/ or outputs/)
==========================================================
  Phase 1: Pick & Place    (25s)   ${PICK_POLICY}
${PLUG_LINE}
${POUR_LINE}
  Mode: $([[ "${AVAILABLE_ONLY}" -eq 1 ]] && echo 'partial (--available-only)' || echo 'full (all checkpoints required)')

  HOME pose:     ${HOME_JSON}
  Eval datasets: local/eval_so101_*_hf_autorun (LeRobot requires eval_ prefix with --policy.path)
  Cameras:       overhead idx ${OVERHEAD_INDEX}, wrist idx ${WRIST_INDEX}

  Initial state required:
    - Cube in PICK_ZONE
    - Connector in CONNECTOR_ZONE
    - Bottle (full) in BOTTLE_ZONE
    - Empty cup in CUP_ZONE
    - Robot powered, leader idle, cameras locked
==========================================================
INFO

if [[ "${SKIP_CONFIRM}" -eq 0 ]]; then
  read -r -p "Start the autonomous demo? [y/N] " ans
  [[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

deploy_phase() {
  local phase_name="$1"
  local policy_dir="$2"
  local repo_id="$3"
  local task_text="$4"
  local episode_time_s="$5"

  echo ""
  echo "----------------------------------------------------------"
  echo "  PHASE: ${phase_name}  (${episode_time_s}s)"
  echo "----------------------------------------------------------"

  local eval_root="${HOME}/.cache/huggingface/lerobot/${repo_id}"
  rm -rf "${eval_root}"

  cd "${REPO_ROOT}"
  "${LEROBOT}/lerobot-record" \
      --robot.type=so101_follower \
      --robot.port="${FOLLOWER_PORT}" \
      --robot.id="${ROBOT_ID}" \
      --robot.max_relative_target=${MAX_RELATIVE_TARGET} \
      --robot.cameras="${CAMERAS_SPEC}" \
      --display_data=true \
      --dataset.repo_id="${repo_id}" \
      --dataset.root="${eval_root}" \
      --dataset.num_episodes=1 \
      --dataset.episode_time_s=${episode_time_s} \
      --dataset.reset_time_s=2 \
      --dataset.fps=${CAM_FPS} \
      --dataset.push_to_hub=false \
      --dataset.single_task="${task_text}" \
      --policy.path="${policy_dir}"
}

go_home() {
  local task="${1:-}"
  local label="${task:-HOME}"
  echo ""
  echo "[home]  Driving to ${label} pose..."
  if [[ -n "${task}" ]]; then
    "${LEROBOT}/python" "${SCRIPT_DIR}/go_home.py" --task "${task}" --duration 3.0 --quiet
  else
    "${LEROBOT}/python" "${SCRIPT_DIR}/go_home.py" --duration 3.0 --quiet
  fi
  echo "[home]  Settled."
  sleep 0.5
}

echo ""
echo "[start] $(date '+%H:%M:%S') — beginning autonomous sequence"

go_home pick

deploy_phase "Pick & Place" "${PICK_POLICY}" \
  "local/eval_so101_pick_v1_hf_autorun" \
  "Pick the cube and place it on the target." \
  25

if [[ -n "${PLUG_POLICY}" ]]; then
  go_home plug
  deploy_phase "Charger Plug" "${PLUG_POLICY}" \
    "local/eval_so101_plug_v1_hf_autorun" \
    "Plug the charger connector into the socket." \
    30
else
  echo ""
  echo "[skip] Plug phase — no checkpoint (train task 2 or sync HF act_plug_v1)."
fi

if [[ -n "${POUR_POLICY}" ]]; then
  go_home pour
  deploy_phase "Liquid Pour" "${POUR_POLICY}" \
    "local/eval_so101_pour_v1_hf_autorun" \
    "Pour the contents of the bottle into the cup." \
    30
else
  echo ""
  echo "[skip] Pour phase — no checkpoint (train task 3 or sync HF act_pour_v1)."
fi

go_home

echo ""
echo "=========================================================="
echo "  AUTONOMOUS DEMO COMPLETE — $(date '+%H:%M:%S')"
echo "=========================================================="
echo "  Recordings (phases that ran):"
echo "    - local/eval_so101_pick_v1_hf_autorun"
if [[ -n "${PLUG_POLICY}" ]]; then echo "    - local/eval_so101_plug_v1_hf_autorun"; fi
if [[ -n "${POUR_POLICY}" ]]; then echo "    - local/eval_so101_pour_v1_hf_autorun"; fi
echo "=========================================================="
