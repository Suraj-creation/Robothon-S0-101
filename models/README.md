# Published ACT checkpoints (all three Robothon tasks)

The project **trains a separate LeRobot ACT policy for each task** (pick, plug, pour). This folder holds **released** policy weights so they can be versioned on GitHub without tracking the full `outputs/` training tree (which stays local and gitignored).

## Task 1 — Pick & place (included in this repo)

| Path | Description |
|------|-------------|
| [`act_pick_v1/`](act_pick_v1/) | LeRobot ACT **pretrained_model** bundle: `config.json`, `model.safetensors`, pre/postprocessor JSON + small `.safetensors` stats, `train_config.json` |

**Load in LeRobot** (inference / `lerobot-record --policy.path=...`):

```bash
--policy.path=models/act_pick_v1
```

Or after `git clone`, use the absolute path to `.../models/act_pick_v1`.

**Size:** ~82 MB total (dominated by `model.safetensors`).

**Source run:** Copied from `outputs/act_pick_v1/checkpoints/last/pretrained_model` after local or Colab training. Re-copy when you retrain and want to update the public checkpoint.

## Tasks 2 & 3 — Plug and pour (same layout when mirrored here)

After training completes locally (`outputs/act_plug_v1`, `outputs/act_pour_v1`) or you download checkpoints from Hugging Face Models, copy each **`pretrained_model`** directory into:

- `models/act_plug_v1/`
- `models/act_pour_v1/`

Then commit and push — same usage as Task 1 with `--policy.path=models/act_plug_v1` etc.

> **Why only Task 1 might be on GitHub:** Each full checkpoint is ~80 MB+. Add Tasks 2–3 here when you want them cloned without Hugging Face or local `outputs/`.
