#!/usr/bin/env bash
# Task 2 — TRAIN ACT policy on the recorded plug demos.
#
# CPU-only on macOS 26 (~4 hours for 11k steps with 51 demos — aggressive
# 8h-budget run with smaller transformer dim_model=256).
# Plug is the hardest task; gets the biggest share of the 8h budget.
# For full quality, run --resume to add steps later (this task benefits
# the most from additional training).
#   - chunk_size=80 — insertion is a long contiguous motion
#   - kl_weight=20 — reduces mode collapse on near-identical demos
#   - dim_model=256 — half the default for ~30-40% faster steps
#
# Run interactively:        ./scripts/task2_train.sh
# Skip y/N prompt:           ./scripts/task2_train.sh --yes
# Resume from last ckpt:     ./scripts/task2_train.sh --resume
# Resume + skip prompt:      ./scripts/task2_train.sh --resume --yes

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task2_env.sh"

EXTRA_FLAGS=""
SKIP_PROMPT=0
for arg in "$@"; do
  case "$arg" in
    --resume) EXTRA_FLAGS="--resume=true" ;;
    --yes|-y) SKIP_PROMPT=1 ;;
  esac
done

cat <<INFO
==========================================================
  TASK 2 TRAINING — ACT policy (charger plug — aggressive 8h budget)
==========================================================
  Dataset:     ${TASK2_REPO}  (${TASK2_NUM_EPISODES} episodes)
  Output dir:  ${TASK2_OUTPUT_DIR}
  Device:      ${TASK2_DEVICE}    (MPS unavailable on macOS 26)
  Batch size:  ${TASK2_BATCH_SIZE}
  Steps:       ${TASK2_STEPS}     (aggressive; was 60000 default)
  Save freq:   every ${TASK2_SAVE_FREQ} steps
  Chunk size:  ${TASK2_CHUNK_SIZE}    (80 — long insertion motion)
  KL weight:   ${TASK2_KL_WEIGHT}     (20 — reduce mode collapse)
  Model size:  dim_model=${TASK2_DIM_MODEL}, n_heads=${TASK2_N_HEADS}, dim_ff=${TASK2_DIM_FEEDFORWARD}
               (~13M params, vs default 52M)

  Estimated wall-clock: ~4 hours @ ~1.3s/step.
  Expected first-eval insertion success: 15-30%
  (vs ~50% with the full 60k-step + 52M-param run)
  This task benefits the MOST from --resume top-up training.

  Output policy: ${TASK2_OUTPUT_DIR}/checkpoints/last/pretrained_model

  Pre-flight checklist:
    [ ] ${TASK2_NUM_EPISODES} episodes recorded
    [ ] Laptop plugged in
    [ ] Closed all heavy apps
    [ ] On a hard surface (no fan blockage)
==========================================================
INFO

if [[ "${SKIP_PROMPT}" -eq 0 ]]; then
  read -r -p "Start training? Will run ${TASK2_STEPS} steps on ${TASK2_DEVICE}. [y/N] " ans
  [[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

cd "${REPO_ROOT}"
exec "${LEROBOT}/lerobot-train" \
    --dataset.repo_id="${TASK2_REPO}" \
    --dataset.root="${TASK2_ROOT}" \
    --policy.type=act \
    --policy.device=${TASK2_DEVICE} \
    --policy.push_to_hub=false \
    --policy.dim_model=${TASK2_DIM_MODEL} \
    --policy.n_heads=${TASK2_N_HEADS} \
    --policy.dim_feedforward=${TASK2_DIM_FEEDFORWARD} \
    --policy.chunk_size=${TASK2_CHUNK_SIZE} \
    --policy.n_action_steps=${TASK2_CHUNK_SIZE} \
    --policy.use_vae=true \
    --policy.kl_weight=${TASK2_KL_WEIGHT} \
    --policy.optimizer_lr=1e-5 \
    --batch_size=${TASK2_BATCH_SIZE} \
    --steps=${TASK2_STEPS} \
    --save_freq=${TASK2_SAVE_FREQ} \
    --log_freq=${TASK2_LOG_FREQ} \
    --output_dir="${TASK2_OUTPUT_DIR}" \
    --job_name="${TASK2_RUN_NAME}" \
    --wandb.enable=false \
    ${EXTRA_FLAGS}
