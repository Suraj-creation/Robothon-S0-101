#!/usr/bin/env bash
# Robothon FULL AUTONOMOUS DEMO — Pick → Plug → Pour using policies under models/
# (Same sequence as run_full_demo.sh; checkpoints come from Hugging Face sync / GitHub,
# not outputs/act_*_v1/checkpoints/last/pretrained_model.)
#
# Prerequisites:
#   models/act_pick_v1/, models/act_plug_v1/, models/act_pour_v1/  (LeRobot pretrained_model layout)
#   scripts/home_pose.json
#
# Populate models/:
#   HF_HUB_DISABLE_XET=1 HF_TOKEN=... .conda/bin/python scripts/sync_models_from_hf.py
#
# Run: ./scripts/run_full_demo_github_models.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
LEROBOT="${REPO_ROOT}/.conda/bin"
export PATH="${LEROBOT}:${PATH}"

source "${SCRIPT_DIR}/task1_env.sh"

PICK_POLICY="${REPO_ROOT}/models/act_pick_v1"
PLUG_POLICY="${REPO_ROOT}/models/act_plug_v1"
POUR_POLICY="${REPO_ROOT}/models/act_pour_v1"
HOME_JSON="${SCRIPT_DIR}/home_pose.json"

missing=0
for p in "${PICK_POLICY}" "${PLUG_POLICY}" "${POUR_POLICY}"; do
  if [[ ! -d "${p}" ]]; then
    echo "  [missing] ${p}"
    missing=1
  fi
done
if [[ ! -f "${HOME_JSON}" ]]; then
  echo "  [missing] ${HOME_JSON}"
  echo "  (run: .conda/bin/python scripts/capture_home.py)"
  missing=1
fi
if [[ "${missing}" -eq 1 ]]; then
  echo ""
  echo "ERROR: pre-requisites not met. Sync HF models: scripts/sync_models_from_hf.py"
  exit 1
fi

cat <<INFO
==========================================================
  ROBOTHON FULL AUTONOMOUS DEMO (models/ checkpoints)
==========================================================
  Phase 1: Pick & Place    (25s)   ${PICK_POLICY}
  Phase 2: Charger Plug    (30s)   ${PLUG_POLICY}
  Phase 3: Liquid Pour     (30s)   ${POUR_POLICY}

  HOME pose:     ${HOME_JSON}
  Eval datasets: local/so101_*_hf_autorun (auto-saved for review)
  Cameras:       overhead idx ${OVERHEAD_INDEX}, wrist idx ${WRIST_INDEX}

  TOTAL: ~2 minutes wall-clock.

  Initial state required:
    - Cube in PICK_ZONE
    - Connector in CONNECTOR_ZONE
    - Bottle (full) in BOTTLE_ZONE
    - Empty cup in CUP_ZONE
    - Robot powered, leader idle, cameras locked
==========================================================
INFO

read -r -p "Start the full autonomous demo? [y/N] " ans
[[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

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
  "local/so101_pick_v1_hf_autorun" \
  "Pick the cube and place it on the target." \
  25

go_home plug

deploy_phase "Charger Plug" "${PLUG_POLICY}" \
  "local/so101_plug_v1_hf_autorun" \
  "Plug the charger connector into the socket." \
  30

go_home pour

deploy_phase "Liquid Pour" "${POUR_POLICY}" \
  "local/so101_pour_v1_hf_autorun" \
  "Pour the contents of the bottle into the cup." \
  30

go_home

echo ""
echo "=========================================================="
echo "  AUTONOMOUS DEMO COMPLETE — $(date '+%H:%M:%S')"
echo "=========================================================="
echo "  Review the recorded runs:"
echo "    - local/so101_pick_v1_hf_autorun"
echo "    - local/so101_plug_v1_hf_autorun"
echo "    - local/so101_pour_v1_hf_autorun"
echo "=========================================================="
