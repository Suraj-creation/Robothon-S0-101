#!/usr/bin/env python3
"""Task 1 preflight vision check.

This is deliberately a gate, not the manipulation controller. The ACT policy
still drives the robot. We briefly open the overhead camera before LeRobot
starts, verify it returns a real frame, optionally run YOLO11 for visibility
debugging, save an annotated frame, and release the camera.

Why not run YOLO during `lerobot-record --policy.path`?
On macOS, a UVC camera is usually owned by one process at a time. Running YOLO
in a separate process while LeRobot also reads the same camera can make the
policy fail to open the camera. So this script only checks before motion.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import cv2
import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--camera-index", type=int, required=True)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--warmup-frames", type=int, default=8)
    parser.add_argument("--yolo-weights", type=Path, default=Path("yolo11n.pt"))
    parser.add_argument("--output-dir", type=Path, default=Path("outputs/task1_autonomous_debug"))
    parser.add_argument("--require-colored-object", action="store_true",
                        help="Fail if no saturated colored blob is visible. "
                             "Leave off unless the cube is a strong solid color.")
    return parser.parse_args()


def detect_colored_blob(frame: np.ndarray) -> tuple[bool, tuple[int, int, int, int] | None, float]:
    """Very simple HSV saturation gate for a solid colored cube.

    This is intentionally broad: it is a sanity check that a colored object is
    in the overhead scene, not a classifier.
    """
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, (0, 55, 35), (179, 255, 255))
    mask = cv2.medianBlur(mask, 5)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return False, None, 0.0
    contour = max(contours, key=cv2.contourArea)
    area = float(cv2.contourArea(contour))
    if area < 300:
        return False, None, area
    x, y, w, h = cv2.boundingRect(contour)
    return True, (x, y, w, h), area


def run_yolo(frame: np.ndarray, weights: Path) -> list[str]:
    if not weights.exists():
        return [f"YOLO skipped: weights not found at {weights}"]
    try:
        from ultralytics import YOLO
    except Exception as exc:  # pragma: no cover - environment dependent
        return [f"YOLO skipped: import failed: {exc}"]

    try:
        model = YOLO(str(weights))
        result = model(frame, verbose=False)[0]
    except Exception as exc:  # pragma: no cover - model/runtime dependent
        return [f"YOLO skipped: inference failed: {exc}"]

    detections: list[str] = []
    boxes = result.boxes
    if boxes is None or len(boxes) == 0:
        return ["YOLO detections: none"]
    for cls, conf in zip(boxes.cls, boxes.conf):
        detections.append(f"{model.names[int(cls)]}:{float(conf):.2f}")
    return detections


def main() -> int:
    args = parse_args()
    cap = cv2.VideoCapture(args.camera_index)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)

    frame = None
    ok = False
    for _ in range(max(1, args.warmup_frames)):
        ok, frame = cap.read()
        if ok and frame is not None:
            time.sleep(0.03)
    cap.release()

    if not ok or frame is None:
        print(f"[vision] ERROR: camera index {args.camera_index} did not return a frame.")
        return 2

    std = float(frame.std())
    if std < 2.0:
        print(f"[vision] ERROR: camera frame looks blank/flat, std={std:.2f}.")
        return 2

    colored_ok, bbox, area = detect_colored_blob(frame)
    yolo_lines = run_yolo(frame, args.yolo_weights)

    annotated = frame.copy()
    if bbox is not None:
        x, y, w, h = bbox
        cv2.rectangle(annotated, (x, y), (x + w, y + h), (0, 255, 255), 2)
        cv2.putText(annotated, f"color blob area={area:.0f}", (x, max(20, y - 8)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1, cv2.LINE_AA)
    cv2.putText(annotated, f"frame std={std:.1f}", (12, 24),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2, cv2.LINE_AA)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    out = args.output_dir / f"task1_preflight_{time.strftime('%Y%m%d_%H%M%S')}.jpg"
    cv2.imwrite(str(out), annotated)

    print(f"[vision] overhead camera OK: index={args.camera_index}, std={std:.2f}")
    print(f"[vision] colored-object gate: {'OK' if colored_ok else 'not found'} (area={area:.0f})")
    print(f"[vision] debug frame: {out}")
    for line in yolo_lines:
        print(f"[vision] {line}")

    if args.require_colored_object and not colored_ok:
        print("[vision] ERROR: --require-colored-object was set, but no colored object was found.")
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
