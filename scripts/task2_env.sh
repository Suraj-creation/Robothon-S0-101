#!/usr/bin/env bash
# Single source of truth for Task 2 (Charger Plugging) parameters.
# Sourced by every task2_*.sh script. Edit values here, not in each script.

# --- Hardware (verified May 1, 2026) ---
export FOLLOWER_PORT="/dev/tty.usbmodem5B141124491"
export LEADER_PORT="/dev/tty.usbmodem5B140318771"
export ROBOT_ID="so101_follower_main"
export TELEOP_ID="so101_leader_main"

# --- Cameras (same as Task 1, must NOT have moved) ---
export OVERHEAD_INDEX=0    # top-down view of worktop
export WRIST_INDEX=1       # mounted on follower wrist (CRITICAL for insertion)
export CAM_W=640
export CAM_H=480
export CAM_FPS=30

# --- Dataset / policy identity ---
export HF_USER="local"
export TASK2_REPO="${HF_USER}/so101_plug_v1"
export TASK2_EVAL_REPO="${HF_USER}/so101_plug_v1_eval"
export TASK2_RUN_NAME="act_plug_v1"
export TASK2_OUTPUT_DIR="outputs/${TASK2_RUN_NAME}"
# Explicit local dataset root. Required by LeRobot's resume() API which
# refuses to default to the HF Hub snapshot cache (read-only / revision-safe).
# Same path as before, just made explicit.
export TASK2_ROOT="${HOME}/.cache/huggingface/lerobot/${TASK2_REPO}"
export TASK2_EVAL_ROOT="${HOME}/.cache/huggingface/lerobot/${TASK2_EVAL_REPO}"

# --- Demo collection parameters ---
# 40 episodes — minimum viable for precision insertion with 2 cameras.
# Honest realism: at 40 demos expect ~40-55% insertion success at first eval.
# If eval shows <60%, plan to record a top-up of 15-20 targeted demos focused
# on the failure cases, then retrain. Original recommendation was 90 episodes
# (~75-85% success). Set to 30 only if you accept ~20-35% first-pass success.
# Use ":=" so the caller can override on the command line, e.g.
#   TASK2_NUM_EPISODES=42 ./scripts/task2_record.sh --resume
: "${TASK2_NUM_EPISODES:=40}"
: "${TASK2_EPISODE_TIME_S:=25}"
: "${TASK2_RESET_TIME_S:=10}"
export TASK2_NUM_EPISODES TASK2_EPISODE_TIME_S TASK2_RESET_TIME_S
export TASK2_TASK_TEXT="Grasp the charger connector and plug it into the socket."

# --- Training parameters (CPU-only on macOS 26) ---
# AGGRESSIVE 8h BUDGET (calibrated against observed 1.76s/step rate).
#
# Model trims (same as Task 1):
#   dim_model=256, n_heads=4, dim_feedforward=1600 (~30-40% step speedup)
#
# At ~1.3s/step with smaller model + chunk_size=80 (still long for insertion):
#   plug: 11000 steps × 1.3s = ~4.0h
# Steps/demo = 216. Plug is the hardest task; gets the biggest share of
# the 8h budget. Expect 15-30% insertion success at first eval — top up
# with --resume if results disappoint (this task benefits the most from
# additional training).
# chunk_size=80 stays — insertion is a long contiguous motion.
# kl_weight=20 stays — reduces mode collapse on near-identical demos.
export TASK2_DEVICE=cpu
export TASK2_BATCH_SIZE=4
export TASK2_STEPS=11000
export TASK2_SAVE_FREQ=2000
export TASK2_LOG_FREQ=200
export TASK2_CHUNK_SIZE=80
export TASK2_KL_WEIGHT=20.0
export TASK2_DIM_MODEL=256
export TASK2_N_HEADS=4
export TASK2_DIM_FEEDFORWARD=1600

# --- Safety: keep the same step limit that worked smoothly in Task 1 ---
export MAX_RELATIVE_TARGET=20

# --- Camera spec for --robot.cameras ---
export CAMERAS_SPEC="{ overhead: { type: opencv, index_or_path: ${OVERHEAD_INDEX}, width: ${CAM_W}, height: ${CAM_H}, fps: ${CAM_FPS} }, wrist: { type: opencv, index_or_path: ${WRIST_INDEX}, width: ${CAM_W}, height: ${CAM_H}, fps: ${CAM_FPS} } }"

# Helper: project root + lerobot binary
export REPO_ROOT="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}" )/.." &> /dev/null && pwd )"
export LEROBOT="${REPO_ROOT}/.conda/bin"

# CRITICAL: prepend conda env bin to PATH so subprocesses (rerun viewer) find it.
export PATH="${LEROBOT}:${PATH}"
