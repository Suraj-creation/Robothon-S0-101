#!/usr/bin/env python3
"""Read calibrated leader/follower joint values without commanding motion."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from lerobot.motors import Motor, MotorCalibration, MotorNormMode
from lerobot.motors.feetech import FeetechMotorsBus


MOTORS = {
    "shoulder_pan": Motor(1, "sts3215", MotorNormMode.DEGREES),
    "shoulder_lift": Motor(2, "sts3215", MotorNormMode.DEGREES),
    "elbow_flex": Motor(3, "sts3215", MotorNormMode.DEGREES),
    "wrist_flex": Motor(4, "sts3215", MotorNormMode.DEGREES),
    "wrist_roll": Motor(5, "sts3215", MotorNormMode.DEGREES),
    "gripper": Motor(6, "sts3215", MotorNormMode.RANGE_0_100),
}


def load_calibration(path: Path) -> dict[str, MotorCalibration]:
    data = json.loads(path.read_text())
    return {
        name: MotorCalibration(
            id=values["id"],
            drive_mode=values["drive_mode"],
            homing_offset=values["homing_offset"],
            range_min=values["range_min"],
            range_max=values["range_max"],
        )
        for name, values in data.items()
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--leader-port", required=True)
    parser.add_argument("--follower-port", required=True)
    parser.add_argument("--leader-calibration", type=Path, required=True)
    parser.add_argument("--follower-calibration", type=Path, required=True)
    parser.add_argument("--seconds", type=float, default=30.0)
    parser.add_argument("--fps", type=float, default=5.0)
    args = parser.parse_args()

    leader = FeetechMotorsBus(args.leader_port, MOTORS, load_calibration(args.leader_calibration))
    follower = FeetechMotorsBus(args.follower_port, MOTORS, load_calibration(args.follower_calibration))
    try:
        leader.connect()
        follower.connect()
        start = time.monotonic()
        while time.monotonic() - start < args.seconds:
            lvals = leader.sync_read("Present_Position")
            fvals = follower.sync_read("Present_Position")
            print("\n--------------------------------------------------------------")
            print(f"{'MOTOR':<15} {'LEADER':>10} {'FOLLOWER':>10} {'DIFF F-L':>10}")
            for motor in MOTORS:
                lv = lvals[motor]
                fv = fvals[motor]
                print(f"{motor:<15} {lv:>10.2f} {fv:>10.2f} {fv - lv:>10.2f}")
            time.sleep(1.0 / args.fps)
    finally:
        try:
            leader.port_handler.closePort()
        except Exception:
            pass
        try:
            follower.port_handler.closePort()
        except Exception:
            pass


if __name__ == "__main__":
    main()
