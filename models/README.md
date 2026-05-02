# Published ACT checkpoints (all three Robothon tasks)

The project **trains a separate LeRobot ACT policy for each task** (pick, plug, pour). This folder holds **released** policy weights so they can be versioned on GitHub (large `*.safetensors` via **Git LFS**) without tracking the full `outputs/` training tree (which stays local and gitignored).

## Download from Hugging Face

From the repo root (token required if repos are private):

```bash
export HF_TOKEN=hf_...   # read access; never commit this
export HF_HUB_DISABLE_XET=1
.conda/bin/python scripts/sync_models_from_hf.py
```

Default Hub IDs: `SurajCreation/act_pick_v1`, `SurajCreation/act_plug_v1`, `SurajCreation/act_pour_v1`.  
**Today only `act_pick_v1` exists on the Hub** — plug/pour return 404 until you create and upload those model repos (same file layout as pick).

`--pick-only` downloads just pick. Override user with `--user YourOrg`.

## Layout per task

| Path | Description |
|------|-------------|
| [`act_pick_v1/`](act_pick_v1/) | LeRobot ACT **pretrained_model** bundle (pick task) |
| `act_plug_v1/` | Same layout for plug (populate via HF sync or copy from `outputs/.../pretrained_model`) |
| `act_pour_v1/` | Same layout for pour |

**Inference:**

```bash
--policy.path=models/act_pick_v1
```

**Full autonomous demo (pick → plug → pour)** when all three folders exist:

```bash
./scripts/run_full_demo_github_models.sh
```

Task 1 only (pick) with vendored weights: `./scripts/task1_autonomous_github_models.sh`.

**Size:** each checkpoint is on the order of **~200 MB** (`model.safetensors`), so GitHub stores weights through **LFS** (install: `git lfs install`).

## Tasks 2 & 3 — Plug and pour

Create [SurajCreation/act_plug_v1](https://huggingface.co/SurajCreation/act_plug_v1) and [SurajCreation/act_pour_v1](https://huggingface.co/SurajCreation/act_pour_v1) on Hugging Face (or copy `pretrained_model` from local training into `models/act_plug_v1/` and `models/act_pour_v1/`), then re-run `sync_models_from_hf.py` or commit those directories.
