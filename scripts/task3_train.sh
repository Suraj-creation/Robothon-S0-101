#!/usr/bin/env bash
# Task 3 — TRAIN ACT policy on the recorded pouring demos.
#
# CPU-only on macOS 26 (~2 hours for 5.5k steps with 35 demos — aggressive
# 8h-budget run with smaller transformer dim_model=256).
# For full quality, run --resume to add steps later.
#   - chunk_size=80    — pouring is one long contiguous motion
#   - kl_weight=15     — preserves tilt-phase variation
#   - dim_model=256    — half the default for ~30-40% faster steps
#
# Run interactively:        ./scripts/task3_train.sh
# Skip y/N prompt:           ./scripts/task3_train.sh --yes
# Resume from last ckpt:     ./scripts/task3_train.sh --resume
# Resume + skip prompt:      ./scripts/task3_train.sh --resume --yes

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task3_env.sh"

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
  TASK 3 TRAINING — ACT policy (liquid pouring — aggressive 8h budget)
==========================================================
  Dataset:     ${TASK3_REPO}  (${TASK3_NUM_EPISODES} episodes)
  Output dir:  ${TASK3_OUTPUT_DIR}
  Device:      ${TASK3_DEVICE}    (MPS unavailable on macOS 26)
  Batch size:  ${TASK3_BATCH_SIZE}
  Steps:       ${TASK3_STEPS}     (aggressive; was 50000 default)
  Save freq:   every ${TASK3_SAVE_FREQ} steps
  Chunk size:  ${TASK3_CHUNK_SIZE}    (80 — long pour motion)
  KL weight:   ${TASK3_KL_WEIGHT}     (15 — preserve tilt-phase variation)
  Model size:  dim_model=${TASK3_DIM_MODEL}, n_heads=${TASK3_N_HEADS}, dim_ff=${TASK3_DIM_FEEDFORWARD}
               (~13M params, vs default 52M)

  Estimated wall-clock: ~2 hours @ ~1.3s/step.
  Expected first-eval pour success: 30-45%
  (vs ~70% with the full 50k-step + 52M-param run)

  Output policy: ${TASK3_OUTPUT_DIR}/checkpoints/last/pretrained_model

  Pre-flight checklist:
    [ ] ${TASK3_NUM_EPISODES} episodes recorded
    [ ] Laptop plugged in
    [ ] Closed all heavy apps
    [ ] On a hard surface (no fan blockage)
==========================================================
INFO

if [[ "${SKIP_PROMPT}" -eq 0 ]]; then
  read -r -p "Start training? Will run ${TASK3_STEPS} steps on ${TASK3_DEVICE}. [y/N] " ans
  [[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

cd "${REPO_ROOT}"
exec "${LEROBOT}/lerobot-train" \
    --dataset.repo_id="${TASK3_REPO}" \
    --dataset.root="${TASK3_ROOT}" \
    --policy.type=act \
    --policy.device=${TASK3_DEVICE} \
    --policy.push_to_hub=false \
    --policy.dim_model=${TASK3_DIM_MODEL} \
    --policy.n_heads=${TASK3_N_HEADS} \
    --policy.dim_feedforward=${TASK3_DIM_FEEDFORWARD} \
    --policy.chunk_size=${TASK3_CHUNK_SIZE} \
    --policy.n_action_steps=${TASK3_CHUNK_SIZE} \
    --policy.use_vae=true \
    --policy.kl_weight=${TASK3_KL_WEIGHT} \
    --policy.optimizer_lr=1e-5 \
    --batch_size=${TASK3_BATCH_SIZE} \
    --steps=${TASK3_STEPS} \
    --save_freq=${TASK3_SAVE_FREQ} \
    --log_freq=${TASK3_LOG_FREQ} \
    --output_dir="${TASK3_OUTPUT_DIR}" \
    --job_name="${TASK3_RUN_NAME}" \
    --wandb.enable=false \
    ${EXTRA_FLAGS}
