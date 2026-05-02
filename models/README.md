# Published ACT checkpoints (Robothon tasks)

Each task uses its own LeRobot ACT **`pretrained_model`** bundle under `models/act_<task>_v1/`. Large **`*.safetensors`** files are stored on GitHub via **Git LFS** (`.gitattributes` at repo root).

## Clone with weights

```bash
git lfs install
git clone https://github.com/Suraj-creation/Robothon-S0-101.git
cd Robothon-S0-101
git lfs pull
```

Without `git lfs pull`, you only get LFS pointer files locally — inference will fail until pointers are resolved.

## Hugging Face → `models/` (sync)

Default model repos: **`SurajCreation/act_pick_v1`**, **`SurajCreation/act_plug_v1`**, **`SurajCreation/act_pour_v1`**.

```bash
export HF_HUB_DISABLE_XET=1
export HF_TOKEN=hf_...   # read access; never commit
.conda/bin/python scripts/sync_models_from_hf.py
```

| Flag | Downloads |
|------|-----------|
| `--pick-only` | `act_pick_v1` → `models/act_pick_v1` |
| `--plug-only` | `act_plug_v1` → `models/act_plug_v1` |
| `--pour-only` | `act_pour_v1` → `models/act_pour_v1` |
| `--repo-id ORG/name` | Use with **exactly one** `--*-only` to override the Hub repo |

If the Hub returns **404**, that model repo does not exist yet — create it on Hugging Face and upload the same file layout as pick, or copy **`outputs/<run>/checkpoints/last/pretrained_model`** into the matching `models/act_*_v1/` folder. Plug-only local staging: **`scripts/stage_plug_model_from_outputs.sh`** (after `task2_train.sh`).

## Layout per task

| Path | Task |
|------|------|
| [`act_pick_v1/`](act_pick_v1/) | Pick & place — **in repo** (synced from HF) |
| `act_plug_v1/` | Charger plug — add when HF or local `pretrained_model` exists |
| `act_pour_v1/` | Liquid pour — same |

Each folder should contain at least: `config.json`, `model.safetensors`, `policy_preprocessor.json`, `policy_postprocessor.json`, small processor `.safetensors`, `train_config.json`.

## Inference

```bash
--policy.path=models/act_pick_v1
```

## Autonomous scripts (use `models/` or fall back to `outputs/`)

| Script | Purpose |
|--------|---------|
| [`../scripts/run_full_demo_github_models.sh`](../scripts/run_full_demo_github_models.sh) | Pick → plug → pour; `--available-only` skips missing tasks |
| [`../scripts/task1_autonomous_github_models.sh`](../scripts/task1_autonomous_github_models.sh) | Task 1 only |
| [`../scripts/task2_autonomous_github_models.sh`](../scripts/task2_autonomous_github_models.sh) | Task 2 only |

## Size & LFS

Expect **~200 MB per task** for `model.safetensors` — above GitHub’s non-LFS limit; **always use Git LFS** for commits including new `models/act_*_v1/` trees.

## Publishing updates to GitHub

1. `sync_models_from_hf.py` (and/or copy from `outputs/.../pretrained_model`).
2. `git add models/` and commit.
3. `git push` (LFS uploads large blobs automatically if `git-lfs` is installed).
