# SO-101 Complete Setup and Three-Task Runbook

**Last checked:** 2026-05-01

**Primary upstream reference:** https://huggingface.co/docs/lerobot/so101

**Robot naming used in this repo:**
- Competition / software name: `LeRobot SO101`
- Physical kit name: `WOWROBO SO-ARM101 Dual Arm Desktop Robot`
- Control roles: `leader` or `teleop` arm is moved by hand; `follower` or `robot` arm performs the task.

This runbook consolidates:
- `robot-spec.md`
- `SO101_Task1_PickPlace_Refined_Architecture.md`
- `so101_official_setup_vs_plan.html`
- `so101_pickplace_setup_guide.html`
- Current Hugging Face LeRobot SO-101 and imitation-learning docs.

## 0. What You Are Building

You have two SO-101 arms:

1. **Leader arm**
   - You move this arm manually during teleoperation.
   - LeRobot reads its joint positions as demonstrations.
   - It uses lighter gear ratios so it can be moved by hand.
   - WOWROBO quickstart power: **5V / 6A**.

2. **Follower arm**
   - This is the powered robot arm that mirrors the leader or runs a learned policy.
   - It performs pick-place, charger plugging, and liquid pouring.
   - It uses high-torque gearing for holding and manipulation.
   - WOWROBO quickstart power: **12V / 8A**.

3. **Camera**
   - Connects by USB.
   - Used for object/connector/bottle/cup detection, pose estimation, and final verification.
   - Start with one fixed overhead or 45-degree front camera. Add a wrist camera later only after the base pipeline works.

## 1. Hard Safety Rules

Follow these before any software command that moves the follower.

- Use the correct power supplies:
  - Leader: **5V / 6A**
  - Follower: **12V / 8A**
- Do not swap leader and follower motor sets.
- Do not exceed **400 g payload**.
- Keep your hand near the follower power switch during first motion tests.
- Run calibration before first teleoperation.
- If motion direction is abnormal, stop immediately and recalibrate.
- Be especially careful with follower **Servo #3 / elbow flex** during calibration; wrong direction can drive the arm into a mechanical limit.
- Do not manually change Feetech servo PID, deadband, torque, or protection parameters until the official bring-up works.
- First autonomous runs should use low speed, clear workspace, and a light test object under 200 g.

## 2. Official Software Baseline

The current Hugging Face LeRobot docs recommend:

- Python **3.12**
- LeRobot install with Feetech support
- Current CLI commands:
  - `lerobot-find-port`
  - `lerobot-setup-motors`
  - `lerobot-calibrate`
  - `lerobot-teleoperate`
  - `lerobot-record`
  - `lerobot-train`

Avoid older commands from stale guides such as:

```powershell
python lerobot/scripts/control_robot.py ...
python -m lerobot.scripts.configure_motor ...
```

Those appear in older local guide text and should be replaced by the current `lerobot-*` CLI flow.

## 3. Recommended Repo-Local Install on Windows

From `C:\Users\Govin\Desktop\robo`:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip setuptools wheel
pip install "lerobot[feetech]"
```

Optional but useful for dataset upload/training:

```powershell
pip install huggingface_hub wandb
```

Optional but useful for local perception experiments:

```powershell
pip install ultralytics opencv-python open3d scipy numpy
```

For video handling, install FFmpeg system-wide if it is not already available:

```powershell
winget install --id Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements
```

After installation, verify:

```powershell
lerobot-find-port --help
lerobot-setup-motors --help
lerobot-calibrate --help
lerobot-teleoperate --help
lerobot-record --help
lerobot-train --help
```

## 3A. Installed Repo-Local Environment on This Mac

This workspace now has a local Conda environment at:

```bash
/Users/udbhavkulkarni/Desktop/FInal_robothon/.conda
```

Activate it from this repository:

```bash
conda activate /Users/udbhavkulkarni/Desktop/FInal_robothon/.conda
```

Installed and verified packages:

```text
Python 3.12.13
LeRobot 0.5.1
PyTorch 2.10.0
torchvision 0.25.0
Feetech Servo SDK 1.0.0
OpenCV 4.13.0.92
Ultralytics 8.4.45
Open3D 0.19.0
MuJoCo 3.8.0
huggingface_hub 1.13.0
wandb 0.24.2
rerun-sdk 0.26.2
pyserial 3.5
FFmpeg 8.0.1
```

The same environment can be recreated from `environment.yml`:

```bash
conda env create -p ./.conda -f environment.yml
```

Available LeRobot commands in this environment include:

```text
lerobot-find-port
lerobot-setup-motors
lerobot-calibrate
lerobot-teleoperate
lerobot-find-cameras
lerobot-record
lerobot-replay
lerobot-train
lerobot-eval
```

## 4. Physical Connection Order

Do this slowly the first time.

1. Put both arms on a stable table.
2. Keep the follower workspace clear.
3. Connect leader controller board to PC by USB.
4. Connect leader power: **5V / 6A**.
5. Connect follower controller board to PC by USB.
6. Connect follower power: **12V / 8A**.
7. Connect camera by USB.
8. Label the USB cables:
   - `LEADER`
   - `FOLLOWER`
   - `CAMERA`
9. If using a Waveshare controller board, confirm jumpers are on channel `B` / USB as required by the Hugging Face troubleshooting note.

## 5. Find Ports

Run:

```powershell
lerobot-find-port
```

The script asks you to disconnect one MotorBus while it is running. Use that prompt to identify which serial port belongs to which arm.

On Windows, ports usually look like:

```text
COM3
COM4
```

Write them here:

```text
LEADER_PORT   = COM__
FOLLOWER_PORT = COM__
CAMERA_INDEX  = 0 or 1
```

Use the same physical USB ports when possible. COM numbers can change after replugging.

## 6. Motor ID and Baudrate Setup

This writes motor IDs and baudrate to EEPROM. Do this once per arm unless motors are replaced.

Critical rule: **only one motor connected to the controller board at a time** while assigning IDs. Do not daisy-chain until the script finishes.

Follower:

```powershell
lerobot-setup-motors `
  --robot.type=so101_follower `
  --robot.port=COM_FOLLOWER
```

Leader:

```powershell
lerobot-setup-motors `
  --teleop.type=so101_leader `
  --teleop.port=COM_LEADER
```

The official script prompts in reverse physical order:

1. `gripper` -> ID 6
2. `wrist_roll` -> ID 5
3. `wrist_flex` -> ID 4
4. `elbow_flex` -> ID 3
5. `shoulder_lift` -> ID 2
6. `shoulder_pan` -> ID 1

After all IDs are set, daisy-chain:

```text
controller board -> shoulder_pan -> shoulder_lift -> elbow_flex -> wrist_flex -> wrist_roll -> gripper
```

## 7. Motor Gear Ratio Considerations

The follower uses high-torque gearing across its motors. The leader uses mixed ratios so it is easier to move by hand.

Leader motor ratios from the official SO-101 docs:

| Axis | Joint | Leader gear ratio |
|---|---:|---:|
| Base / shoulder pan | 1 | 1 / 191 |
| Shoulder lift | 2 | 1 / 345 |
| Elbow flex | 3 | 1 / 191 |
| Wrist flex | 4 | 1 / 147 |
| Wrist roll | 5 | 1 / 147 |
| Gripper | 6 | 1 / 147 |

The LeRobot command handles this when you use the correct type:

```text
--teleop.type=so101_leader
--robot.type=so101_follower
```

Do not treat both arms as identical in configuration.

## 8. Calibrate Both Arms

Use stable IDs. The same `--robot.id` and `--teleop.id` must be reused for teleoperation, recording, and evaluation because LeRobot stores calibration by ID.

Recommended IDs:

```text
robot.id  = so101_follower_main
teleop.id = so101_leader_main
```

Follower calibration:

```powershell
lerobot-calibrate `
  --robot.type=so101_follower `
  --robot.port=COM_FOLLOWER `
  --robot.id=so101_follower_main
```

Leader calibration:

```powershell
lerobot-calibrate `
  --teleop.type=so101_leader `
  --teleop.port=COM_LEADER `
  --teleop.id=so101_leader_main
```

Calibration process:

1. Put the arm in the middle/rest pose when prompted.
2. Press Enter.
3. Move each joint through its full safe range.
4. Do not force joints into hard stops.
5. Be extra careful with follower elbow / Servo #3 direction.
6. Save and reuse the generated calibration.

If the follower moves the wrong way during teleoperation, stop and rerun calibration.

## 9. First Teleoperation Test

Run only after both arms are calibrated.

```powershell
lerobot-teleoperate `
  --robot.type=so101_follower `
  --robot.port=COM_FOLLOWER `
  --robot.id=so101_follower_main `
  --teleop.type=so101_leader `
  --teleop.port=COM_LEADER `
  --teleop.id=so101_leader_main
```

Expected behavior:

- Moving the leader makes the follower mirror it.
- Motion is smooth and directionally correct.
- No joint drives into a hard stop.
- Gripper open/close direction is correct.

Stop conditions:

- Wrong direction on any joint
- Sudden jump
- Grinding or binding
- Follower elbow moving toward mechanical limit
- Servo overheats or overloads

## 10. Camera Bring-Up

Start simple with OpenCV camera capture through LeRobot.

Find camera index:

```bash
lerobot-find-cameras opencv
```

If needed, cross-check with raw OpenCV:

```powershell
python - <<'PY'
import cv2
for i in range(6):
    cap = cv2.VideoCapture(i)
    ok, _ = cap.read()
    print(i, ok)
    cap.release()
PY
```

Use the camera in teleoperation/recording:

```powershell
lerobot-teleoperate `
  --robot.type=so101_follower `
  --robot.port=COM_FOLLOWER `
  --robot.id=so101_follower_main `
  --robot.cameras="{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}}" `
  --teleop.type=so101_leader `
  --teleop.port=COM_LEADER `
  --teleop.id=so101_leader_main `
  --display_data=true
```

Camera placement:

- Fixed mount, no wobble.
- Full view of pick zone and place zone.
- No cable path through follower workspace.
- Consistent lighting.
- For charger plugging and pouring, add close-up view or wrist camera later.

## 11. Record Demonstrations

Log in to Hugging Face if you want to upload datasets:

```powershell
hf auth login --token YOUR_HF_TOKEN --add-to-git-credential
hf auth whoami
```

Record a small smoke-test dataset first:

```powershell
lerobot-record `
  --robot.type=so101_follower `
  --robot.port=COM_FOLLOWER `
  --robot.id=so101_follower_main `
  --robot.cameras="{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}}" `
  --teleop.type=so101_leader `
  --teleop.port=COM_LEADER `
  --teleop.id=so101_leader_main `
  --display_data=true `
  --dataset.repo_id=YOUR_HF_USER/so101_smoke_pickplace `
  --dataset.num_episodes=5 `
  --dataset.single_task="Pick up the light cube and place it in the marked target zone" `
  --dataset.streaming_encoding=true `
  --dataset.encoder_threads=2
```

For actual task training:

- Start with 30 to 50 good episodes.
- Prefer smooth, successful demonstrations.
- Delete bad episodes or keep them only if you intentionally train recovery behavior.
- Reset the object, connector, bottle, and cup consistently.
- Use identical `robot.id`, `teleop.id`, camera names, and resolution across all recordings.

## 12. Train ACT Policy

Official LeRobot example:

```powershell
lerobot-train `
  --dataset.repo_id=YOUR_HF_USER/so101_pickplace `
  --policy.type=act `
  --output_dir=outputs/train/act_so101_pickplace `
  --job_name=act_so101_pickplace `
  --policy.device=cuda `
  --wandb.enable=true `
  --policy.repo_id=YOUR_HF_USER/act_so101_pickplace
```

CPU-only fallback:

```powershell
lerobot-train `
  --dataset.repo_id=YOUR_HF_USER/so101_pickplace `
  --policy.type=act `
  --output_dir=outputs/train/act_so101_pickplace_cpu `
  --job_name=act_so101_pickplace_cpu `
  --policy.device=cpu `
  --wandb.enable=false `
  --policy.push_to_hub=false
```

Notes:

- GPU training is strongly preferred.
- CPU training can take many hours.
- Google Colab is reasonable if local GPU is unavailable.

## 13. Evaluate Policy on the Follower

Use `lerobot-record` with a policy path to evaluate and save videos/results.

```powershell
lerobot-record `
  --robot.type=so101_follower `
  --robot.port=COM_FOLLOWER `
  --robot.id=so101_follower_main `
  --robot.cameras="{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}}" `
  --display_data=true `
  --dataset.repo_id=YOUR_HF_USER/eval_so101_pickplace `
  --dataset.single_task="Pick up the light cube and place it in the marked target zone" `
  --dataset.num_episodes=10 `
  --dataset.streaming_encoding=true `
  --dataset.encoder_threads=2 `
  --policy.path=outputs/train/act_so101_pickplace/checkpoints/last/pretrained_model
```

For first evaluations:

- Use a very light object.
- Keep speed conservative.
- Do not include fragile objects.
- Be ready to cut follower power.

## 14. Three Competition Tasks

Your final-round requirement is sequential autonomous execution:

```text
Task 1: Object pick and place
Task 2: Charger plugging
Task 3: Liquid pouring
```

The strategic architecture from `SO101_Task1_PickPlace_Refined_Architecture.md` is sound:

```text
Perception -> Grasp/Contact Plan -> Motion Plan -> ACT/Policy refinement -> Low-level servo execution -> Verification
```

Use classical structure for safety and repeatability. Use learning for the uncertain final centimeters.

### Task 1: Object Pick and Place

Minimum setup:

- Light object under 200 g for early runs.
- Marked pick zone.
- Marked target/place zone.
- Fixed camera sees both.

Flow:

1. Detect object.
2. Estimate 3D pose from camera and depth or calibrated 2D workspace.
3. Move follower to pre-grasp pose.
4. Approach slowly.
5. Close gripper.
6. Verify grasp with gripper load and visual check.
7. Lift.
8. Move to pre-place pose.
9. Descend.
10. Open gripper.
11. Retreat.
12. Verify object lies inside target tolerance.

Important considerations:

- Use top-down grasps first.
- Keep the table as a collision plane.
- Add retry: if grasp verification fails, open gripper, retreat, redetect, retry.
- Keep demonstrations consistent before adding variation.

### Task 2: Charger Plugging

This is harder than pick-place because insertion needs alignment and contact control.

Recommended staged plan:

1. Start with a rigid dummy connector before a flexible cable.
2. Fix the socket position during early experiments.
3. Use a bright visual marker near the connector and socket.
4. Teleoperate 50+ successful insertions.
5. Train/evaluate only after scripted alignment is reliable.

Flow:

1. Detect connector.
2. Grasp connector body, not the flexible cable.
3. Detect socket pose.
4. Move to pre-insertion pose 2 to 4 cm in front of socket.
5. Align connector axis with socket axis.
6. Insert slowly along socket axis.
7. Monitor follower joint load/current for contact spikes.
8. Stop at full insertion depth.
9. Verify connector remains secure, visually or by gentle retreat/pull test.

Important considerations:

- Cable flexibility causes pose drift; keep cable slack controlled.
- Use funnel or chamfered fixture in early development.
- Use low insertion speed.
- Avoid high force; SO-101 has no true force/torque sensor.
- Treat insertion as "visual alignment + compliant push", not simple replay.

### Task 3: Liquid Pouring

This is harder than pick-place because it needs grip stability and controlled wrist rotation.

Recommended staged plan:

1. Practice with an empty bottle.
2. Then use dry beads or rice.
3. Then use small water volume.
4. Use a wide receiving cup before narrowing the target.

Flow:

1. Detect bottle and cup.
2. Grasp bottle near center of mass.
3. Verify grip with load and visual stability.
4. Move bottle above cup.
5. Tilt wrist gradually.
6. Hold pour angle for timed interval or until target weight/vision threshold.
7. Return bottle upright.
8. Place bottle down or move to safe home pose.
9. Verify no spill and target volume.

Important considerations:

- Keep bottle plus liquid under 400 g.
- Fill bottle only partially for early runs.
- Grasp around a non-slip section.
- Add a tray under the cup.
- Use slow wrist rotation, not sudden tilt.
- For accurate volume, add a cheap kitchen scale under the cup if rules allow.

## 15. Final Sequential Autonomy Plan

Once each task works alone, connect them with a top-level state machine:

```text
HOME
  -> PICK_PLACE
  -> VERIFY_PICK_PLACE
  -> CHARGER_PLUG
  -> VERIFY_CHARGER
  -> POUR
  -> VERIFY_POUR
  -> HOME
```

Transition rules:

- Each task starts from a known safe pose.
- Each task ends in a known safe pose.
- Each task has visual verification.
- A failed verification triggers one retry.
- Two failures trigger safe stop.

Common safe pose:

- Follower above table.
- Gripper open.
- Wrist upright.
- No object held unless the next task explicitly expects it.

## 16. Architecture Corrections to Keep

From the comparison guide, keep these corrections as non-negotiable:

- Use current `lerobot-*` CLI commands.
- Use leader 5V / 6A and follower 12V / 8A.
- Account for leader mixed gear ratios.
- Assign motor IDs one at a time before daisy-chaining.
- Calibrate both arms and preserve IDs.
- Add Servo #3 calibration warning.
- Enforce 400 g payload limit.
- Treat MoveIt2 + BehaviorTree as an extension on top of official LeRobot, not a replacement for official bring-up.

## 17. Practical Milestones

Do not skip ahead. Each milestone should work before moving to the next.

1. LeRobot CLI installed.
2. `lerobot-find-port` sees both arms.
3. `lerobot-setup-motors` completed for follower.
4. `lerobot-setup-motors` completed for leader.
5. `lerobot-calibrate` completed for follower.
6. `lerobot-calibrate` completed for leader.
7. Teleoperation works with no camera.
8. Teleoperation works with camera display.
9. Five-episode smoke dataset records successfully.
10. Pick-place policy/evaluation works slowly on one light object.
11. Pick-place robust over small pose variation.
12. Charger plugging works with rigid dummy connector.
13. Charger plugging works with actual cable.
14. Pouring works with empty bottle.
15. Pouring works with safe liquid volume.
16. Full three-task sequence works with one retry and safe stop.

## 18. References

- Hugging Face SO-101 setup: https://huggingface.co/docs/lerobot/so101
- Hugging Face LeRobot installation: https://huggingface.co/docs/lerobot/installation
- Hugging Face real-robot imitation learning: https://huggingface.co/docs/lerobot/il_robots
- Official/community support link from docs: https://discord.com
- User-provided setup video: https://www.youtube.com/watch?v=70GuJf2jbYk
- User-provided Discord invite: https://discord.gg/dhTGTVJQC4
