#!/usr/bin/env python3
"""Extract the HOME pose from the first frame of recorded demos.

Why this script exists:
    Every ACT policy is trained to *start* from whatever pose the operator
    held when episode 0 frame 0 was recorded. If our autonomous sequencer
    starts a phase from a different pose, the policy gets out-of-distribution
    inputs and fails. So we read frame 0 of each task's first episode and
    emit a HOME pose JSON used by `go_home.py` between phases.

Usage:
    .conda/bin/python scripts/capture_home.py
        # writes scripts/home_pose.json with averaged starting poses

    .conda/bin/python scripts/capture_home.py --task pick
        # only pick — dumps the per-task home for reference
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "scripts" / "home_pose.json"

DATASETS = {
    "pick": Path.home() / ".cache/huggingface/lerobot/local/so101_pick_v1",
    "plug": Path.home() / ".cache/huggingface/lerobot/local/so101_plug_v1",
    "pour": Path.home() / ".cache/huggingface/lerobot/local/so101_pour_v1",
}

JOINTS = [
    "shoulder_pan.pos",
    "shoulder_lift.pos",
    "elbow_flex.pos",
    "wrist_flex.pos",
    "wrist_roll.pos",
    "gripper.pos",
]


def read_first_frames(dataset_root: Path, n_episodes: int = 5) -> pd.DataFrame:
    """Read frame 0 from the first `n_episodes` episodes."""
    parquet = dataset_root / "data" / "chunk-000" / "file-000.parquet"
    if not parquet.exists():
        raise FileNotFoundError(f"Dataset parquet not found at {parquet}")
    df = pd.read_parquet(parquet)
    # frame_index == 0 marks the start of each episode
    starts = df[df["frame_index"] == 0]
    return starts.head(n_episodes)


def extract_home(dataset_root: Path, n_episodes: int = 5) -> dict[str, float]:
    """Average the starting state across the first `n_episodes` of a dataset."""
    starts = read_first_frames(dataset_root, n_episodes=n_episodes)
    states = starts["observation.state"].tolist()
    if not states:
        raise RuntimeError(f"No starting frames found in {dataset_root}")
    avg = [sum(s[i] for s in states) / len(states) for i in range(len(JOINTS))]
    return {name: round(float(v), 2) for name, v in zip(JOINTS, avg)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--task", choices=list(DATASETS.keys()), default=None,
        help="Print the HOME pose for one task only (don't write JSON).",
    )
    parser.add_argument(
        "--out", type=Path, default=DEFAULT_OUT,
        help="Path to write the merged home_pose.json (default: scripts/home_pose.json)",
    )
    parser.add_argument(
        "--n-episodes", type=int, default=5,
        help="How many episodes' starting frames to average (default: 5).",
    )
    args = parser.parse_args()

    if args.task is not None:
        ds = DATASETS[args.task]
        home = extract_home(ds, n_episodes=args.n_episodes)
        print(f"# HOME pose for task: {args.task}")
        print(f"# averaged across {args.n_episodes} starting frames")
        print(json.dumps(home, indent=2))
        return 0

    # Compute per-task starting poses. We use Task 1 (pick) as the canonical
    # HOME because it's the start of the autonomous sequence; the other two
    # are dumped alongside for reference and for between-phase resets if you
    # want phase-specific homes later.
    poses: dict[str, dict[str, float]] = {}
    for name, ds in DATASETS.items():
        if not ds.exists():
            print(f"[skip] {name}: dataset not found at {ds}")
            continue
        try:
            poses[name] = extract_home(ds, n_episodes=args.n_episodes)
            print(f"[ok]   {name}: {ds}")
        except Exception as exc:
            print(f"[fail] {name}: {exc}")

    if not poses:
        print("ERROR: no datasets found. Make sure you have recorded demos.")
        return 1

    # Canonical HOME is the start of Task 1 (pick) — that's where the demo
    # begins. The other per-task homes are kept for reference / phase resets.
    home_canonical = poses.get("pick") or next(iter(poses.values()))

    out = {
        "canonical_home": home_canonical,
        "per_task_starts": poses,
        "joint_names": JOINTS,
        "notes": (
            "canonical_home is the pose to drive the follower to BEFORE the "
            "autonomous sequence starts (and between phases). It is the "
            "average of the first-frame states across the first 5 episodes "
            "of so101_pick_v1. per_task_starts shows each task's natural "
            "starting pose for reference."
        ),
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, indent=2))
    print(f"\nWrote {args.out}")
    print("\nCanonical HOME pose (start of Task 1):")
    print(json.dumps(home_canonical, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
