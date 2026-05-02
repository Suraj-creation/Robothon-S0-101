#!/usr/bin/env bash
# Single source of truth for Task 3 (Liquid Pouring) parameters.
# Sourced by every task3_*.sh script. Edit values here, not in each script.

# --- Hardware (verified May 1, 2026) ---
export FOLLOWER_PORT="/dev/tty.usbmodem5B141124491"
export LEADER_PORT="/dev/tty.usbmodem5B140318771"
export ROBOT_ID="so101_follower_main"
export TELEOP_ID="so101_leader_main"

# --- Cameras (same physical setup as Tasks 1 & 2 — must NOT have moved) ---
export OVERHEAD_INDEX=0    # top-down view of worktop (sees bottle + cup + spill)
export WRIST_INDEX=1       # mounted on follower wrist (sees pour stream into cup)
export CAM_W=640
export CAM_H=480
export CAM_FPS=30

# --- Dataset / policy identity ---
export HF_USER="local"
export TASK3_REPO="${HF_USER}/so101_pour_v1"
export TASK3_EVAL_REPO="${HF_USER}/so101_pour_v1_eval"
export TASK3_RUN_NAME="act_pour_v1"
export TASK3_OUTPUT_DIR="outputs/${TASK3_RUN_NAME}"
# Explicit local dataset roots — required by LeRobotDataset.resume() in 0.5.x.
export TASK3_ROOT="${HOME}/.cache/huggingface/lerobot/${TASK3_REPO}"
export TASK3_EVAL_ROOT="${HOME}/.cache/huggingface/lerobot/${TASK3_EVAL_REPO}"

# --- Demo collection parameters ---
# 35 episodes — pouring is medium difficulty. Easier than charger insertion
# (no mm-level alignment) but harder than pick-and-place (long action sequence,
# wrist_roll precision matters). 35 demos ≈ 50-65% pour success at first eval
# with consistent setup. 50+ if you want >70%.
#
# Episode budget (25s):
#   3s  grasp the bottle
#   4s  lift + transport over the cup
#   2s  align wrist above cup
#   5s  tilt and hold pour
#   2s  return to upright
#   3s  place bottle back to start
#   6s  buffer for slow movements (pour MUST be slow)
#
# Override the count from the command line, e.g.
#   TASK3_NUM_EPISODES=10 ./scripts/task3_record.sh
: "${TASK3_NUM_EPISODES:=35}"
: "${TASK3_EPISODE_TIME_S:=25}"
: "${TASK3_RESET_TIME_S:=10}"
export TASK3_NUM_EPISODES TASK3_EPISODE_TIME_S TASK3_RESET_TIME_S
export TASK3_TASK_TEXT="Grasp the bottle, position it above the cup, and pour the contents."

# --- Training parameters (CPU-only on macOS 26) ---
# AGGRESSIVE 8h BUDGET (calibrated against observed 1.76s/step rate).
#
# Model trims (same as Tasks 1 & 2):
#   dim_model=256, n_heads=4, dim_feedforward=1600 (~30-40% step speedup)
#
# At ~1.3s/step with smaller model + chunk_size=80:
#   pour: 5500 steps × 1.3s = ~2.0h
# Steps/demo = 157 (35 demos). Expect 30-45% pour success at first eval.
# chunk_size=80 stays — pouring is a long contiguous motion.
# kl_weight=15 stays — preserves tilt-phase variation.
export TASK3_DEVICE=cpu
export TASK3_BATCH_SIZE=4
export TASK3_STEPS=5500
export TASK3_SAVE_FREQ=1500
export TASK3_LOG_FREQ=200
export TASK3_CHUNK_SIZE=80
export TASK3_KL_WEIGHT=15.0
export TASK3_DIM_MODEL=256
export TASK3_N_HEADS=4
export TASK3_DIM_FEEDFORWARD=1600

# --- Safety: keep the same step limit that worked in Tasks 1 & 2 ---
export MAX_RELATIVE_TARGET=20

# --- Camera spec for --robot.cameras ---
export CAMERAS_SPEC="{ overhead: { type: opencv, index_or_path: ${OVERHEAD_INDEX}, width: ${CAM_W}, height: ${CAM_H}, fps: ${CAM_FPS} }, wrist: { type: opencv, index_or_path: ${WRIST_INDEX}, width: ${CAM_W}, height: ${CAM_H}, fps: ${CAM_FPS} } }"

# Helper: project root + lerobot binary
export REPO_ROOT="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}" )/.." &> /dev/null && pwd )"
export LEROBOT="${REPO_ROOT}/.conda/bin"

# CRITICAL: prepend conda env bin to PATH so subprocesses (rerun viewer) find it.
export PATH="${LEROBOT}:${PATH}"
