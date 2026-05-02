#!/usr/bin/env python3
"""Validate SO-101 calibration JSON ranges before teleoperation."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


MIN_DELTAS = {
    "shoulder_pan": 300,
    "shoulder_lift": 300,
    "elbow_flex": 300,
    "wrist_flex": 300,
    "wrist_roll": 3000,
    "gripper": 100,
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("calibration_json", type=Path)
    args = parser.parse_args()

    data = json.loads(args.calibration_json.read_text())
    ok = True
    print(args.calibration_json)
    print(f"{'MOTOR':<15} {'MIN':>6} {'MAX':>6} {'DELTA':>7} {'NEED':>6} STATUS")
    for motor, need in MIN_DELTAS.items():
        values = data.get(motor)
        if not values:
            print(f"{motor:<15} {'-':>6} {'-':>6} {'-':>7} {need:>6} MISSING")
            ok = False
            continue
        range_min = values["range_min"]
        range_max = values["range_max"]
        delta = range_max - range_min
        status = "OK" if delta >= need else "TOO_SMALL"
        ok = ok and status == "OK"
        print(f"{motor:<15} {range_min:>6} {range_max:>6} {delta:>7} {need:>6} {status}")

    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
