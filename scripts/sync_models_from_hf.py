#!/usr/bin/env python3
"""
Download SurajCreation ACT model repos from Hugging Face into models/.

  act_pick_v1  -> models/act_pick_v1
  act_plug_v1  -> models/act_plug_v1
  act_pour_v1  -> models/act_pour_v1

Auth (private repos):
  export HF_TOKEN=hf_...
  # or: huggingface-cli login

HF_HUB_DISABLE_XET=1 avoids flaky xet uploads/downloads on some networks.

Usage:
  HF_HUB_DISABLE_XET=1 HF_TOKEN=... .conda/bin/python scripts/sync_models_from_hf.py
  .conda/bin/python scripts/sync_models_from_hf.py --pick-only
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pick-only", action="store_true")
    parser.add_argument("--user", default=os.environ.get("HF_USER", "SurajCreation"))
    args = parser.parse_args()

    os.environ.setdefault("HF_HUB_DISABLE_XET", "1")

    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        print("pip install huggingface_hub", file=sys.stderr)
        return 1

    pairs = [
        (f"{args.user}/act_pick_v1", REPO_ROOT / "models" / "act_pick_v1"),
        (f"{args.user}/act_plug_v1", REPO_ROOT / "models" / "act_plug_v1"),
        (f"{args.user}/act_pour_v1", REPO_ROOT / "models" / "act_pour_v1"),
    ]
    if args.pick_only:
        pairs = pairs[:1]

    token = (
        os.environ.get("HF_TOKEN")
        or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    )

    failed: list[str] = []
    for repo_id, dest in pairs:
        print(f"\n=== {repo_id} -> {dest.name}/ ===", flush=True)
        if dest.exists():
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            snapshot_download(
                repo_id=repo_id,
                repo_type="model",
                local_dir=str(dest),
                token=token,
            )
            # HF snapshots include their own .gitattributes; we use repo-root LFS rules.
            ga = dest / ".gitattributes"
            if ga.is_file():
                ga.unlink()
            n = sum(1 for _ in dest.rglob("*") if _.is_file())
            print(f"OK ({n} files)", flush=True)
        except Exception as e:
            print(f"FAIL: {type(e).__name__}: {e}", flush=True)
            failed.append(repo_id)
            if dest.exists():
                shutil.rmtree(dest, ignore_errors=True)

    if failed:
        print(
            "\nFailed repos — create/upload them on HF or set HF_TOKEN for private repos.",
            file=sys.stderr,
        )
        return 2 if len(failed) == len(pairs) else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
