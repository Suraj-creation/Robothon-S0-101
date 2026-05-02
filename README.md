# Robothon SO-101 — Full-Stack Imitation Learning & Autonomous Task Sequencing

This repository contains the **end-to-end pipeline** for the hackathon’s **three SO-101 tasks** on a **MacBook Air M4** with a **WOWROBO SO-ARM101** (LeRobot **SO101**) setup: teleoperation, LeRobot datasets, **ACT (Action Chunking Transformer)** training, optional **GPU training on Google Colab**, and **autonomous execution** of all three tasks in sequence without operator intervention during the run.

### ACT training status — all three tasks

**Separate ACT policies were trained for every Robothon task:** **pick & place (Task 1)**, **charger plug (Task 2)**, and **liquid pour (Task 3)** — each with its own `lerobot-train` run (`scripts/task*_train.sh` or chained `./scripts/train_all.sh`), using the collected demos and matching hyperparameters in `scripts/task*_env.sh`. Optional **GPU retraining / refinement** uses the same ACT architecture via [`cloud/lerobot_train_colab.ipynb`](cloud/lerobot_train_colab.ipynb) with datasets on the Hub.

**Where the weights live:**

| Task | Policy run name (local `outputs/`) | Published in this GitHub repo |
|------|-------------------------------------|-------------------------------|
| Task 1 — Pick | `outputs/act_pick_v1/` | Yes — [`models/act_pick_v1/`](models/act_pick_v1/) (~82 MB) |
| Task 2 — Plug | `outputs/act_plug_v1/` | Copy `checkpoints/last/pretrained_model` → `models/act_plug_v1/` if you want it on GitHub (same layout as Task 1) |
| Task 3 — Pour | `outputs/act_pour_v1/` | Same — `models/act_pour_v1/` |

Training artifacts under `outputs/` remain **gitignored** by default (large checkpoints). Only bundles you explicitly copy into [`models/`](models/) are versioned here. You can also host policies as **Hugging Face Models** (e.g. after Colab) for `huggingface-cli download`.

**Public repo:** [github.com/Suraj-creation/Robothon-S0-101](https://github.com/Suraj-creation/Robothon-S0-101)

**Hugging Face datasets (mirrors of local demos):** [SurajCreation — dataset activity](https://huggingface.co/SurajCreation/activity/datasets) — includes [`so101_pick_v1`](https://huggingface.co/datasets/SurajCreation/so101_pick_v1), [`so101_plug_v1`](https://huggingface.co/datasets/SurajCreation/so101_plug_v1), and [`so101_pour_v1`](https://huggingface.co/datasets/SurajCreation/so101_pour_v1).

**ACT weights on GitHub:** Task 1 is vendored as a full LeRobot `pretrained_model` bundle in [`models/act_pick_v1/`](models/act_pick_v1/) (~82 MB). Use `--policy.path=models/act_pick_v1` after clone. Tasks 2–3 use the same file layout under `outputs/act_*_v1/checkpoints/last/pretrained_model` locally; add them under `models/act_plug_v1` and `models/act_pour_v1` to mirror on GitHub. Details: [`models/README.md`](models/README.md).

---

## Table of contents

1. [What we built](#what-we-built)
2. [Competition tasks (problem statement)](#competition-tasks-problem-statement)
3. [Architecture at a glance](#architecture-at-a-glance)
4. [What has been achieved](#what-has-been-achieved)
5. [Repository layout](#repository-layout)
6. [Environment & hardware](#environment--hardware)
7. [Data: where episodes live](#data-where-episodes-live)
8. [Workflow: one loop per task](#workflow-one-loop-per-task)
9. [Training (local CPU vs Colab GPU)](#training-local-cpu-vs-colab-gpu)
10. [Autonomous execution (all three tasks)](#autonomous-execution-all-three-tasks)
11. [Documentation map](#documentation-map)
12. [Safety & expectations](#safety--expectations)

---

## What we built

| Layer | Choice | Why |
|--------|--------|-----|
| **Robot control & data** | [LeRobot](https://github.com/huggingface/lerobot) `0.5.1` | Official SO-101 support, `lerobot-record` / `lerobot-train`, dataset format |
| **Policy** | **ACT** (`--policy.type=act`) | Standard for SO-101 imitation learning; chunk-based actions |
| **Cameras** | **Dual RGB**: overhead (e.g. phone as UVC) + wrist USB | Better generalization; wrist view critical for precision (e.g. plug) |
| **Optional perception gate** | **YOLO11n** (`yolo11n.pt`) | Lightweight “is the object present?” gating between phases — not full pose tracking |
| **Sequencer** | Bash + Python (`run_full_demo.sh` / `run_full_demo.py`) | No ROS 2 / MoveIt on this Mac path; loads policies and resets HOME between tasks |
| **Training on Mac** | **CPU** (`--policy.device=cpu`) | PyTorch **MPS** blocked on macOS 26.x version parsing at time of setup; CPU is reliable |
| **Faster training** | **Colab T4** / optional cloud | Same `lerobot-train` stack; datasets on Hugging Face Hub |

---

## Competition tasks (problem statement)

From [`robot-spec.md`](robot-spec.md) (aligned with the semifinal brief):

| Task | Goal |
|------|------|
| **Task 1 — Pick & place** | Detect/grasp an object at a known region, move it, place precisely at a target |
| **Task 2 — Charger plugging** | Grasp connector, align to socket, insert until seated |
| **Task 3 — Liquid pouring** | Grasp bottle, position above cup, tilt and pour to target behavior |

**Task 4** in the spec (humanoid walking) is **out of scope** for this repo.

---

## Architecture at a glance

```
┌─────────────────────────────────────────────────────────────┐
│  Two RGB cameras: overhead + wrist (640×480 @ 30 Hz)      │
│  + 6-DOF follower joint state / actions                     │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Three separate ACT policies (one trained per task)         │
│  pick  →  plug  →  pour   (loaded sequentially on deploy) │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  SO-101 follower (Feetech servos, calibrated)             │
└─────────────────────────────────────────────────────────────┘

Optional: YOLO11n for coarse object presence / phase gating (not required for core ACT deployment).
```

---

## What has been achieved

### Data & calibration

- **Smoke tests** for recording pipelines (Tasks 1–3), with scripts that avoid stale dataset folder collisions.
- **Full demo collection** for all three tasks with **consistent schema**: 6-DoF state/action, **two cameras**, same resolution/FPS, fixed workspace layout.
- **Per-task and canonical HOME poses** captured into [`scripts/home_pose.json`](scripts/home_pose.json) (from demo start poses) so autonomous runs begin in distribution.

### Training & automation scripts

- **Per-task env scripts** (`scripts/task1_env.sh` … `task3_env.sh`): ports, camera indices, repo IDs, hyperparameters, `--dataset.root` for LeRobot 0.5.x.
- **Recording**: `task*_record.sh`, **training**: `task*_train.sh`, **eval**: `task*_eval.sh`.
- **One-shot local training**: [`scripts/train_all.sh`](scripts/train_all.sh) chains **all three ACT trainings** sequentially (with logging under `outputs/training_logs/`).
- **Autonomous single-task deploy**: e.g. [`scripts/task1_autonomous_pick_place.sh`](scripts/task1_autonomous_pick_place.sh) for Task-1-only policy rollout with `lerobot-record --policy.path=...`.

### Full autonomous sequence (three tasks)

- **[`scripts/run_full_demo.sh`](scripts/run_full_demo.sh)** (primary): after training, runs **pick → plug → pour** with **task-specific `go_home`** between phases and policy deployment via `lerobot-record` and trained checkpoints.
- **[`scripts/run_full_demo.py`](scripts/run_full_demo.py)**: in-process variant using LeRobot inference primitives (`make_policy`, `predict_action`, processors).

This is the **“press go once”** path for the competition narrative: operator prepares the scene, starts the script; **no manual intervention during the timed sequence** (subject to real-world policy success).

### Cloud & Hugging Face

- **Datasets uploaded** to Hugging Face under **`SurajCreation/`** so Colab or other GPUs can `snapshot_download` and train without copying multi‑hundred‑MB folders by hand. See activity: [huggingface.co/SurajCreation/activity/datasets](https://huggingface.co/SurajCreation/activity/datasets).
- **[`cloud/lerobot_train_colab.ipynb`](cloud/lerobot_train_colab.ipynb)**: multi-task Colab notebook (GPU), streaming logs, resume-friendly paths, optional push of trained **model** repos.
- **[`cloud/CLOUD_TRAINING.md`](cloud/CLOUD_TRAINING.md)** & **[`cloud/upload_resume.py`](cloud/upload_resume.py)**: Hub upload / resume notes and tooling.
- **[`cloud/modal_train.py`](cloud/modal_train.py)**: optional Modal.com GPU training entrypoint.

---

## Repository layout

| Path | Purpose |
|------|---------|
| [`AUTOMATION_PLAN_M4.md`](AUTOMATION_PLAN_M4.md) | **Master runbook**: commands, checklist, training budget, sequencer behavior |
| [`robot-spec.md`](robot-spec.md) | Problem statement & task definitions |
| [`SO101_COMPLETE_SETUP_AND_TASK_RUNBOOK.md`](SO101_COMPLETE_SETUP_AND_TASK_RUNBOOK.md) | Setup & operations reference |
| [`SO101_Task1_PickPlace_Refined_Architecture.md`](SO101_Task1_PickPlace_Refined_Architecture.md) | Early architecture notes (superseded by automation plan for Mac path) |
| [`environment.yml`](environment.yml) | Conda-style dependency snapshot |
| [`scripts/`](scripts/) | All shell entrypoints, `go_home.py`, `capture_home.py`, `camera_probe.py`, full-demo runners |
| [`models/`](models/) | **Published ACT checkpoints** (Task 1 `act_pick_v1` on GitHub; add plug/pour here to mirror) — not the full gitignored `outputs/` tree |
| [`cloud/`](cloud/) | Colab notebook, cloud training docs, Modal script |
| [`yolo11n.pt`](yolo11n.pt) | Pretrained YOLO11n weights for optional gating |

---

## Environment & hardware

- **Robot:** WOWROBO SO-ARM101 dual arm; hackathon naming: **LeRobot SO101** follower + leader for teleop.
- **Conda env:** project uses a local env at `.conda/` (see `AUTOMATION_PLAN_M4.md` for versions). Activate it before running scripts:
  ```bash
  conda activate /path/to/FInal_robothon/.conda
  ```
- **Cameras:** verify indices every session (`lerobot-find-cameras` or `scripts/camera_probe.py`). Documented indices in practice: **`OVERHEAD_INDEX=0`**, **`WRIST_INDEX=1`** (adjust in `task*_env.sh` if your machine enumerates differently).
- **Serial:** follower/leader USB ports are set in `scripts/task1_env.sh` (single source duplicated in task2/3 envs).

---

## Data: where episodes live

Local LeRobot datasets (default namespace `local/` in `HF_USER`):

| Task | Local dataset root |
|------|---------------------|
| Pick & place | `~/.cache/huggingface/lerobot/local/so101_pick_v1` |
| Charger plug | `~/.cache/huggingface/lerobot/local/so101_plug_v1` |
| Pour | `~/.cache/huggingface/lerobot/local/so101_pour_v1` |

**Hugging Face mirrors (for Colab / sharing):**

- [SurajCreation/so101_pick_v1](https://huggingface.co/datasets/SurajCreation/so101_pick_v1)
- [SurajCreation/so101_plug_v1](https://huggingface.co/datasets/SurajCreation/so101_plug_v1)
- [SurajCreation/so101_pour_v1](https://huggingface.co/datasets/SurajCreation/so101_pour_v1)

Eval / autonomous **recording** runs use separate `repo_id`s and roots (see `task*_eval.sh` and `run_full_demo.sh`).

---

## Workflow: one loop per task

For each task the loop is the same:

1. **Fixture workspace** — taped zones, fixed cameras, lighting (see `AUTOMATION_PLAN_M4.md`).
2. **Smoke test** — `task*_smoketest.sh`.
3. **Collect demos** — `task*_record.sh` (teleop), `--resume` if interrupted.
4. **Train** — `task*_train.sh` or [`train_all.sh`](scripts/train_all.sh).
5. **Eval** — `task*_eval.sh`.

---

## Training (local CPU vs Colab GPU)

| Mode | When to use |
|------|-------------|
| **Local** `./scripts/train_all.sh` | Overnight on M4; uses compressed step budget in env scripts for ~8 h total (see plan doc). |
| **Colab** [`cloud/lerobot_train_colab.ipynb`](cloud/lerobot_train_colab.ipynb) | Faster iterations on **T4 GPU**; datasets pulled from `SurajCreation/so101_*` on the Hub. |

**Note:** Do not commit Hugging Face tokens. Use `huggingface-cli login` or Colab `login()` interactively.

---

## Autonomous execution (all three tasks)

** Preconditions:** Trained checkpoints exist under `outputs/act_*_v1/checkpoints/last/pretrained_model` (names match your `task*_env.sh` `TASK*_OUTPUT_DIR`).

From repo root:

```bash
cd /path/to/FInal_robothon
./scripts/run_full_demo.sh
```

High-level behavior (see `AUTOMATION_PLAN_M4.md` §11.3):

1. `go_home pick` → run pick policy  
2. `go_home plug` → run plug policy  
3. `go_home pour` → run pour policy  
4. Final `go_home`

**Task 1 only** (single-policy autonomous pick):

```bash
./scripts/task1_autonomous_pick_place.sh --yes
```

If `lerobot-train` is still running and you accept shared CPU load:

```bash
./scripts/task1_autonomous_pick_place.sh --allow-while-training --display-data false --yes
```

---

## Documentation map

| Document | Contents |
|----------|----------|
| [`AUTOMATION_PLAN_M4.md`](AUTOMATION_PLAN_M4.md) | Full command reference, status, training budget, failure playbook |
| [`robot-spec.md`](robot-spec.md) | Official task wording & constraints |
| [`cloud/CLOUD_TRAINING.md`](cloud/CLOUD_TRAINING.md) | Colab vs Modal vs Hub |
| [`SO101_CURRENT_STATUS.md`](SO101_CURRENT_STATUS.md) | Historical bring-up notes (verify against your current hardware) |

---

## Safety & expectations

- Respect **payload (~400 g)** and **calibration** per manufacturer guidance ([LeRobot SO-101 docs](https://huggingface.co/docs/lerobot/so101)).
- ACT policies **memorize the fixed workspace**; moving cameras or fixtures breaks generalization until new data is collected.
- **Success rates** depend on data volume, consistency of demos, and training steps; the automation plan documents realistic first-pass expectations under compressed budgets.
- macOS may print benign **`objc` / libavdevice** warnings when opening cameras; they are usually non-fatal if streaming works.

---

## Citation & upstream

- **LeRobot:** [Hugging Face LeRobot](https://github.com/huggingface/lerobot)  
- **Robot platform:** [LeRobot SO-101 documentation](https://huggingface.co/docs/lerobot/so101)

---

*README generated to reflect the Robothon SO-101 pipeline: imitation learning, Hub-backed datasets, and autonomous three-task sequencing. For exact hyperparameters and day-of commands, always treat [`AUTOMATION_PLAN_M4.md`](AUTOMATION_PLAN_M4.md) as the operational source of truth.*
