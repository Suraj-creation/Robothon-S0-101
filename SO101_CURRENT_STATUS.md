# SO-101 Current Bring-Up Status

Last checked: 2026-05-01

## Software Status

The repo-local Conda environment is active and usable:

```bash
conda activate /Users/udbhavkulkarni/Desktop/FInal_robothon/.conda
```

Fixed:

- `rerun-sdk==0.26.2` is installed.
- `import rerun as rr` works.
- `lerobot_teleoperate` imports successfully.
- A Conda-specific `rerun` module path issue was fixed by linking:

```text
.conda/lib/python3.12/site-packages/rerun -> rerun_sdk/rerun
```

Current warning:

- macOS prints a duplicate `libavdevice` warning from `cv2` and `av`.
- This is not blocking teleoperation startup.
- Do not uninstall `av` yet because LeRobot requires it for video/dataset paths.

## Hardware Bus Status

Diagnostic command:

```bash
.conda/bin/python scripts/so101_diagnose.py \
  --leader-port /dev/tty.usbmodem5B140318771 \
  --follower-port /dev/tty.usbmodem5B141124491 \
  --scan-all
```

Leader result:

```text
IDs 1,2,3,4,5,6 detected
```

Follower result:

```text
IDs 1,2,3,4 detected
IDs 5,6 missing
```

One follower motor was previously detected as ID `0`; it was corrected to ID `4`.

## Why Teleoperation Still Stops

`lerobot-teleoperate` now passes the software import stage and connects to the leader. It stops during follower handshake because LeRobot requires all six follower motors:

```text
Missing motor IDs:
  - 5 wrist_roll
  - 6 gripper
```

## Next Physical Fix

On the follower arm, inspect the daisy-chain after `wrist_flex` / ID 4:

```text
controller -> shoulder_pan(1) -> shoulder_lift(2) -> elbow_flex(3) -> wrist_flex(4) -> wrist_roll(5) -> gripper(6)
```

Most likely causes:

- 3-pin cable from wrist_flex to wrist_roll is loose, reversed, damaged, or in the wrong socket.
- 3-pin cable from wrist_roll to gripper is loose or damaged.
- Wrist_roll and gripper were never ID-configured.
- Wrist_roll or gripper is not powered through the bus chain.

After reseating cables, rerun the diagnostic command above. The follower must show:

```text
ALL_IDS=[(1, 777), (2, 777), (3, 777), (4, 777), (5, 777), (6, 777)]
```

Then run teleoperation:

```bash
lerobot-teleoperate \
  --teleop.type=so101_leader \
  --teleop.port=/dev/tty.usbmodem5B140318771 \
  --robot.type=so101_follower \
  --robot.port=/dev/tty.usbmodem5B141124491
```

## If the Visible IDs Keep Changing

If repeated diagnostics show different follower IDs on different runs, or errors like:

```text
[TxRxResult] Incorrect status packet!
```

then the bus is unstable or multiple motors may be replying with colliding IDs. Do not run teleoperation and do not rewrite IDs while the full daisy-chain is connected.

Use the one-motor helper instead. Connect exactly one follower motor to the controller board, then detect it:

```bash
python scripts/so101_single_motor.py \
  --port /dev/tty.usbmodem5B141124491
```

If exactly one motor is detected, assign the correct target:

```bash
python scripts/so101_single_motor.py \
  --port /dev/tty.usbmodem5B141124491 \
  --target wrist_roll \
  --set \
  --yes-one-motor-only
```

Valid target names:

```text
shoulder_pan  -> ID 1
shoulder_lift -> ID 2
elbow_flex    -> ID 3
wrist_flex    -> ID 4
wrist_roll    -> ID 5
gripper       -> ID 6
```

Official setup order is reverse physical order:

```text
gripper -> wrist_roll -> wrist_flex -> elbow_flex -> shoulder_lift -> shoulder_pan
```
