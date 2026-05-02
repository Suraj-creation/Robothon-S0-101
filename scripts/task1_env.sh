#!/usr/bin/env bash
# Single source of truth for Task 1 (Pick & Place) parameters.
# Sourced by every task1_*.sh script. Edit values here, not in each script.

# --- Hardware (verified May 1, 2026) ---
export FOLLOWER_PORT="/dev/tty.usbmodem5B141124491"
export LEADER_PORT="/dev/tty.usbmodem5B140318771"
export ROBOT_ID="so101_follower_main"
export TELEOP_ID="so101_leader_main"

# --- Cameras (verified by frame inspection May 1, 2026) ---
export OVERHEAD_INDEX=0    # top-down view of worktop
export WRIST_INDEX=1       # mounted on follower wrist
export CAM_W=640
export CAM_H=480
export CAM_FPS=30

# --- Dataset / policy identity ---
# Use a local-only namespace; we don't push to HF unless you log in.
export HF_USER="local"
export TASK1_REPO="${HF_USER}/so101_pick_v1"
export TASK1_EVAL_REPO="${HF_USER}/so101_pick_v1_eval"
export TASK1_RUN_NAME="act_pick_v1"
export TASK1_OUTPUT_DIR="outputs/${TASK1_RUN_NAME}"
# Explicit local dataset root. Required by LeRobot's resume() API which
# refuses to default to the HF Hub snapshot cache.
export TASK1_ROOT="${HOME}/.cache/huggingface/lerobot/${TASK1_REPO}"
export TASK1_EVAL_ROOT="${HOME}/.cache/huggingface/lerobot/${TASK1_EVAL_REPO}"

# --- Demo collection parameters ---
export TASK1_NUM_EPISODES=50
export TASK1_EPISODE_TIME_S=20
export TASK1_RESET_TIME_S=8
export TASK1_TASK_TEXT="Pick the cube and place it in the green target zone."

# --- Training parameters (CPU-only on macOS 26) ---
# AGGRESSIVE 8h BUDGET (calibrated against observed 1.76s/step rate).
#
# Model trims:
#   dim_model=256 (vs default 512) — 4x fewer transformer params (~13M vs ~52M)
#   n_heads=4     (vs default 8)   — must divide dim_model
#   dim_feedforward=1600 (vs default 3200) — proportional to dim_model
#   These together give ~30-40% per-step speedup and (often) BETTER
#   generalization with small datasets (less overfitting).
#
# At ~1.2s/step with the smaller model:
#   pick: 8000 steps × 1.2s = ~2.7h
# Steps/demo = 160. Low but workable. Top up with --resume if needed.
export TASK1_DEVICE=cpu
export TASK1_BATCH_SIZE=4
export TASK1_STEPS=8000
export TASK1_SAVE_FREQ=2000
export TASK1_LOG_FREQ=200
export TASK1_CHUNK_SIZE=50
export TASK1_DIM_MODEL=256
export TASK1_N_HEADS=4
export TASK1_DIM_FEEDFORWARD=1600

# --- Safety: how big a step the follower can take per servo update ---
# At 30 fps, max joint speed = MAX_RELATIVE_TARGET * 30 deg/sec.
#   10  ->  300 deg/s  (very safe but visibly laggy when leader moves fast)
#   20  ->  600 deg/s  (smooth tracking, still safe with calibrated arms)  <-- chosen
#   25  ->  750 deg/s  (max recommended; only if 20 still feels laggy)
# Do NOT exceed 25 — sudden bus glitches at higher steps can damage the gear train.
export MAX_RELATIVE_TARGET=20

# --- Camera spec for --robot.cameras (single-line YAML literal) ---
export CAMERAS_SPEC="{ overhead: { type: opencv, index_or_path: ${OVERHEAD_INDEX}, width: ${CAM_W}, height: ${CAM_H}, fps: ${CAM_FPS} }, wrist: { type: opencv, index_or_path: ${WRIST_INDEX}, width: ${CAM_W}, height: ${CAM_H}, fps: ${CAM_FPS} } }"

# Helper: project root + lerobot binary
export REPO_ROOT="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}" )/.." &> /dev/null && pwd )"
export LEROBOT="${REPO_ROOT}/.conda/bin"

# CRITICAL: prepend conda env bin to PATH so subprocesses spawned by lerobot
# (specifically the `rerun` viewer launched by rr.spawn()) can find the binary.
# Without this, lerobot-record dies with "Failed to find Rerun Viewer executable".
export PATH="${LEROBOT}:${PATH}"
