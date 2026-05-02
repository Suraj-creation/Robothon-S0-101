#!/usr/bin/env python3
"""Probe camera indices on macOS via AVFoundation, save sample frames.

Usage:
    .conda/bin/python scripts/camera_probe.py
    open camera_probe/        # then visually identify which index is which cam
"""
import os
import time

import cv2

OUT_DIR = "camera_probe"
os.makedirs(OUT_DIR, exist_ok=True)

print(f"OpenCV: {cv2.__version__}")
print(f"{'idx':<4} {'WxH':<12} {'fps':<6} {'saved':<40}")
print("-" * 70)

found = []
for i in range(6):
    cap = cv2.VideoCapture(i, cv2.CAP_AVFOUNDATION)
    if not cap.isOpened():
        cap.release()
        continue
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_FPS, 30)
    # Warm-up — first few frames can be black on UVC devices
    for _ in range(8):
        cap.read()
        time.sleep(0.05)
    ok, frame = cap.read()
    if not ok or frame is None:
        cap.release()
        continue
    h, w = frame.shape[:2]
    fps = cap.get(cv2.CAP_PROP_FPS)
    path = os.path.join(OUT_DIR, f"cam_index_{i}_{w}x{h}.jpg")
    cv2.imwrite(path, frame)
    print(f"{i:<4} {w}x{h:<8} {fps:<6.1f} {path}")
    found.append((i, w, h, path))
    cap.release()
    time.sleep(0.3)

if not found:
    print(
        "\nNo cameras opened.\n"
        "Fix: System Settings -> Privacy & Security -> Camera -> enable Terminal\n"
        "(or iTerm / Cursor, whatever you ran this from). Then re-run."
    )
else:
    print(f"\n{len(found)} camera(s) usable. Open the JPEGs to identify them:")
    print(f"  open {OUT_DIR}/")
