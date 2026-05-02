#!/usr/bin/env python3
"""Read-only SO-101 motor bus diagnostics for leader/follower arms."""

from __future__ import annotations

import argparse
import time

from lerobot.motors import Motor, MotorNormMode
from lerobot.motors.feetech import FeetechMotorsBus


EXPECTED_MOTORS = {
    "shoulder_pan": Motor(1, "sts3215", MotorNormMode.DEGREES),
    "shoulder_lift": Motor(2, "sts3215", MotorNormMode.DEGREES),
    "elbow_flex": Motor(3, "sts3215", MotorNormMode.DEGREES),
    "wrist_flex": Motor(4, "sts3215", MotorNormMode.DEGREES),
    "wrist_roll": Motor(5, "sts3215", MotorNormMode.DEGREES),
    "gripper": Motor(6, "sts3215", MotorNormMode.RANGE_0_100),
}


def diagnose(label: str, port: str, scan_all: bool, read_registers: bool) -> None:
    print(f"\n=== {label.upper()} {port} ===")
    bus = FeetechMotorsBus(port=port, motors=EXPECTED_MOTORS)
    try:
        bus._connect(handshake=False)
        bus.set_baudrate(bus.default_baudrate)

        for name, motor in EXPECTED_MOTORS.items():
            model = bus.ping(motor.id, num_retry=2, raise_on_error=False)
            if model is None:
                print(f"ID {motor.id} {name}: MISSING")
                continue

            if read_registers:
                try:
                    pos = bus.read("Present_Position", name, normalize=False, num_retry=2)
                    torque = bus.read("Torque_Enable", name, normalize=False, num_retry=2)
                    print(f"ID {motor.id} {name}: OK model={model} pos={pos} torque={torque}")
                except Exception as exc:
                    print(f"ID {motor.id} {name}: PING_OK model={model} READ_FAIL {type(exc).__name__}: {exc}")
            else:
                print(f"ID {motor.id} {name}: PING_OK model={model}")

        if scan_all:
            found = []
            for motor_id in range(254):
                model = bus.ping(motor_id, num_retry=0, raise_on_error=False)
                if model is not None:
                    found.append((motor_id, model))
            print(f"ALL_IDS={found}")
    finally:
        try:
            bus.port_handler.closePort()
        except Exception:
            pass


def repeated_ping(label: str, port: str, samples: int, delay_s: float) -> None:
    print(f"\n=== {label.upper()} REPEATED PING {port} ===")
    for sample in range(1, samples + 1):
        bus = FeetechMotorsBus(port=port, motors={})
        try:
            bus._connect(handshake=False)
            bus.set_baudrate(bus.default_baudrate)
            found = []
            for motor_id in range(1, 7):
                model = bus.ping(motor_id, num_retry=1, raise_on_error=False)
                if model is not None:
                    found.append(motor_id)
            print(f"sample {sample:02d}: {found}")
        except Exception as exc:
            print(f"sample {sample:02d}: BUS_FAIL {type(exc).__name__}: {exc}")
        finally:
            try:
                bus.port_handler.closePort()
            except Exception:
                pass
        time.sleep(delay_s)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--leader-port")
    parser.add_argument("--follower-port")
    parser.add_argument("--scan-all", action="store_true")
    parser.add_argument("--no-read", action="store_true", help="Only ping IDs; do not read registers.")
    parser.add_argument("--repeat", type=int, default=0, help="Run repeated ping-only samples.")
    parser.add_argument("--delay-s", type=float, default=0.25, help="Delay between repeated samples.")
    args = parser.parse_args()

    if args.repeat:
        if args.leader_port:
            repeated_ping("leader", args.leader_port, args.repeat, args.delay_s)
        if args.follower_port:
            repeated_ping("follower", args.follower_port, args.repeat, args.delay_s)
        return

    if args.leader_port:
        diagnose("leader", args.leader_port, args.scan_all, not args.no_read)
    if args.follower_port:
        diagnose("follower", args.follower_port, args.scan_all, not args.no_read)
    if not args.leader_port and not args.follower_port:
        parser.error("Provide --leader-port and/or --follower-port")


if __name__ == "__main__":
    main()
