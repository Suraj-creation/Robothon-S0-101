#!/usr/bin/env python3
"""SO-101 full Robothon autonomous demo: pick → plug → pour, IN-PROCESS.

This is the advanced/optional in-process sequencer. It opens the robot and
both cameras ONCE, then loads each ACT policy in turn and runs it. Compared
to the bash sequencer (run_full_demo.sh), this version:

    + has tighter phase transitions (no camera open/close churn)
    + can do a "go home" via direct joint commands between phases
    - has more code paths to debug (preprocessor pipeline, action conversion)

Use run_full_demo.sh as the primary, this script for fine-tuning later.

Pre-reqs:
    1. All three policies trained:
        outputs/act_pick_v1/checkpoints/last/pretrained_model
        outputs/act_plug_v1/checkpoints/last/pretrained_model
        outputs/act_pour_v1/checkpoints/last/pretrained_model
    2. HOME pose captured (scripts/home_pose.json):
        .conda/bin/python scripts/capture_home.py
    3. Each task evaluated in isolation and works.

Run:
    .conda/bin/python scripts/run_full_demo.py
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Any

import cv2  # noqa: F401  forces opencv to load before torch on macOS
import numpy as np
import torch

# lerobot 0.5.1 verified import paths
from lerobot.cameras.opencv import OpenCVCamera, OpenCVCameraConfig
from lerobot.configs.policies import PreTrainedConfig
from lerobot.datasets.lerobot_dataset import LeRobotDataset
from lerobot.policies.factory import make_policy, make_pre_post_processors
from lerobot.policies.utils import make_robot_action
from lerobot.robots.so_follower import SO101Follower, SO101FollowerConfig
from lerobot.utils.control_utils import predict_action
from lerobot.utils.device_utils import get_safe_torch_device

ROOT = Path(__file__).resolve().parent.parent
HOME_JSON = ROOT / "scripts" / "home_pose.json"

# --- Hardware (verified May 1, 2026) ------------------------------------
FOLLOWER_PORT = "/dev/tty.usbmodem5B141124491"
ROBOT_ID = "so101_follower_main"

# --- Camera indices (must match what was used during recording) ---------
# Tasks 1, 2, 3 were all recorded with these indices. See scripts/task*_env.sh.
OVERHEAD_INDEX = 0  # Android phone webcam, top-down
WRIST_INDEX = 1     # USB UVC on follower wrist
CAM_W, CAM_H, CAM_FPS = 640, 480, 30

# --- Per-phase config ---------------------------------------------------
PHASES = [
    {
        "name": "pick",
        "policy_dir": ROOT / "outputs/act_pick_v1/checkpoints/last/pretrained_model",
        "dataset_dir": Path.home() / ".cache/huggingface/lerobot/local/so101_pick_v1",
        "task_text": "Pick the cube and place it on the target.",
        "max_seconds": 25.0,
    },
    {
        "name": "plug",
        "policy_dir": ROOT / "outputs/act_plug_v1/checkpoints/last/pretrained_model",
        "dataset_dir": Path.home() / ".cache/huggingface/lerobot/local/so101_plug_v1",
        "task_text": "Plug the charger connector into the socket.",
        "max_seconds": 30.0,
    },
    {
        "name": "pour",
        "policy_dir": ROOT / "outputs/act_pour_v1/checkpoints/last/pretrained_model",
        "dataset_dir": Path.home() / ".cache/huggingface/lerobot/local/so101_pour_v1",
        "task_text": "Pour the contents of the bottle into the cup.",
        "max_seconds": 30.0,
    },
]

# CPU only — torch.backends.mps.is_available() returns False on macOS 26.
DEVICE = "cpu"

JOINTS = [
    "shoulder_pan.pos",
    "shoulder_lift.pos",
    "elbow_flex.pos",
    "wrist_flex.pos",
    "wrist_roll.pos",
    "gripper.pos",
]


def load_home_data() -> dict[str, Any]:
    if not HOME_JSON.exists():
        raise FileNotFoundError(
            f"{HOME_JSON} not found. Run: .conda/bin/python scripts/capture_home.py"
        )
    return json.loads(HOME_JSON.read_text())


def get_task_home(home_data: dict[str, Any], task_name: str) -> dict[str, float]:
    """Return the natural starting pose for a specific task.
    Falls back to canonical_home if the per-task pose isn't available."""
    return home_data["per_task_starts"].get(task_name, home_data["canonical_home"])


def go_home(robot: SO101Follower, home: dict[str, float], duration: float = 3.0,
            hz: int = 30) -> None:
    """Linearly interpolate from current to HOME over `duration` seconds."""
    obs = robot.get_observation()
    current = {k: float(obs[k]) for k in home}
    n_steps = max(1, int(duration * hz))
    period = 1.0 / hz
    for i in range(1, n_steps + 1):
        alpha = i / n_steps
        cmd = {k: current[k] + alpha * (home[k] - current[k]) for k in home}
        robot.send_action(cmd)
        time.sleep(period)
    robot.send_action(home)
    time.sleep(0.5)


def load_policy_and_processors(phase: dict[str, Any]) -> tuple[Any, Any, Any]:
    """Load an ACT policy + its preprocessor/postprocessor pipelines.

    The processors are essential — they handle image normalization, state
    normalization, batch dimension, device transfer, and unnormalization
    of action outputs. Without them the policy produces garbage.
    """
    policy_dir: Path = phase["policy_dir"]
    dataset_dir: Path = phase["dataset_dir"]

    if not policy_dir.exists():
        raise FileNotFoundError(
            f"Policy not found at {policy_dir}. Train it with task*_train.sh first."
        )

    # Load policy config from checkpoint
    cfg = PreTrainedConfig.from_pretrained(policy_dir)
    cfg.device = DEVICE  # force CPU on macOS 26

    # We need dataset metadata + stats so preprocessor can normalize correctly.
    # The processors saved with the checkpoint reference these stats.
    ds = LeRobotDataset(
        repo_id=f"local/so101_{phase['name']}_v1",
        root=dataset_dir,
    )

    policy = make_policy(cfg, ds_meta=ds.meta)
    policy.eval()

    preprocessor, postprocessor = make_pre_post_processors(
        policy_cfg=cfg,
        pretrained_path=policy_dir,
        dataset_stats=ds.meta.stats,
        preprocessor_overrides={
            "device_processor": {"device": DEVICE},
            "rename_observations_processor": {"rename_map": {}},
        },
    )
    return policy, preprocessor, postprocessor


def build_observation(
    robot: SO101Follower,
    cameras: dict[str, OpenCVCamera],
) -> dict[str, np.ndarray]:
    """Compose the observation dict the same shape lerobot-record produces."""
    obs = robot.get_observation()  # joint state already in this dict
    # Add camera frames using the keys the policy was trained with:
    # observation.images.<cam_name>
    for name, cam in cameras.items():
        frame = cam.async_read() if hasattr(cam, "async_read") else cam.read()
        obs[f"observation.images.{name}"] = frame
    # Joint state under observation.state — collect into a flat array
    state = np.array([float(obs[j]) for j in JOINTS], dtype=np.float32)
    obs["observation.state"] = state
    return obs


def run_phase(
    robot: SO101Follower,
    cameras: dict[str, OpenCVCamera],
    phase: dict[str, Any],
    fps: int = 30,
) -> None:
    """Drive the follower with `phase['policy']` for `phase['max_seconds']`."""
    print(f"\n[phase] {phase['name'].upper()}: loading policy...")
    policy, preprocessor, postprocessor = load_policy_and_processors(phase)
    policy.reset()
    preprocessor.reset()
    postprocessor.reset()

    # Get dataset meta once for action key conversion
    ds = LeRobotDataset(
        repo_id=f"local/so101_{phase['name']}_v1",
        root=phase["dataset_dir"],
    )

    period = 1.0 / fps
    t0 = time.time()
    print(f"[phase] {phase['name'].upper()}: running for {phase['max_seconds']:.0f}s...")
    while time.time() - t0 < phase["max_seconds"]:
        loop_start = time.time()
        obs = build_observation(robot, cameras)
        action_values = predict_action(
            observation=obs,
            policy=policy,
            device=get_safe_torch_device(DEVICE),
            preprocessor=preprocessor,
            postprocessor=postprocessor,
            use_amp=False,
            task=phase["task_text"],
            robot_type=robot.robot_type,
        )
        robot_action = make_robot_action(action_values, ds.features)
        robot.send_action(robot_action)
        dt = time.time() - loop_start
        if dt < period:
            time.sleep(period - dt)
    print(f"[phase] {phase['name'].upper()}: done ({time.time() - t0:.1f}s)")


def main() -> int:
    home_data = load_home_data()
    print("Loaded per-task starting poses from", HOME_JSON.name)
    for task in ("pick", "plug", "pour"):
        pose = get_task_home(home_data, task)
        first = next(iter(pose.items()))
        print(f"  {task}: {first[0]}={first[1]:+.2f}, ...")

    robot = SO101Follower(SO101FollowerConfig(
        port=FOLLOWER_PORT,
        id=ROBOT_ID,
        use_degrees=True,
        max_relative_target=20.0,  # match the recording-time safety limit
    ))
    print("\nConnecting robot...")
    robot.connect()

    overhead = OpenCVCamera(OpenCVCameraConfig(
        index_or_path=OVERHEAD_INDEX, width=CAM_W, height=CAM_H, fps=CAM_FPS,
    ))
    wrist = OpenCVCamera(OpenCVCameraConfig(
        index_or_path=WRIST_INDEX, width=CAM_W, height=CAM_H, fps=CAM_FPS,
    ))
    print("Connecting cameras...")
    overhead.connect()
    wrist.connect()
    cameras = {"overhead": overhead, "wrist": wrist}

    try:
        for phase in PHASES:
            target = get_task_home(home_data, phase["name"])
            print(f"\n[home]  Driving to {phase['name']} start pose...")
            go_home(robot, target, duration=3.0)
            run_phase(robot, cameras, phase)

        # Final reset to canonical home
        print("\n[home]  Final return to canonical HOME...")
        go_home(robot, home_data["canonical_home"], duration=3.0)

        print("\n========== AUTONOMOUS DEMO COMPLETE ==========")
        return 0
    finally:
        for cam in cameras.values():
            try:
                cam.disconnect()
            except Exception:
                pass
        try:
            robot.disconnect()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
