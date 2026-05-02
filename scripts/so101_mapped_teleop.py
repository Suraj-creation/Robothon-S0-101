#!/usr/bin/env python3
"""SO-101 teleoperation with optional per-joint sign inversion and startup offset."""

from __future__ import annotations

import argparse
import time

from lerobot.robots.so_follower.config_so_follower import SOFollowerRobotConfig
from lerobot.robots.so_follower.so_follower import SOFollower
from lerobot.teleoperators.so_leader.config_so_leader import SOLeaderTeleopConfig
from lerobot.teleoperators.so_leader.so_leader import SOLeader


MOTORS = ["shoulder_pan", "shoulder_lift", "elbow_flex", "wrist_flex", "wrist_roll", "gripper"]


def parse_inverts(value: str) -> set[str]:
    if not value.strip():
        return set()
    motors = {item.strip() for item in value.split(",") if item.strip()}
    unknown = motors - set(MOTORS)
    if unknown:
        raise ValueError(f"Unknown motor names: {sorted(unknown)}")
    return motors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--leader-port", required=True)
    parser.add_argument("--follower-port", required=True)
    parser.add_argument("--leader-id", default="so101_leader_main")
    parser.add_argument("--follower-id", default="so101_follower_main")
    parser.add_argument("--invert", default="", help="Comma-separated motor names to invert.")
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--max-relative-target", type=float, default=3.0)
    parser.add_argument(
        "--no-startup-offset",
        action="store_true",
        help="Do not preserve current follower-vs-leader offset at startup.",
    )
    args = parser.parse_args()

    inverted = parse_inverts(args.invert)
    signs = {motor: (-1.0 if motor in inverted else 1.0) for motor in MOTORS}

    leader = SOLeader(SOLeaderTeleopConfig(port=args.leader_port, id=args.leader_id))
    follower = SOFollower(
        SOFollowerRobotConfig(
            port=args.follower_port,
            id=args.follower_id,
            max_relative_target=args.max_relative_target,
        )
    )

    leader.connect()
    follower.connect()
    print(f"Connected. Inverted joints: {sorted(inverted) or 'none'}")
    print("Keep hand near follower power. Press Ctrl+C to stop.")

    try:
        leader_action = leader.get_action()
        follower_obs = follower.get_observation()
        offsets = {}
        for motor in MOTORS:
            key = f"{motor}.pos"
            offsets[key] = 0.0 if args.no_startup_offset else follower_obs[key] - signs[motor] * leader_action[key]

        period = 1.0 / args.fps
        while True:
            start = time.perf_counter()
            leader_action = leader.get_action()
            target = {}
            for motor in MOTORS:
                key = f"{motor}.pos"
                target[key] = signs[motor] * leader_action[key] + offsets[key]
            follower.send_action(target)
            elapsed = time.perf_counter() - start
            if elapsed < period:
                time.sleep(period - elapsed)
    except KeyboardInterrupt:
        pass
    finally:
        leader.disconnect()
        follower.disconnect()
        print("Disconnected.")


if __name__ == "__main__":
    main()
