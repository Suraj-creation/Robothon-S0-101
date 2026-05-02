"""Modal app for training all three SO-101 ACT policies on cloud GPUs.

Use this if you want unattended training without Colab's 12h session
limits / disconnects, and don't mind paying ~$3-8 total.

Why Modal?
  - $30 free credit on signup (covers all 3 tasks comfortably)
  - A10G GPU at ~$1.10/hr (≈ 30-50× faster than your M4 CPU)
  - One file, one command, no infra to manage
  - Logs stream to your terminal; checkpoints saved to a Modal volume

Setup (one-time):
  pip install modal
  modal setup        # pairs your terminal to your modal.com account
  modal token new    # if the above does not auto-create a token

Run all three tasks (sequential, ~2-3 hours wall-clock at full quality):
  HF_USER=udbhav-k modal run cloud/modal_train.py::run_all

Run just one task:
  HF_USER=udbhav-k modal run cloud/modal_train.py::run_one --task pick

Each function uploads the trained checkpoint back to your HuggingFace Hub
under <HF_USER>/act_<task>_v1 so you can pull it down to your Mac with
  huggingface-cli download <HF_USER>/act_pick_v1 \
      --local-dir outputs/act_pick_v1/checkpoints/last/pretrained_model
"""

from __future__ import annotations

import os
from pathlib import Path

import modal

# --- Image: pinned to match the local .conda environment ---
image = (
    modal.Image.debian_slim(python_version="3.10")
    .apt_install("git", "ffmpeg")
    .pip_install(
        "lerobot==0.5.1",
        "huggingface_hub>=0.25",
        "torch==2.4.0",
    )
)

app = modal.App("so101-lerobot-train", image=image)

# Persistent volume so we can resume / inspect runs across invocations
vol = modal.Volume.from_name("so101-train-vol", create_if_missing=True)

# Per-task config — mirrors scripts/task{1,2,3}_env.sh but FULL QUALITY because
# the GPU is fast enough to make the compressed budget unnecessary.
CONFIGS = {
    "pick": {
        "repo_local": "so101_pick_v1",
        "run_name": "act_pick_v1",
        "steps": 50000,
        "save_freq": 5000,
        "chunk_size": 50,
        "kl_weight": 10.0,
    },
    "plug": {
        "repo_local": "so101_plug_v1",
        "run_name": "act_plug_v1",
        "steps": 60000,
        "save_freq": 5000,
        "chunk_size": 80,
        "kl_weight": 20.0,
    },
    "pour": {
        "repo_local": "so101_pour_v1",
        "run_name": "act_pour_v1",
        "steps": 40000,
        "save_freq": 5000,
        "chunk_size": 80,
        "kl_weight": 15.0,
    },
}


@app.function(
    gpu="A10G",
    timeout=60 * 60 * 6,  # 6h hard cap per task
    volumes={"/vol": vol},
    secrets=[modal.Secret.from_name("huggingface-secret")],  # contains HF_TOKEN
)
def train_task(task: str, hf_user: str) -> str:
    """Train one task. Pulls dataset from HF Hub, trains on A10G, pushes policy back."""
    import subprocess
    from huggingface_hub import HfApi, create_repo, login, snapshot_download

    assert task in CONFIGS, f"unknown task: {task}"
    c = CONFIGS[task]

    hf_token = os.environ["HF_TOKEN"]
    login(token=hf_token)

    dataset_repo = f"{hf_user}/{c['repo_local']}"
    policy_repo = f"{hf_user}/{c['run_name']}"

    dataset_root = Path(f"/vol/datasets/{dataset_repo}")
    out_dir = Path(f"/vol/outputs/{c['run_name']}")
    dataset_root.parent.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[{task}] downloading dataset {dataset_repo} -> {dataset_root}")
    snapshot_download(
        repo_id=dataset_repo,
        repo_type="dataset",
        local_dir=str(dataset_root),
    )

    cmd = [
        "lerobot-train",
        "--policy.type=act",
        "--policy.device=cuda",
        "--policy.push_to_hub=false",
        f"--policy.chunk_size={c['chunk_size']}",
        f"--policy.kl_weight={c['kl_weight']}",
        "--policy.dim_model=512",
        "--policy.n_heads=8",
        "--policy.dim_feedforward=3200",
        f"--dataset.repo_id={dataset_repo}",
        f"--dataset.root={dataset_root}",
        "--batch_size=8",
        f"--steps={c['steps']}",
        f"--save_freq={c['save_freq']}",
        "--log_freq=200",
        f"--output_dir={out_dir}",
        f"--job_name={c['run_name']}_modal",
        "--wandb.enable=false",
    ]
    print(f"[{task}] starting training:\n  " + " ".join(cmd))
    rc = subprocess.run(cmd).returncode
    if rc != 0:
        raise RuntimeError(f"training failed with code {rc}")

    checkpoints = sorted((out_dir / "checkpoints").glob("*"))
    if not checkpoints:
        raise RuntimeError(f"no checkpoints under {out_dir}")
    pretrained = checkpoints[-1] / "pretrained_model"

    print(f"[{task}] uploading {pretrained} to {policy_repo}")
    api = HfApi()
    create_repo(policy_repo, exist_ok=True, private=True)
    api.upload_folder(
        folder_path=str(pretrained),
        repo_id=policy_repo,
        repo_type="model",
    )
    return policy_repo


@app.local_entrypoint()
def run_one(task: str = "pick"):
    hf_user = os.environ.get("HF_USER")
    if not hf_user:
        raise SystemExit("set HF_USER env var, e.g. HF_USER=udbhav-k modal run ...")
    repo = train_task.remote(task, hf_user)
    print(f"\nDone. Policy pushed to: https://huggingface.co/{repo}")


@app.local_entrypoint()
def run_all():
    hf_user = os.environ.get("HF_USER")
    if not hf_user:
        raise SystemExit("set HF_USER env var, e.g. HF_USER=udbhav-k modal run ...")
    pushed: list[str] = []
    for task in ("pick", "plug", "pour"):
        repo = train_task.remote(task, hf_user)
        pushed.append(repo)
        print(f"  {task} -> {repo}")
    print("\nAll three policies pushed. Pull them on your Mac with:")
    for repo in pushed:
        run_name = repo.split("/")[-1]
        print(
            f"  huggingface-cli download {repo} "
            f"--local-dir outputs/{run_name}/checkpoints/last/pretrained_model"
        )
