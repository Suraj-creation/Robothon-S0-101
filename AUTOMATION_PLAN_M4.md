# SO‑101 Full Automation Plan — MacBook Air M4 (24 GB)

**Supersedes:** `SO101_Task1_PickPlace_Refined_Architecture.md` (kept as reference; ROS 2 / MoveIt 2 / RealSense / FoundationPose / GR00T are **out of scope** on macOS).

**Scope:** Bring all three Robothon tasks (Pick & Place, Charger Plugging, Liquid Pouring) to **autonomous execution** on your existing hardware, using only what already works on macOS + your `.conda` env.

**Hardware confirmed:** MacBook Air M4 · 10-core (4P+6E) · 24 GB unified memory · macOS 25.4.

**Software confirmed (in `.conda`):**
`python 3.12.13`, `lerobot 0.5.1`, `torch 2.10.0` (MPS built), `mujoco 3.8.0`, `ultralytics 8.4.45` (YOLO11), `opencv-python 4.13`, `huggingface_hub 1.13`, `einops`, `wandb`.

**Robot ports:**
Leader `/dev/tty.usbmodem5B140318771` · Follower `/dev/tty.usbmodem5B141124491`.

---

## 0. Corrections to the Plan You Wrote

| You wrote | Reality | What to use |
|---|---|---|
| `--policy.type=bc` | Not in `lerobot 0.5.1`. Allowed: `act, diffusion, smolvla, pi0, pi0_fast, pi05, vqbet, tdmpc, …` | **`act`** (Action Chunking Transformer). It is what every public SO‑101 demo uses. |
| `lerobot-run` | Doesn't exist | `lerobot-record --policy.path=outputs/<run>/checkpoints/last/pretrained_model` — records while running the policy as the controller. |
| "YOLO26" | No such model. Latest stable Ultralytics models are YOLO11 (Sep 2024) and YOLO12 (early 2025). | **YOLO11n** (`yolo11n.pt`, already downloaded to repo root) — fastest, 5–8 ms/frame on M4. Plenty for cube/connector/bottle. |
| ROS 2 + MoveIt 2 + BehaviorTree.CPP | Linux-first; on macOS this is days of pain and Docker GPU passthrough is broken for cameras/serial. | Skip. Use a **Python sequencer + lerobot policies + YOLO gates**. |
| RealSense D435i | You don't need depth. ACT is RGB-only end-to-end. | UVC webcams only. |
| MPS (Apple GPU) for training | **Blocked on macOS 26.4.1.** `torch 2.10` and even today's nightly fail with "MPS backend is supported on macOS 14.0+" — torch's runtime version check doesn't recognize `26.x` (Apple jumped to year-based versioning in late 2025). Confirmed broken even on `torch-2.13.0.dev20260501`. | **Train on CPU** (`--policy.device=cpu`). M4 has 10 cores, 24 GB; Task 1 ACT trains in ~7 hours overnight. We try MPS again only if a future torch wheel fixes it. |

---

## 1. What You Are Actually Building

```
     ┌────────────────────────────────────────┐
     │  Overhead USB Camera (RGB, 1080p)      │
     └───────────────┬────────────────────────┘
                     │ image
                     ▼
     ┌────────────────────────────────────────┐
     │  Per-task ACT policy (trained on demos)│
     │  Input :  image  +  6 follower joints  │
     │  Output:  next 50 joint targets        │
     └───────────────┬────────────────────────┘
                     │ joint targets @ 30 Hz
                     ▼
     ┌────────────────────────────────────────┐
     │   SO-101 Follower (servo bus)          │
     └────────────────────────────────────────┘

     ┌────────────────────────────────────────┐
     │   Task Sequencer (Python)              │
     │   detect_state → pick → plug → pour    │
     │   Uses YOLO11 ONLY for "is the object  │
     │   present?" gating + a HOME pose       │
     │   between tasks                        │
     └────────────────────────────────────────┘
```

Three policies, one each:
- `act_pick_place`
- `act_charger_plug`
- `act_pour`

A small Python sequencer loads them in order. YOLO11 is the only "perception" component, used as a **gate** ("Is the cube on the mat? Is the connector visible? Is the bottle in the gripper?") between phases — not for full 6D pose estimation.

This is the **fastest path to a working autonomous demo on a Mac**.

---

## 2. Hardware Additions (Buy / Set Up)

You already have **two cameras** plugged in:

| What | Detected as | Role in this plan |
|---|---|---|
| **Wrist cam** (already mounted on follower) | `USB2.0_CAM1` (UVC, VID 1443, PID 37424) | `wrist` view — close-up of the gripper, critical for Task 2 (charger plug) and useful for Task 1 grasp accuracy |
| **Android phone webcam** (tethered) | `Android Webcam` (UVC, VID 6353/0x18D1) | `overhead` view — wide shot of the whole worktop, primary view for Task 1 (pick & place) and Task 3 (pour) |
| MacBook Air built-in (FaceTime) | `MacBook Air Camera` | **Do not use.** Wrong angle. |

### 2.1 Do you need both cameras for Task 1? — Yes.

You asked. Honest answer: **use both.** Reasons:
1. The wrist cam is **already physically mounted** on the follower — you've paid for that work, throwing it away makes the model strictly weaker.
2. Every public SO‑101 ACT checkpoint that actually works (`davidlinjiahao/lerobot_so101_base_sim_pickplace`, the LeRobot SO-101 cookbook, the HuggingFace tutorials) trains on **2 cameras**. Single-cam ACT on SO-101 routinely fails to align in depth.
3. Task 2 (charger plug) **requires** a wrist view. You'd have to retrofit it later anyway, and re-collect Task 2 demos.
4. Cost: training time goes up only ~25–35 % on M4 CPU. Inference at 30 Hz is fine — two 640×480 frames is ~2 MB/s combined, well within USB and CPU budget.
5. macOS **does** allow two USB UVC cameras open at once. The Android-as-webcam adapter (DroidCam / Camo / Continuity) presents as a normal UVC device.

> The only situation where I'd pick single-cam: the Android phone tether is unreliable (it drops frames or disconnects). If you see that during the smoke test, switch to a $30 Logitech C270 instead. **Do not** keep the wrist cam unused.

### 2.2 Camera placement rules (non-negotiable)

| Camera | Position | Mount | Frozen? |
|---|---|---|---|
| `overhead` (Android phone) | Static, ~50 cm above the worktop, looking straight down. Tilt 0–15°. | Phone tripod or desk arm clamp. **Lock physically.** Plug in the charger so it never sleeps. | YES — once placed, do not move for the entire project. If it shifts 1 cm, all demos for that task become invalid. |
| `wrist` (USB UVC on follower) | As mounted | Already done | The camera moves WITH the gripper — that's the point. The mount on the follower must be tight. |

### 2.3 Worktop fixture (non-negotiable, takes 30 minutes)

Tape down on a matte non-reflective mat (A3 black foam board is ideal):
- **Robot base position** — mark with masking tape so you can re-seat the arm if it gets bumped.
- **3 object zones** — small squares drawn with marker, one per task:
  - `PICK_ZONE` (10×10 cm) — where the cube starts.
  - `DROP_ZONE` (10×10 cm) — pick & place target.
  - `SOCKET_ZONE` — fixture holding the charger socket. Hot-glue a USB / DC socket to a wood block, then clamp/screw the block to the table so it cannot rotate.
  - `CUP_ZONE` — pouring receiver. Heavy mug, taped down.
- **Lighting** — one constant light source. No window light that shifts during the day. This is the single biggest cause of policy failure on Mac setups.

> **Why this matters:** ACT is end-to-end. It will memorize "the cube is at *this* pixel position when I grasp." If the camera moves or the lighting changes, the policy fails. Fix the world once, then collect demos.

### 2.4 Identify which camera index is which (run this first)

macOS reports OpenCV indices in AVFoundation enumeration order, which is not deterministic across reboots. You must probe every session and confirm. Two ways — use either:

**Option A (LeRobot's official tool):**
```bash
cd /Users/udbhavkulkarni/Desktop/FInal_robothon
.conda/bin/lerobot-find-cameras opencv \
  --record-time-s 4 \
  --output-dir camera_probe
open camera_probe/
```
This opens each detected UVC camera, writes a sample frame, and prints the index/resolution/fps. Match each saved JPEG to a physical camera by eye.

**Option B (the script in this repo):**
```bash
.conda/bin/python scripts/camera_probe.py
open camera_probe/
```

**Both require macOS Camera permission first.** When you run either command the very first time, macOS pops a TCC permission prompt. If you don't see one (because you ran it inside Cursor, which suppresses some prompts), grant manually:

> System Settings → Privacy & Security → Camera → toggle ON for **Terminal** (or **iTerm** / **Cursor**, whichever app you're running the command from). You may need to fully quit and relaunch that app once after granting.

Expected result: 3 saved frames — `cam_index_0_*.jpg`, `cam_index_1_*.jpg`, `cam_index_2_*.jpg`. Identify them:

| File | What you should see |
|---|---|
| FaceTime view (your face, low angle from screen) | **MacBook Air built-in** — note the index, do **not** use it |
| Top-down view of worktop / robot arm from above | This is your **overhead** (Android phone) — note the index |
| View from inside the gripper / close-up of the arm | This is your **wrist** cam — note the index |

Write the two indices down. You will use them as `OVERHEAD_INDEX` and `WRIST_INDEX` in every command below. Common results on macOS: built-in is usually `0`, the two USB cams take `1` and `2`, but **don't trust order — confirm by eye.**

---

## 3. Software Status (already 100 % installed — verified)

Verified present in `.conda` on **May 1, 2026**:

| Component | Version | Used for |
|---|---|---|
| `python` | 3.12.13 | runtime |
| `lerobot` | 0.5.1 | training, recording, replay, eval |
| `torch` / `torchvision` | 2.10.0 / 0.25.0 | ACT model |
| `mujoco` | 3.8.0 | optional sim playground |
| `gymnasium` | 1.3.0 | sim env wrappers |
| `ultralytics` | 8.4.45 | YOLO11n (weights `yolo11n.pt` already at repo root) |
| `opencv-python` | 4.13.0.92 | camera capture |
| `rerun-sdk` | 0.26.2 | **live data viewer** (opens automatically with `--display_data=true`) |
| `huggingface_hub` | 1.13.0 | dataset upload (optional) |
| `wandb` | 0.24.2 | training curves (optional) |
| `accelerate` | 1.13.0 | multi-process training utilities |
| `datasets` | 4.8.5 | LeRobot dataset format |
| `av` (PyAV) | 15.1.0 | video encoding for episodes |
| `einops`, `matplotlib`, `scipy` | latest | misc |

LeRobot CLIs verified on PATH: `lerobot-record`, `lerobot-train`, `lerobot-teleoperate`, `lerobot-eval`, `lerobot-replay`, `lerobot-calibrate`, `lerobot-find-cameras`, `lerobot-find-port`, `lerobot-find-joint-limits`, `lerobot-dataset-viz`, `lerobot-imgtransform-viz`, `lerobot-info`. Plus standalone `rerun` (the desktop viewer) and `yolo`.

**There is nothing to install.** Skip to §3.1.

### 3.1 Compute reality on macOS 26.4.1 — train on CPU

Your platform is `macOS 26.4.1` (Tahoe; Apple's year-based versioning that started in late 2025). Verified diagnostic:

```text
torch:           2.10.0
mps_built:       True
mps_available:   False
mps_alloc:       FAILED — "MPS backend is supported on macOS 14.0+. Current OS version can be queried using sw_vers"
```

Tested also on `torch-2.13.0.dev20260501` (today's nightly): same failure. PyTorch's runtime macOS-version check rejects `26.x`. There is **no fix today** other than a future torch release. So:

**All training runs use `--policy.device=cpu`.** With 24 GB unified memory and 10 cores (4P+6E), Task 1 ACT trains in ~7 hours overnight. We re-test MPS only when a new `torch>=2.11` wheel ships that knows about macOS 26.

> If you're determined to have GPU acceleration: the only working route on macOS 26 today is **Apple's MLX** library. ACT is not yet ported to MLX. Don't burn hackathon time on this; CPU works.

### 3.2 (Optional) Enable Hugging Face uploads

If you want datasets and checkpoints backed up to HF:
```bash
.conda/bin/huggingface-cli login
```
Then add `--dataset.push_to_hub=true` to record commands and `--wandb.enable=true` to training. Both are optional; everything works locally without them.

---

## 4. The Five-Stage Workflow (Repeated Once Per Task)

This is the loop. Execute it three times — Task 1, Task 2, Task 3. The commands are nearly identical, only the `repo_id`, episode count, and demo behavior change.

```
┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ A. Fixture  │──>│ B. Demos    │──>│ C. Train    │──>│ D. Deploy   │──>│ E. Iterate  │
│ Lock world  │   │ Teleop +    │   │ ACT on MPS  │   │ Policy ctrls│   │ Add demos   │
│ Mark zones  │   │ camera rec  │   │ ~3-8h/task  │   │ follower    │   │ for failures│
└─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘
```

### Stage A — Fixture (you do this once, total)

Already specified in §2.2. After this is set, **do not move the camera, the robot base, the cup, or the socket fixture for the rest of the project.** If you have to move anything, all demos for that task are invalid and must be re-collected.

### Stage B — Record demonstrations

Generic command (replace `<OVERHEAD_INDEX>`, `<WRIST_INDEX>` from §2.4, and `<repo>`, `<N>`, `<task_text>` per task — see §5–7):

```bash
cd /Users/udbhavkulkarni/Desktop/FInal_robothon
source .conda/bin/activate ./.conda    # or: conda activate ./.conda

lerobot-record \
  --robot.type=so101_follower \
  --robot.port=/dev/tty.usbmodem5B141124491 \
  --robot.id=so101_follower_main \
  --robot.cameras='{
      overhead: { type: opencv, index_or_path: <OVERHEAD_INDEX>, width: 640, height: 480, fps: 30 },
      wrist:    { type: opencv, index_or_path: <WRIST_INDEX>,    width: 640, height: 480, fps: 30 }
    }' \
  --teleop.type=so101_leader \
  --teleop.port=/dev/tty.usbmodem5B140318771 \
  --teleop.id=so101_leader_main \
  --display_data=true \
  --dataset.repo_id=<your_hf_user>/<repo> \
  --dataset.num_episodes=<N> \
  --dataset.episode_time_s=20 \
  --dataset.reset_time_s=8 \
  --dataset.fps=30 \
  --dataset.single_task="<task_text>"
```

> Note: `--robot.cameras='{...}'` is a YAML-ish dict literal in single quotes. Keep it on one line if your shell complains about multi-line single-quoted strings.

What each value does:
- `episode_time_s=20` — give yourself 20 seconds per attempt (enough for any of the three tasks if you teleop slowly).
- `reset_time_s=8` — 8 seconds between episodes to put the cube/connector back.
- `fps=30` — match the camera. Don't go higher — bus bandwidth and disk IO get worse fast on macOS.
- `display_data=true` — opens a `rerun` window so you see camera + joints live.
- `single_task="..."` — a short text label; ACT ignores it but it makes the dataset card readable.

**Demo discipline (matters more than the model):**
1. Move **slowly and smoothly** with the leader. Robot's max speed during deployment is roughly your demo speed.
2. **Same trajectory shape every time**, only the start position varies.
3. **Vary the object's position deliberately** — for Task 1, place the cube in a 5×5 cm grid of 9 positions, do 3–4 demos at each. The policy will only generalize to the area you sampled.
4. Reset the world cleanly between episodes — same arm home pose, same object zone.
5. **Discard bad episodes immediately** — `lerobot-record` lets you press a key to drop the last episode. If you fumbled, drop it. Bad demos poison the model.
6. **Lighting must not change** during the recording session. Don't record half during day, half at night.

### Stage C — Train ACT (CPU on macOS 26)

```bash
lerobot-train \
  --dataset.repo_id=<your_hf_user>/<repo> \
  --policy.type=act \
  --policy.device=cpu \
  --policy.dim_model=512 \
  --policy.n_heads=8 \
  --policy.chunk_size=50 \
  --policy.n_action_steps=50 \
  --policy.use_vae=true \
  --policy.kl_weight=10.0 \
  --policy.optimizer_lr=1e-5 \
  --batch_size=4 \
  --steps=80000 \
  --save_freq=10000 \
  --log_freq=200 \
  --output_dir=outputs/<run_name> \
  --job_name=<run_name> \
  --wandb.enable=false
```

Run with the laptop **plugged in**, lid open, on a hard surface (so the fan vents). M4 Air has no fan — it will thermal-throttle if you stack it on bedding, which can double training time.

Time budget on M4 Air (CPU, batch_size=4, 2 cameras):

| `--steps` | Wall-clock | Used by |
|---|---|---|
| 30 000 | ~4–5 h | first sanity run |
| **50 000** | **~7–9 h** | **Task 1, Task 3** |
| **80 000** | **~11–14 h** | **Task 2** |

Start training before bed. By morning Task 1 is done.

> **If a future torch update ever fixes MPS on macOS 26**, just change `--policy.device=cpu` to `--policy.device=mps` and `--batch_size=4` to `--batch_size=8`. Everything else stays the same. Re-test with `python -c "import torch; print(torch.backends.mps.is_available())"`.

### Stage D — Deploy autonomously

```bash
# Path is created by lerobot-train inside outputs/<run_name>/checkpoints/last/
POLICY=$PWD/outputs/<run_name>/checkpoints/last/pretrained_model

lerobot-record \
  --robot.type=so101_follower \
  --robot.port=/dev/tty.usbmodem5B141124491 \
  --robot.id=so101_follower_main \
  --robot.cameras='{
      overhead: { type: opencv, index_or_path: <OVERHEAD_INDEX>, width: 640, height: 480, fps: 30 },
      wrist:    { type: opencv, index_or_path: <WRIST_INDEX>,    width: 640, height: 480, fps: 30 }
    }' \
  --display_data=true \
  --dataset.repo_id=<your_hf_user>/eval_<repo> \
  --dataset.num_episodes=10 \
  --dataset.episode_time_s=25 \
  --dataset.reset_time_s=8 \
  --dataset.fps=30 \
  --dataset.single_task="<task_text>" \
  --policy.path=$POLICY
```

Note: `--teleop.*` is **omitted** — the policy drives the follower. The leader can sit there. The command also records the autonomous runs, which is gold for failure analysis.

You can also replay any recorded episode (teleop or autonomous) without policy:
```bash
lerobot-replay \
  --robot.type=so101_follower \
  --robot.port=/dev/tty.usbmodem5B141124491 \
  --robot.id=so101_follower_main \
  --dataset.repo_id=<your_hf_user>/<repo> \
  --episode 0
```
That's useful for debugging "is the follower physically able to repeat this trajectory?" before training.

### Stage E — Iterate

Watch every autonomous episode. For each failure, write down:
- Which phase failed (approach? grasp? release?)
- Was the object in a position you had demos for?
- Did the policy hesitate or move confidently?

Then **add 5–10 fresh demos that specifically cover the failure** (e.g. cube at far-left edge), retrain from scratch (or resume) with `--steps` bumped by 20 000. Three iterations of this loop is normally what gets a Mac-trained ACT from 60 % to ~90 %.

---

## 5. Task 1 — Pick & Place

### 5.1 Scene
- `PICK_ZONE`: 10×10 cm, on the mat.
- `DROP_ZONE`: 10×10 cm, ~25 cm away from `PICK_ZONE`.
- Object: a 4 cm cube (printed or wooden), one solid color (red is best for YOLO later).

### 5.2 Demo strategy
- **Episode plan:** 9 cube positions × 4 demos each = **36 episodes**. Bump to **50** if you have time.
- During each demo:
  1. Robot at `HOME` (define a single fixed home pose; record it once).
  2. Pick — top-down approach, close gripper.
  3. Lift 5 cm.
  4. Move to `DROP_ZONE`.
  5. Lower, open gripper.
  6. Return to `HOME`.

### 5.3 Commands

Substitute `<OVERHEAD_INDEX>` and `<WRIST_INDEX>` with the values you found in §2.4. Pick a `<user>` for the dataset path (e.g. `udbhavkulkarni`); it's used for local cache only unless you also `--dataset.push_to_hub=true`.

```bash
# --- Stage B: record 50 demos ---
lerobot-record \
  --robot.type=so101_follower --robot.port=/dev/tty.usbmodem5B141124491 \
  --robot.id=so101_follower_main \
  --robot.cameras='{ overhead: { type: opencv, index_or_path: <OVERHEAD_INDEX>, width: 640, height: 480, fps: 30 }, wrist: { type: opencv, index_or_path: <WRIST_INDEX>, width: 640, height: 480, fps: 30 } }' \
  --teleop.type=so101_leader --teleop.port=/dev/tty.usbmodem5B140318771 \
  --teleop.id=so101_leader_main \
  --display_data=true \
  --dataset.repo_id=<user>/so101_pick_v1 \
  --dataset.num_episodes=50 \
  --dataset.episode_time_s=20 --dataset.reset_time_s=8 --dataset.fps=30 \
  --dataset.single_task="Pick the red cube and place it on the green target."

# --- Stage C: train 50k steps on CPU (~7-9 hours) ---
lerobot-train \
  --dataset.repo_id=<user>/so101_pick_v1 \
  --policy.type=act --policy.device=cpu \
  --policy.chunk_size=50 --policy.n_action_steps=50 \
  --batch_size=4 --steps=50000 --save_freq=10000 --log_freq=200 \
  --output_dir=outputs/act_pick_v1 --job_name=act_pick_v1 \
  --wandb.enable=false

# --- Stage D: deploy autonomously, record 10 eval episodes ---
lerobot-record \
  --robot.type=so101_follower --robot.port=/dev/tty.usbmodem5B141124491 \
  --robot.id=so101_follower_main \
  --robot.cameras='{ overhead: { type: opencv, index_or_path: <OVERHEAD_INDEX>, width: 640, height: 480, fps: 30 }, wrist: { type: opencv, index_or_path: <WRIST_INDEX>, width: 640, height: 480, fps: 30 } }' \
  --display_data=true \
  --dataset.repo_id=<user>/so101_pick_v1_eval --dataset.num_episodes=10 \
  --dataset.episode_time_s=25 --dataset.reset_time_s=8 --dataset.fps=30 \
  --dataset.single_task="Pick and place the cube." \
  --policy.path=outputs/act_pick_v1/checkpoints/last/pretrained_model
```

### 5.4 Targets
| Metric | Acceptable | Good |
|---|---|---|
| Demos | 36 | 50–60 |
| Train steps | 50 000 | 80 000 |
| Eval grasp success | 70 % | 90 % |
| Eval place-in-zone | 60 % | 85 % |

### 5.5 Adding YOLO11 (only after the fixed-position version works)

Train only **one extra detector** for the cube. Used by the sequencer to gate Task 1.

```bash
# Quick "is the cube there?" check used by the sequencer
.conda/bin/python - <<'PY'
from ultralytics import YOLO
import cv2
cap = cv2.VideoCapture(0); cap.set(3,640); cap.set(4,480)
model = YOLO("yolo11n.pt")    # auto-downloaded, ~6 MB
ok, f = cap.read(); cap.release()
res = model(f, verbose=False)[0]
# COCO 'sports ball' / 'apple' / etc give decent OOTB hits for a colored cube.
print([(model.names[int(c)], float(conf))
       for c, conf in zip(res.boxes.cls, res.boxes.conf)])
PY
```

**You do not need a custom-trained YOLO model for Task 1.** A simple HSV color mask in OpenCV beats YOLO for a single solid-colored cube and runs in <1 ms. Use YOLO11 only for Task 2 and 3 where shapes vary.

---

## 6. Task 2 — Charger Plugging (the hardest of the three)

This is precision-critical. Plan for ~3× the demos and ~1.6× the steps.

### 6.1 Scene
- Socket fixture **rigidly bolted/clamped** to the table. Position locked.
- Connector starts in a fixed `CONNECTOR_ZONE` (5×5 cm). The cable can curl, but the connector body should rest in the same orientation each time.

### 6.2 Demo strategy
- **Sub-phase the demos.** Make every episode follow the same 3-phase script:
  1. **Grasp** the connector body (top-down).
  2. **Approach** to a way-point ~3 cm in front of the socket, oriented to match the socket axis.
  3. **Insert** — slow, ~1 cm/s, into the socket until contact.
- **Episode plan:** 3 connector positions × 30 demos = **90 episodes**. Yes, this many. Insertion tolerance is millimeters; ACT needs the data.
- Move **especially slowly** during the insertion phase — the policy mimics your speed.

### 6.3 Commands

```bash
lerobot-record \
  --robot.type=so101_follower --robot.port=/dev/tty.usbmodem5B141124491 \
  --robot.id=so101_follower_main \
  --robot.cameras='{ overhead: { type: opencv, index_or_path: <OVERHEAD_INDEX>, width: 640, height: 480, fps: 30 }, wrist: { type: opencv, index_or_path: <WRIST_INDEX>, width: 640, height: 480, fps: 30 } }' \
  --teleop.type=so101_leader --teleop.port=/dev/tty.usbmodem5B140318771 \
  --teleop.id=so101_leader_main \
  --display_data=true \
  --dataset.repo_id=<user>/so101_plug_v1 \
  --dataset.num_episodes=90 \
  --dataset.episode_time_s=25 --dataset.reset_time_s=10 --dataset.fps=30 \
  --dataset.single_task="Grasp the charger connector and plug it into the socket."

lerobot-train \
  --dataset.repo_id=<user>/so101_plug_v1 \
  --policy.type=act --policy.device=cpu \
  --policy.chunk_size=80 --policy.n_action_steps=80 \
  --policy.kl_weight=20.0 \
  --batch_size=4 --steps=80000 --save_freq=10000 --log_freq=200 \
  --output_dir=outputs/act_plug_v1 --job_name=act_plug_v1 \
  --wandb.enable=false
```

Notes:
- Larger `chunk_size=80` because insertion is a long contiguous motion.
- Higher `kl_weight=20` to reduce mode collapse on near-identical demos.

### 6.4 Hard rule
If the connector misaligns at insertion >1 mm, ACT alone won't fix it consistently — even with 90 demos. The wrist camera you already have is what makes insertion work; if it's still failing after 90 demos:

1. **Re-aim the wrist cam** so the connector tip is fully visible during the last 5 cm of approach. Re-record those 90 demos.
2. **Mechanical compliance**: print/cut a small spring-loaded gripper tip so 1–2 mm misalignment is absorbed mechanically.
3. **More demos at the failure pose** — record 30 extra demos starting *3 cm from socket* (the hardest segment).

### 6.5 Targets
| Metric | Acceptable | Good |
|---|---|---|
| Demos | 90 | 150 |
| Train steps | 80 000 | 120 000 |
| Insertion success | 50 % | 80 % |

---

## 7. Task 3 — Liquid Pouring

Easier than plugging because tolerance is "fluid hits the cup", not "submillimeter alignment".

### 7.1 Scene
- Bottle: small (~150 ml), filled with water (use food coloring for visibility / YOLO if used).
- Cup: heavy mug, taped down at `CUP_ZONE`.
- **Bottle starts already in a fixed gripping pose**, in a small bottle stand. This is way easier than picking up the bottle from a flat surface.

### 7.2 Demo strategy
- **Episode plan:** 2 bottle stand positions × 25 demos = **50 episodes**.
- Per episode:
  1. Pick the bottle from the stand.
  2. Move to a way-point above the cup.
  3. Tilt wrist to ~90°, hold for 2 s.
  4. Tilt back to vertical, return bottle to stand.
- The wrist roll motion is the key signal. Make it identical every time.

### 7.3 Commands

```bash
lerobot-record \
  --robot.type=so101_follower --robot.port=/dev/tty.usbmodem5B141124491 \
  --robot.id=so101_follower_main \
  --robot.cameras='{ overhead: { type: opencv, index_or_path: <OVERHEAD_INDEX>, width: 640, height: 480, fps: 30 }, wrist: { type: opencv, index_or_path: <WRIST_INDEX>, width: 640, height: 480, fps: 30 } }' \
  --teleop.type=so101_leader --teleop.port=/dev/tty.usbmodem5B140318771 \
  --teleop.id=so101_leader_main \
  --display_data=true \
  --dataset.repo_id=<user>/so101_pour_v1 \
  --dataset.num_episodes=50 \
  --dataset.episode_time_s=22 --dataset.reset_time_s=10 --dataset.fps=30 \
  --dataset.single_task="Pick the bottle, pour into the cup, return the bottle."

lerobot-train \
  --dataset.repo_id=<user>/so101_pour_v1 \
  --policy.type=act --policy.device=cpu \
  --policy.chunk_size=60 --policy.n_action_steps=60 \
  --batch_size=4 --steps=50000 --save_freq=10000 --log_freq=200 \
  --output_dir=outputs/act_pour_v1 --job_name=act_pour_v1 \
  --wandb.enable=false
```

### 7.4 Targets
| Metric | Acceptable | Good |
|---|---|---|
| Demos | 50 | 80 |
| Train steps | 50 000 | 80 000 |
| Liquid in cup (no spill) | 70 % | 90 % |

---

## 8. Final Integration — The Task Sequencer

A small Python script that:
1. Loads all three ACT policies.
2. Runs YOLO11 on the camera once per phase to **gate** ("is the next object visible?").
3. Drives the follower through Task 1 → 2 → 3 sequentially.
4. Inserts a `HOME` pose between tasks so each policy starts from the same state it was trained on.

A working sequencer template lives at `scripts/run_full_demo.py` (see file in this repo). The non-obvious parts:

- The correct `lerobot 0.5.1` import path is `lerobot.robots.so_follower.SO101Follower` (the package is `so_follower`, not `so101_follower`; it covers both SO-100 and SO-101 variants).
- `OpenCVCameraConfig` fields are `fps, width, height, index_or_path, color_mode, rotation, warmup_s, fourcc, backend`.
- `SO101FollowerConfig` fields are `port, disable_torque_on_disconnect, max_relative_target, cameras, use_degrees, id, calibration_dir`.
- `DEVICE` should be `cpu` until torch supports macOS 26 MPS.

You **don't need to write this until Tasks 1, 2, 3 each work in isolation.** It's the very last step. The starter template is committed at `scripts/run_full_demo.py` and uses the exact verified import paths.

---

## 9. Optional — Fine-tune YOLO11 on Your Three Objects

Only worth doing if the COCO gate is unreliable.

```bash
mkdir -p datasets/robothon/{images,labels}/{train,val}
# Snap 50–100 photos with the overhead camera, varied lighting/positions.
# Label them with one bbox each via labelImg or roboflow.
# Classes: 0=cube, 1=connector, 2=bottle, 3=cup, 4=socket
```

`datasets/robothon/data.yaml`:

```yaml
path: /Users/udbhavkulkarni/Desktop/FInal_robothon/datasets/robothon
train: images/train
val: images/val
names: [cube, connector, bottle, cup, socket]
```

Train (M4-friendly):
```bash
.conda/bin/yolo detect train \
  data=datasets/robothon/data.yaml \
  model=yolo11n.pt \
  imgsz=640 epochs=80 batch=16 device=mps \
  project=outputs/yolo_robothon name=v1
```

The trained weights go to `outputs/yolo_robothon/v1/weights/best.pt`. Swap that into the sequencer:

```python
yolo = YOLO("outputs/yolo_robothon/v1/weights/best.pt")
```

Total time: ~20 min on M4 (MPS). Use this only after Task 1 works end-to-end.

---

## 10. Training Budget Cheat Sheet (M4 Air, CPU on macOS 26)

Estimates assume `--batch_size=4`, `chunk_size` per task (50 / 80 / 60), 2 cameras at 640×480, no thermal throttling.

| Task | Demos | Steps | Wall-clock (CPU) | Disk used by dataset |
|---|---:|---:|---:|---:|
| Pick & Place | 50 | 50 000 | ~7–9 h | ~1.4 GB |
| Charger Plug | 90 | 80 000 | ~12–14 h | ~3.0 GB |
| Pouring | 50 | 50 000 | ~7–9 h | ~1.6 GB |
| YOLO11n fine-tune (optional, §9) | 100 imgs | 80 epochs | ~1 h | ~50 MB |
| **Total (one full pass)** | **190 demos** | **180 k ACT steps** | **~28 h** | **~6 GB** |

If MPS becomes available later (via a future torch wheel), drop wall-clock by ~2.5×.

Plan to spend ~3 days end-to-end:
- **Day 1:** Hardware fixture + camera + Task 1 demos + train overnight.
- **Day 2:** Task 1 eval + iteration. Task 2 demos + train overnight.
- **Day 3:** Task 2 eval + iteration. Task 3 demos + train overnight.
- **Day 4:** Sequencer integration + dress rehearsal.

---

## 11. CURRENT STATUS — May 2, 2026

### 11.1 What's done

| Phase | Status |
|---|---|
| Hardware setup (cameras locked, fixtures placed) | ✅ DONE |
| macOS Camera permissions, rerun viewer | ✅ DONE |
| Camera probe + index identification | ✅ DONE — `OVERHEAD_INDEX=0` (Android Webcam), `WRIST_INDEX=1` (USB UVC) |
| Smoke tests (Tasks 1, 2, 3) | ✅ DONE — auto-clean smoke datasets so reruns never block |
| **Task 1 demo collection** | ✅ DONE — **50 episodes**, 30,000 frames, 528 MB at `~/.cache/huggingface/lerobot/local/so101_pick_v1` |
| **Task 2 demo collection** | ✅ DONE — **51 episodes**, 38,230 frames, 551 MB at `~/.cache/huggingface/lerobot/local/so101_plug_v1` |
| **Task 3 demo collection** | ✅ DONE — **35 episodes**, 26,250 frames, 510 MB at `~/.cache/huggingface/lerobot/local/so101_pour_v1` |
| HOME pose extraction | ✅ DONE — `scripts/home_pose.json` (averaged from first frames of demos) |
| Autonomous sequencer scripts | ✅ DONE — `scripts/run_full_demo.sh` (primary) + `run_full_demo.py` (in-process) |

All three datasets share **identical schemas**: 6-DoF state + 6-DoF action, two cameras (overhead + wrist) at 640×480 av1 30 fps. This is the precondition that lets the sequencer load all three policies onto the same robot+camera setup.

### 11.2 What's NOT done — the remaining work to autonomy

**COMPRESSED 8-HOUR TRAINING BUDGET (set up May 2, 2026):**

| Phase | Steps | Wall-clock | Expected first-eval success |
|---|---|---|---|
| Train Task 1 (pick) | 15,000 | ~2.3 h | 50-65% grasp |
| Train Task 2 (plug) | 20,000 | ~3.3 h | 25-40% insertion |
| Train Task 3 (pour) | 12,000 | ~2.0 h | 50-60% pour |
| **Total** | **47,000** | **~7.6 h** | |
| Eval each task in isolation | — | ~10 min each | |
| Run full autonomous sequence | — | ~2 min | |

**One-shot launcher** chains all three trainings unattended in a single command — see §12.1.

**Trade-off:** these step counts are ~70% lower than the "full quality" recipe (50k/60k/50k = 160k steps, ~28h) which is what gives ~70-80% per-task success. The compressed run is "minimum viable for a demo". If first-eval results disappoint on any task, lerobot supports `--resume`, so you can add 10-15k more steps to that single task overnight as a separate session and keep iterating.

### 11.3 Core objective — autonomous in-sequence execution

After all three policies are trained and individually verified, **`./scripts/run_full_demo.sh`** runs the full Robothon demonstration with **zero human intervention during the run**:

```
[operator presses ENTER once]
   │
   ▼
go_home pick    →   pick policy 25s   →   cube placed in DROP_ZONE
   │
   ▼
go_home plug    →   plug policy 30s   →   connector seated in socket
   │
   ▼
go_home pour    →   pour policy 30s   →   liquid dispensed into cup
   │
   ▼
go_home (final reset)
```

Initial state required (set up before pressing ENTER):
- Cube in `PICK_ZONE`
- Connector resting in `CONNECTOR_ZONE`
- Bottle (filled) in `BOTTLE_ZONE`
- Empty cup in `CUP_ZONE`
- Robot powered, leader idle, all cameras locked in their original positions

Total wall-clock for the autonomous run: **~2 minutes** (3 phases × ~30s + 4 × 3s HOME transitions).

---

## 12. The Path To Autonomy — exact ordered commands

### 12.1 ONE-SHOT TRAINING (recommended) — `./scripts/train_all.sh`

The compressed 8-hour budget is delivered as a single unattended launcher.
Open the lid, plug in the charger, quit Cursor/Chrome/Slack, then:

```bash
cd /Users/udbhavkulkarni/Desktop/FInal_robothon

# Recommended — runs in foreground, keep the terminal open:
./scripts/train_all.sh

# OR fully detached overnight (closes when you log out):
nohup ./scripts/train_all.sh > train_all.log 2>&1 &
disown
tail -f train_all.log
```

Either way, the script:
1. Verifies all three datasets exist
2. Trains pick → plug → pour sequentially with `--yes` (no prompts)
3. Logs each phase to `outputs/training_logs/<phase>.log`
4. Survives a single-phase failure (other phases still run)
5. Prints a per-phase elapsed-time summary at the end

While it runs, you can monitor any phase live in another terminal:
```bash
tail -f outputs/training_logs/pick.log    # or plug.log / pour.log
```

If a checkpoint is interrupted (you closed the lid by accident, the laptop crashed, etc.) re-run with `--resume` to pick up from the last saved checkpoint of every partially-completed phase:

```bash
./scripts/train_all.sh --resume
```

### 12.2 Pre-flight checklist (do this BEFORE launching)

| Check | Why it matters |
|---|---|
| Charger plugged in | M4 Air at full TDP only with charger; on battery it throttles ~50% |
| Lid open | Closing the lid sleeps the system mid-training |
| Hard surface (desk, table) | M4 Air is fan-less — soft surfaces double the thermal throttling |
| Quit heavy apps (Cursor, Chrome, Slack, Docker) | Each free CPU core shaves ~5-10% off training time |
| Disable Time Machine for the night | Backup IO competes with dataset reads |
| Disable system updates / auto-restart | An unannounced restart will kill the run |
| `caffeinate -dis` in another terminal (optional but recommended) | Prevents idle sleep, display sleep, and disk sleep |

```bash
# Recommended: keep the laptop awake the whole night with one command
caffeinate -dis &
```

### 12.3 Morning after — verify each task in isolation

```bash
./scripts/task1_eval.sh   # 10 autonomous pick episodes
./scripts/task2_eval.sh   # 10 autonomous plug attempts
./scripts/task3_eval.sh   # 10 autonomous pour attempts
```

Score each one. Use these targets:

| Task | Acceptable | Topup needed if below |
|---|---|---|
| Pick & Place | ≥50% grasp + place | <40% grasp |
| Charger Plug | ≥25% insertion | <20% — usually means re-aim the wrist cam |
| Liquid Pour | ≥50% liquid in cup | <40% pour |

If a task underperforms, top it up overnight (each --resume adds another `TASKn_STEPS` worth of training):

```bash
./scripts/task1_train.sh --resume --yes   # adds 15k more steps in ~2.3h
./scripts/task2_train.sh --resume --yes   # adds 20k more steps in ~3.3h
./scripts/task3_train.sh --resume --yes   # adds 12k more steps in ~2h
```

### 12.4 Full autonomous sequence

Once each task is acceptable in isolation:

```bash
./scripts/run_full_demo.sh
```

This:
1. Verifies all 3 policy directories exist + `home_pose.json` is present
2. Drives the follower to `pick` start pose (3s), then runs pick policy (25s)
3. Drives to `plug` start pose, runs plug policy (30s)
4. Drives to `pour` start pose, runs pour policy (30s)
5. Final return to canonical HOME
6. Saves a 1-episode eval recording for each phase so you can replay/review

Total wall-clock: **~2 minutes**. Zero human intervention from the prompt onward.

### 12.5 In-process sequencer (optional polish)

For tighter phase transitions (no camera open/close churn between phases), use the in-process Python version:

```bash
.conda/bin/python scripts/run_full_demo.py
```

Both versions take the same recorded HOME poses and use the same trained policies. The bash version is more robust (uses lerobot-record's battle-tested inference path); the Python version is faster between phases.

---

## 13. The Helper Scripts (already created)

| Script | What it does | When to use |
|---|---|---|
| `scripts/capture_home.py` | Reads frame 0 of each dataset's first 5 episodes and writes per-task starting poses to `scripts/home_pose.json` | Once after recording, or after re-recording any task. Already done — file exists. |
| `scripts/go_home.py` | Smoothly drives the follower to a chosen pose (`--task pick/plug/pour` for per-task starts, no `--task` for canonical HOME) | Standalone testing or as a building block for the sequencer |
| `scripts/run_full_demo.sh` | Bash sequencer: chains 3 `lerobot-record --policy.path` calls with HOME drives between them | **PRIMARY autonomous-demo entry point.** Use this. |
| `scripts/run_full_demo.py` | In-process Python sequencer: opens robot+cameras once, loads all 3 policies, uses `lerobot.utils.control_utils.predict_action` with proper preprocessor/postprocessor pipelines | Optional polish for tighter phase transitions |

---

## 14. Failure-Recovery Playbook

If a phase fails during the autonomous run:

| Symptom | Likely cause | Fix |
|---|---|---|
| Robot freezes at start of phase | `home_pose.json` missing or wrong indices | Re-run `scripts/capture_home.py`, verify `OVERHEAD_INDEX=0, WRIST_INDEX=1` in `task*_env.sh` |
| Phase 1 misses the cube | Cube outside the demo distribution; lighting changed; camera moved | Add 10 targeted demos covering the failure pose, retrain with `--steps=70000` |
| Phase 2 misses the socket by >1 mm | Wrist cam can't see the connector tip; connector position changed | Re-aim wrist cam, verify in rerun, possibly add mechanical compliance to gripper tip |
| Phase 3 spills | Tilt was too fast or too far; bottle CG too high in grip | Add demos with slower tilt; ensure consistent grip height across demos |
| Robot jerks to wrong pose between phases | Per-task start pose drift; cable load changed | Re-run `capture_home.py` to refresh poses |
| `lerobot-record` fails to load policy | Checkpoint path wrong or stats mismatched | Verify `outputs/act_*_v1/checkpoints/last/pretrained_model` exists and contains `config.json`, `model.safetensors`, processor files |

---

## 12. Things to NOT Do (failure modes I'm pre-empting)

- **Don't** retrain three policies into one giant model. Keep them separate; debugging one bad policy is far easier.
- **Don't** add `--policy.type=diffusion` on M4 Air. It works, but it's 2–3× slower per step **and** ~2× slower at inference, making real-time control marginal at 30 Hz.
- **Don't** skip the fixture (§2.2). Every Mac-trained ACT failure I've seen on SO‑101 traces back to a moved camera or shifting daylight.
- **Don't** record 200 demos before training once. Train at 30 episodes first, watch one eval episode, learn what's missing, then collect 20 more targeted demos.
- **Don't** install ROS 2 / Docker / Isaac Lab on macOS at this stage. None of it will help you finish the hackathon.
- **Don't** run `lerobot-record` and the YOLO gate from the *same* camera index simultaneously — only one process can hold a UVC device on macOS at a time. The sequencer handles this by reading frames itself and not running `lerobot-record`.

---

*Plan v2 — May 1, 2026 — tuned for MacBook Air M4 (24 GB), `lerobot 0.5.1`, `ultralytics 8.4.45`. Replaces the ROS 2 / MoveIt 2 architecture document for execution purposes.*
