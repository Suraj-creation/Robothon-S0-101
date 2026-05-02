#!/usr/bin/env python3
"""SO-101 pre-calibration live movement checker.

This does not save calibration. It disables torque, streams raw encoder
positions, and helps confirm every joint can be moved by hand before running
the official `lerobot-calibrate` command.
"""

from __future__ import annotations

import argparse
import sys
import termios
import time
import tty

from lerobot.motors import Motor, MotorNormMode
from lerobot.motors.feetech import FeetechMotorsBus, OperatingMode


MOTORS = {
    "shoulder_pan": Motor(1, "sts3215", MotorNormMode.DEGREES),
    "shoulder_lift": Motor(2, "sts3215", MotorNormMode.DEGREES),
    "elbow_flex": Motor(3, "sts3215", MotorNormMode.DEGREES),
    "wrist_flex": Motor(4, "sts3215", MotorNormMode.DEGREES),
    "wrist_roll": Motor(5, "sts3215", MotorNormMode.DEGREES),
    "gripper": Motor(6, "sts3215", MotorNormMode.RANGE_0_100),
}


def key_pressed() -> bool:
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        import select

        readable, _, _ = select.select([sys.stdin], [], [], 0)
        if readable:
            sys.stdin.read(1)
            return True
        return False
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--seconds", type=float, default=60.0)
    args = parser.parse_args()

    bus = FeetechMotorsBus(port=args.port, motors=MOTORS)
    try:
        bus.connect()
        bus.disable_torque()
        for motor in MOTORS:
            bus.write("Operating_Mode", motor, OperatingMode.POSITION.value)

        print("Torque disabled. Move every joint by hand except wrist_roll can be ignored for official range.")
        print("Press any key to stop early.\n")

        start = time.monotonic()
        start_positions = bus.sync_read("Present_Position", normalize=False)
        mins = start_positions.copy()
        maxes = start_positions.copy()

        while time.monotonic() - start < args.seconds:
            positions = bus.sync_read("Present_Position", normalize=False)
            mins = {motor: min(mins[motor], positions[motor]) for motor in MOTORS}
            maxes = {motor: max(maxes[motor], positions[motor]) for motor in MOTORS}

            print("\n-------------------------------------------------------")
            print(f"{'NAME':<15} | {'MIN':>6} | {'POS':>6} | {'MAX':>6} | {'DELTA':>6}")
            for motor in MOTORS:
                delta = maxes[motor] - mins[motor]
                print(f"{motor:<15} | {mins[motor]:>6} | {positions[motor]:>6} | {maxes[motor]:>6} | {delta:>6}")

            if key_pressed():
                break
            print("\033[F" * (len(MOTORS) + 3), end="")
            time.sleep(0.1)

        print("\nFinal movement deltas:")
        for motor in MOTORS:
            delta = maxes[motor] - mins[motor]
            status = "OK" if delta > 20 or motor == "wrist_roll" else "MOVE_MORE"
            print(f"{motor:<15} delta={delta:<6} {status}")
    finally:
        try:
            bus.disconnect(disable_torque=True)
        except Exception:
            try:
                bus.port_handler.closePort()
            except Exception:
                pass


if __name__ == "__main__":
    main()
