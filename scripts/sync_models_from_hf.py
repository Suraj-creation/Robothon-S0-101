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
  .conda/bin/python scripts/sync_models_from_hf.py --plug-only
  .conda/bin/python scripts/sync_models_from_hf.py --pour-only
  .conda/bin/python scripts/sync_models_from_hf.py --plug-only --repo-id ORG/my_plug_model
  # 404 on default URL? Create the model repo on HF, or use:
  #   ./scripts/stage_plug_model_from_outputs.sh
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
    parser.add_argument("--plug-only", action="store_true")
    parser.add_argument("--pour-only", action="store_true")
    parser.add_argument(
        "--repo-id",
        metavar="ORG/name",
        default=None,
        help="HF model repo to download (overrides default for --*-only modes)",
    )
    parser.add_argument("--user", default=os.environ.get("HF_USER", "SurajCreation"))
    args = parser.parse_args()

    _modes = int(args.pick_only) + int(args.plug_only) + int(args.pour_only)
    if _modes > 1:
        print(
            "Use only one of --pick-only / --plug-only / --pour-only",
            file=sys.stderr,
        )
        return 2
    if args.repo_id and _modes != 1:
        print(
            "--repo-id requires exactly one of --pick-only / --plug-only / --pour-only",
            file=sys.stderr,
        )
        return 2

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
        pairs = [(args.repo_id, pairs[0][1])] if args.repo_id else pairs[:1]
    elif args.plug_only:
        pairs = [(args.repo_id, pairs[1][1])] if args.repo_id else [pairs[1]]
    elif args.pour_only:
        pairs = [(args.repo_id, pairs[2][1])] if args.repo_id else [pairs[2]]

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
            en = type(e).__name__
            if en == "RepositoryNotFoundError" or "404" in str(e):
                print(
                    "\n  → 404 means this model repo does not exist on Hugging Face (or wrong name).",
                    flush=True,
                )
                print(
                    "     • Create https://huggingface.co/new-model and upload the same files as act_pick_v1,",
                    flush=True,
                )
                print(
                    "       then: --plug-only --repo-id YOUR_ORG/the_new_repo\n",
                    flush=True,
                )
                print(
                    "     • Or copy local training weights:",
                    flush=True,
                )
                print(
                    f"       {REPO_ROOT}/scripts/stage_plug_model_from_outputs.sh\n",
                    flush=True,
                )

    if failed:
        print(
            "Failed repos — fix HF upload or use local staging script above.",
            file=sys.stderr,
        )
        return 2 if len(failed) == len(pairs) else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
