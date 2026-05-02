#!/usr/bin/env bash
# Task 1 — TRAIN ACT policy on the recorded demos.
#
# CPU-only on macOS 26 (~2.7 hours for 8k steps with 50 demos — aggressive
# 8h-budget run with smaller transformer dim_model=256).
# For full quality, run --resume after to add more steps.
# Laptop plugged in, lid open, on a hard surface.
#
# Run interactively:        ./scripts/task1_train.sh
# Skip y/N prompt:           ./scripts/task1_train.sh --yes
# Resume from last ckpt:     ./scripts/task1_train.sh --resume
# Resume + skip prompt:      ./scripts/task1_train.sh --resume --yes

set -e
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/task1_env.sh"

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
  TASK 1 TRAINING — ACT policy (aggressive 8h budget)
==========================================================
  Dataset:     ${TASK1_REPO}  (${TASK1_NUM_EPISODES} episodes)
  Output dir:  ${TASK1_OUTPUT_DIR}
  Device:      ${TASK1_DEVICE}    (MPS unavailable on macOS 26)
  Batch size:  ${TASK1_BATCH_SIZE}
  Steps:       ${TASK1_STEPS}     (aggressive; was 50000 default)
  Save freq:   every ${TASK1_SAVE_FREQ} steps
  Chunk size:  ${TASK1_CHUNK_SIZE}
  Model size:  dim_model=${TASK1_DIM_MODEL}, n_heads=${TASK1_N_HEADS}, dim_ff=${TASK1_DIM_FEEDFORWARD}
               (~13M params, vs default 52M)

  Estimated wall-clock: ~2.7 hours @ ~1.2s/step.
  Expected first-eval grasp success: 35-55%
  (vs ~70-80% with the full 50k-step + 52M-param run)

  Output policy: ${TASK1_OUTPUT_DIR}/checkpoints/last/pretrained_model

  Pre-flight checklist:
    [ ] ${TASK1_NUM_EPISODES} episodes recorded
    [ ] Laptop plugged in
    [ ] Closed all heavy apps (browser tabs, IDEs, simulators)
    [ ] On a hard surface (no fan blockage)
==========================================================
INFO

if [[ "${SKIP_PROMPT}" -eq 0 ]]; then
  read -r -p "Start training? Will run ${TASK1_STEPS} steps on ${TASK1_DEVICE}. [y/N] " ans
  [[ "${ans}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

cd "${REPO_ROOT}"
exec "${LEROBOT}/lerobot-train" \
    --dataset.repo_id="${TASK1_REPO}" \
    --dataset.root="${TASK1_ROOT}" \
    --policy.type=act \
    --policy.device=${TASK1_DEVICE} \
    --policy.push_to_hub=false \
    --policy.dim_model=${TASK1_DIM_MODEL} \
    --policy.n_heads=${TASK1_N_HEADS} \
    --policy.dim_feedforward=${TASK1_DIM_FEEDFORWARD} \
    --policy.chunk_size=${TASK1_CHUNK_SIZE} \
    --policy.n_action_steps=${TASK1_CHUNK_SIZE} \
    --policy.use_vae=true \
    --policy.kl_weight=10.0 \
    --policy.optimizer_lr=1e-5 \
    --batch_size=${TASK1_BATCH_SIZE} \
    --steps=${TASK1_STEPS} \
    --save_freq=${TASK1_SAVE_FREQ} \
    --log_freq=${TASK1_LOG_FREQ} \
    --output_dir="${TASK1_OUTPUT_DIR}" \
    --job_name="${TASK1_RUN_NAME}" \
    --wandb.enable=false \
    ${EXTRA_FLAGS}
