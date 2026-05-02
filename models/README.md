# Published ACT checkpoints (Task 1)

This folder holds **released** policy weights so they can be versioned on GitHub without tracking the full `outputs/` training tree (which stays local and gitignored).

## Task 1 — Pick & place

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

> **Note:** Task 2 and Task 3 policies can be added as `act_plug_v1/`, `act_pour_v1/` the same way when you are ready to pin them in the repo.
