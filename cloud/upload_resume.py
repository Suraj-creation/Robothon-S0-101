"""Idempotent dataset uploader: resume-safe across network/process restarts.

Behavior:
  - For each task, checks the HF Hub state first.
  - If the remote dataset already has a populated commit (>1 file), skips it.
  - Otherwise calls upload_folder which itself does SHA-based dedup against
    the LFS staging bucket — so already-uploaded files are skipped, and only
    the ones missing or mid-flight on the prior run are re-uploaded.

Usage (run OUTSIDE the workspace sandbox so it can write to ~/.cache/huggingface/xet logs):

  HF_TOKEN="<token>" \\
  HF_HUB_DISABLE_XET=1 \\
  HF_HUB_DISABLE_PROGRESS_BARS=0 \\
  ./.conda/bin/python cloud/upload_resume.py

Set HF_HUB_DISABLE_PROGRESS_BARS=0 if you want live progress bars; set =1 for clean logs.
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

from huggingface_hub import HfApi, create_repo

USER = os.environ.get("HF_USER", "SurajCreation")
TOKEN = os.environ.get("HF_TOKEN")
if not TOKEN:
    sys.exit("ERROR: set HF_TOKEN env var before running.")

HOME = Path.home()
DATASETS = [
    ("pick", HOME / ".cache/huggingface/lerobot/local/so101_pick_v1", f"{USER}/so101_pick_v1"),
    ("plug", HOME / ".cache/huggingface/lerobot/local/so101_plug_v1", f"{USER}/so101_plug_v1"),
    ("pour", HOME / ".cache/huggingface/lerobot/local/so101_pour_v1", f"{USER}/so101_pour_v1"),
]

api = HfApi(token=TOKEN)


def is_already_uploaded(repo_id: str) -> bool:
    """True if the remote dataset has a real (data-bearing) commit, not just .gitattributes."""
    try:
        files = list(api.list_repo_files(repo_id, repo_type="dataset"))
    except Exception:
        return False
    real_files = [f for f in files if f != ".gitattributes" and not f.startswith(".")]
    return len(real_files) > 0


for task, local, remote in DATASETS:
    if not local.is_dir():
        print(f"SKIP {task}: missing {local}", flush=True)
        continue
    if is_already_uploaded(remote):
        print(f"SKIP {task}: already uploaded -> https://huggingface.co/datasets/{remote}", flush=True)
        continue

    print(f"\n=== {task}: {local} -> {remote} ===", flush=True)
    create_repo(remote, repo_type="dataset", private=True, exist_ok=True, token=TOKEN)
    t0 = time.time()
    try:
        api.upload_folder(
            folder_path=str(local),
            repo_id=remote,
            repo_type="dataset",
            commit_message=f"Upload SO-101 {task} demos for cloud training",
            token=TOKEN,
        )
        elapsed = time.time() - t0
        print(
            f"DONE {task} in {elapsed:.1f}s "
            f"-> https://huggingface.co/datasets/{remote}",
            flush=True,
        )
    except Exception as e:
        print(f"FAILED {task}: {type(e).__name__}: {e}", flush=True)
        sys.exit(2)

print("\nALL UPLOADS COMPLETE", flush=True)
