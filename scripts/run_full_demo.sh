#!/usr/bin/env bash
# Robothon FULL AUTONOMOUS DEMO — Pick → Plug → Pour, no human intervention.
#
# Pre-requisites (verify all four boxes before running):
#   [ ] All 3 policies trained:
#         outputs/act_pick_v1/checkpoints/last/pretrained_model
#         outputs/act_plug_v1/checkpoints/last/pretrained_model
#         outputs/act_pour_v1/checkpoints/last/pretrained_model
#   [ ] HOME pose captured: scripts/home_pose.json exists
#         (run: .conda/bin/python scripts/capture_home.py)
#   [ ] Each policy has been eval-tested individually and works ≥60% in isolation
#         (run: ./scripts/task1_eval.sh ; ./scripts/task2_eval.sh ; ./scripts/task3_eval.sh)
#   [ ] Initial workspace state set:
#         - Cube placed in PICK_ZONE
#         - Connector placed in CONNECTOR_ZONE
#         - Bottle placed in BOTTLE_ZONE (filled with rice/water)
#         - Empty cup placed in CUP_ZONE
#         - Cameras and fixtures in EXACTLY the same positions as during demos
#         - Robot powered on, leader connected (sits idle, doesn't drive)
#
# What this script does:
#   1) Drive follower to HOME pose (extracted from your demo recordings)
#   2) Run pick policy autonomously for 25s (records the run for review)
#   3) Drive to HOME
#   4) Run plug policy autonomously for 30s
#   5) Drive to HOME
#   6) Run pour policy autonomously for 30s
#   7) Drive to HOME and stop
#
# Total wall-clock: ~2 minutes including 3-second HOME transitions.
#
# Each phase records its own eval dataset (so101_pick_v1_eval, etc.) so you
# can review every autonomous run later.
#
# Run: ./scripts/run_full_demo.sh

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
LEROBOT="${REPO_ROOT}/.conda/bin"
export PATH="${LEROBOT}:${PATH}"

# Source Task 1 env to inherit ports, robot id, camera spec, MAX_RELATIVE_TARGET.
# (All three tasks share the same hardware/camera config — see task*_env.sh.)
source "${SCRIPT_DIR}/task1_env.sh"

# --- Pre-flight checks ----------------------------------------------------
PICK_POLICY="${REPO_ROOT}/outputs/act_pick_v1/checkpoints/last/pretrained_model"
PLUG_POLICY="${REPO_ROOT}/outputs/act_plug_v1/checkpoints/last/pretrained_model"
POUR_POLICY="${REPO_ROOT}/outputs/act_pour_v1/checkpoints/last/pretrained_model"
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
  echo "ERROR: pre-requisites not met. See the checklist at the top of this script."
  exit 1
fi

# --- Banner ---------------------------------------------------------------
cat <<INFO
==========================================================
  ROBOTHON FULL AUTONOMOUS DEMO
==========================================================
  Phase 1: Pick & Place    (25s)   ${PICK_POLICY##*/outputs/}
  Phase 2: Charger Plug    (30s)   ${PLUG_POLICY##*/outputs/}
  Phase 3: Liquid Pour     (30s)   ${POUR_POLICY##*/outputs/}

  HOME pose:     ${HOME_JSON}
  Eval datasets: local/so101_*_eval (auto-saved for review)
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

# --- Helper: deploy one policy autonomously -------------------------------
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

  # Auto-clean prior eval dataset for this phase (eval data is throwaway).
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

# --- Helper: drive to a specific task's start pose ------------------------
# Each ACT policy was trained from a slightly different starting pose, so we
# drive to the matching per-task start before invoking that phase's policy.
# `task` is one of: pick | plug | pour | "" (canonical home).
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

# --- Run the autonomous sequence ------------------------------------------
echo ""
echo "[start] $(date '+%H:%M:%S') — beginning autonomous sequence"

go_home pick

deploy_phase "Pick & Place" "${PICK_POLICY}" \
  "local/so101_pick_v1_autorun" \
  "Pick the cube and place it on the target." \
  25

go_home plug

deploy_phase "Charger Plug" "${PLUG_POLICY}" \
  "local/so101_plug_v1_autorun" \
  "Plug the charger connector into the socket." \
  30

go_home pour

deploy_phase "Liquid Pour" "${POUR_POLICY}" \
  "local/so101_pour_v1_autorun" \
  "Pour the contents of the bottle into the cup." \
  30

go_home

echo ""
echo "=========================================================="
echo "  AUTONOMOUS DEMO COMPLETE — $(date '+%H:%M:%S')"
echo "=========================================================="
echo "  Review the recorded runs:"
echo "    - local/so101_pick_v1_autorun"
echo "    - local/so101_plug_v1_autorun"
echo "    - local/so101_pour_v1_autorun"
echo ""
echo "  Each phase saved 1 episode with both camera views and the policy"
echo "  actions. Use lerobot-replay to play back any phase frame-by-frame."
echo "=========================================================="
