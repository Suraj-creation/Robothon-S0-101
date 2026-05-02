#!/usr/bin/env python3
"""Detect or configure one isolated SO-101 Feetech motor.

Use this only when exactly one motor is connected to the controller board.
It is meant for recovering interrupted SO-101 setup-motors runs or duplicate IDs.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass

from lerobot.motors import Motor, MotorNormMode
from lerobot.motors.feetech import FeetechMotorsBus


@dataclass(frozen=True)
class TargetMotor:
    name: str
    motor_id: int
    norm_mode: MotorNormMode


TARGETS = {
    "shoulder_pan": TargetMotor("shoulder_pan", 1, MotorNormMode.DEGREES),
    "shoulder_lift": TargetMotor("shoulder_lift", 2, MotorNormMode.DEGREES),
    "elbow_flex": TargetMotor("elbow_flex", 3, MotorNormMode.DEGREES),
    "wrist_flex": TargetMotor("wrist_flex", 4, MotorNormMode.DEGREES),
    "wrist_roll": TargetMotor("wrist_roll", 5, MotorNormMode.DEGREES),
    "gripper": TargetMotor("gripper", 6, MotorNormMode.RANGE_0_100),
}


def detect_one(port: str) -> list[tuple[int, int, int]]:
    """Return `(baudrate, id, model)` tuples for all detected motors."""
    bus = FeetechMotorsBus(port=port, motors={})
    found: list[tuple[int, int, int]] = []
    try:
        bus._connect(handshake=False)
        for baudrate in bus.available_baudrates:
            bus.set_baudrate(baudrate)
            for motor_id in range(254):
                model = bus.ping(motor_id, num_retry=0, raise_on_error=False)
                if model is not None:
                    found.append((baudrate, motor_id, model))
    finally:
        try:
            bus.port_handler.closePort()
        except Exception:
            pass
    return found


def set_one(port: str, target: TargetMotor, found: tuple[int, int, int]) -> None:
    baudrate, current_id, model = found
    if model != 777:
        raise RuntimeError(f"Expected STS3215 model 777, found model {model}")

    bus = FeetechMotorsBus(
        port=port,
        motors={target.name: Motor(target.motor_id, "sts3215", target.norm_mode)},
    )
    try:
        bus._connect(handshake=False)
        bus.setup_motor(target.name, initial_baudrate=baudrate, initial_id=current_id)
        bus.set_baudrate(bus.default_baudrate)
        verified_model = bus.ping(target.motor_id, num_retry=2, raise_on_error=False)
        if verified_model != 777:
            raise RuntimeError(f"Write did not verify. ID {target.motor_id} returned {verified_model}")
        print(f"OK: {target.name} configured as ID {target.motor_id} at {bus.default_baudrate} baud.")
    finally:
        try:
            bus.port_handler.closePort()
        except Exception:
            pass


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--target", choices=TARGETS, help="Motor name to configure.")
    parser.add_argument("--set", action="store_true", help="Write target ID/baudrate.")
    parser.add_argument(
        "--yes-one-motor-only",
        action="store_true",
        help="Required with --set. Confirms exactly one motor is connected.",
    )
    args = parser.parse_args()

    found = detect_one(args.port)
    print("Detected motors:")
    if not found:
        print("  none")
    for baudrate, motor_id, model in found:
        print(f"  baud={baudrate} id={motor_id} model={model}")

    if not args.set:
        return

    if not args.target:
        parser.error("--set requires --target")
    if not args.yes_one_motor_only:
        parser.error("--set requires --yes-one-motor-only")
    if len(found) != 1:
        raise SystemExit(
            f"Refusing to write because {len(found)} motors were detected. "
            "Disconnect everything except the one target motor."
        )

    set_one(args.port, TARGETS[args.target], found[0])


if __name__ == "__main__":
    main()
