#!/usr/bin/env bash
# ONE-SHOT UNATTENDED TRAINING — all three policies, sequentially, on CPU.
#
# Total wall-clock target: ~8.7 hours (calibrated against observed 1.76s/step
# rate for default ACT, plus a smaller dim_model=256 transformer for ~30%
# step speedup → expected ~1.2-1.3s/step).
#
# Per-task budget (smaller transformer: dim_model=256, n_heads=4):
#   Task 1 (pick):  8,000 steps @ ~2.7h  =>  ~35-55% grasp success
#   Task 2 (plug): 11,000 steps @ ~4.0h  =>  ~15-30% insertion success
#   Task 3 (pour):  5,500 steps @ ~2.0h  =>  ~30-45% pour success
#                                ----------
#   Total:         24,500 steps @ ~8.7h
#
# Each phase logs to outputs/training_logs/<phase>.log so you can tail
# any task while the whole script runs unattended.
#
# What it does:
#   1) Verifies all three datasets exist
#   2) Trains pick → plug → pour in sequence
#   3) Even if one phase fails, the others still complete (each is run with
#      `set +e` around the lerobot-train call). Failures are logged.
#   4) Prints a summary at the end with elapsed time per phase.
#
# Run unattended (recommended for overnight):
#   nohup ./scripts/train_all.sh > train_all.log 2>&1 &
#   tail -f train_all.log
#
# Run in the foreground (lid open, charger in):
#   ./scripts/train_all.sh
#
# Resume mode (skips already-completed phases — based on outputs/<run>/checkpoints/last/):
#   ./scripts/train_all.sh --resume
#
# IMPORTANT before running:
#   - Plug in the laptop charger
#   - Lid open, on a HARD surface (M4 Air is fan-less; soft surfaces overheat it)
#   - Quit Cursor/Chrome/Slack/anything heavy
#   - Disable Time Machine and any background backup tools

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

# Optional resume from existing checkpoints
RESUME_FLAG=""
if [[ "$1" == "--resume" ]]; then
  RESUME_FLAG="--resume"
  echo "==> RESUME mode: any completed phases will be skipped, partial ones resumed."
fi

LOG_DIR="${REPO_ROOT}/outputs/training_logs"
mkdir -p "${LOG_DIR}"

# --- Pre-flight ----------------------------------------------------------
PICK_ROOT="${HOME}/.cache/huggingface/lerobot/local/so101_pick_v1"
PLUG_ROOT="${HOME}/.cache/huggingface/lerobot/local/so101_plug_v1"
POUR_ROOT="${HOME}/.cache/huggingface/lerobot/local/so101_pour_v1"

missing=0
for d in "${PICK_ROOT}" "${PLUG_ROOT}" "${POUR_ROOT}"; do
  if [[ ! -d "${d}" ]]; then
    echo "  [missing dataset] ${d}"
    missing=1
  fi
done
if [[ "${missing}" -eq 1 ]]; then
  echo ""
  echo "ERROR: one or more datasets are missing. Record them first with"
  echo "  ./scripts/task1_record.sh ; ./scripts/task2_record.sh ; ./scripts/task3_record.sh"
  exit 1
fi

# --- Banner --------------------------------------------------------------
START_TS=$(date +%s)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

cat <<INFO
==========================================================
  ROBOTHON ONE-SHOT TRAINING — pick + plug + pour
==========================================================
  Started:        ${START_HUMAN}
  Estimated end:  ~8.7 hours from now (so ~$(date -v+9H '+%H:%M' 2>/dev/null || date -d '+9 hours' '+%H:%M' 2>/dev/null || echo 'morning'))
  Logs:           ${LOG_DIR}/
  Mode:           ${RESUME_FLAG:+RESUME}${RESUME_FLAG:-FRESH}

  Phase budget (CPU on M4 Air, smaller dim_model=256 transformer):
    1. pick    8,000 steps  ~2.7h  =>  outputs/act_pick_v1/
    2. plug   11,000 steps  ~4.0h  =>  outputs/act_plug_v1/
    3. pour    5,500 steps  ~2.0h  =>  outputs/act_pour_v1/

  Note: the harmless "objc[xxx]: Class AVF... is implemented in both"
  warnings are macOS dyld noise from torchcodec/PyAV duplicates. They
  are NOT errors. Training proceeds normally past them.

  Tail any phase live in another terminal:
    tail -f ${LOG_DIR}/pick.log
    tail -f ${LOG_DIR}/plug.log
    tail -f ${LOG_DIR}/pour.log
==========================================================
INFO

# --- Helper: run one training phase with logging + failure isolation ----
run_phase() {
  local name="$1"
  local script="$2"
  local log="${LOG_DIR}/${name}.log"

  echo ""
  echo "----------------------------------------------------------"
  echo "  PHASE: ${name}  (started $(date '+%H:%M:%S'))"
  echo "  Log:   ${log}"
  echo "----------------------------------------------------------"

  local phase_start=$(date +%s)

  # Don't let a phase failure abort the others — record and move on.
  set +e
  if [[ -n "${RESUME_FLAG}" ]]; then
    "${script}" --yes --resume 2>&1 | tee "${log}"
  else
    "${script}" --yes 2>&1 | tee "${log}"
  fi
  local rc="${PIPESTATUS[0]}"
  set -e

  local phase_end=$(date +%s)
  local elapsed=$((phase_end - phase_start))
  local h=$((elapsed / 3600))
  local m=$(((elapsed % 3600) / 60))

  if [[ "${rc}" -eq 0 ]]; then
    echo "[ok]   ${name}: completed in ${h}h${m}m"
    PHASE_RESULTS+=("${name}: OK (${h}h${m}m)")
  else
    echo "[FAIL] ${name}: exit code ${rc} after ${h}h${m}m"
    echo "       see ${log} for details"
    PHASE_RESULTS+=("${name}: FAILED rc=${rc} (${h}h${m}m)")
  fi
}

declare -a PHASE_RESULTS=()

run_phase "pick" "${SCRIPT_DIR}/task1_train.sh"
run_phase "plug" "${SCRIPT_DIR}/task2_train.sh"
run_phase "pour" "${SCRIPT_DIR}/task3_train.sh"

# --- Summary -------------------------------------------------------------
END_TS=$(date +%s)
TOTAL=$((END_TS - START_TS))
TOT_H=$((TOTAL / 3600))
TOT_M=$(((TOTAL % 3600) / 60))

echo ""
echo "=========================================================="
echo "  TRAINING COMPLETE — $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================================="
echo "  Total elapsed: ${TOT_H}h ${TOT_M}m"
for r in "${PHASE_RESULTS[@]}"; do
  echo "    ${r}"
done
echo ""
echo "  Trained checkpoints:"
for run in act_pick_v1 act_plug_v1 act_pour_v1; do
  ckpt="${REPO_ROOT}/outputs/${run}/checkpoints/last/pretrained_model"
  if [[ -d "${ckpt}" ]]; then
    echo "    [ok]      ${ckpt}"
  else
    echo "    [missing] ${ckpt}"
  fi
done
echo ""
echo "  Next steps:"
echo "    1. ./scripts/task1_eval.sh   (verify Task 1 in isolation)"
echo "    2. ./scripts/task2_eval.sh   (verify Task 2)"
echo "    3. ./scripts/task3_eval.sh   (verify Task 3)"
echo "    4. ./scripts/run_full_demo.sh   (full autonomous Pick → Plug → Pour)"
echo ""
echo "  If any task underperforms (<50% success), top it up with:"
echo "    ./scripts/taskN_train.sh --resume --yes"
echo "  Each --resume adds however many --steps you set in taskN_env.sh."
echo "=========================================================="
