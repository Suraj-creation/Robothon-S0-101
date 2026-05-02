#!/usr/bin/env python3
"""Release SO-101 follower torque safely.

Use this after an interrupted autonomous run if the follower is still stiff.

Run:
    .conda/bin/python scripts/so101_release_torque.py
"""
from __future__ import annotations

import argparse
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="/dev/tty.usbmodem5B141124491")
    parser.add_argument("--id", default="so101_follower_main")
    args = parser.parse_args()

    from lerobot.robots.so_follower import SO101Follower, SO101FollowerConfig

    robot = SO101Follower(
        SO101FollowerConfig(
            port=args.port,
            id=args.id,
            use_degrees=True,
            disable_torque_on_disconnect=True,
        )
    )
    robot.connect()
    robot.disconnect()
    print("Follower torque released.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
