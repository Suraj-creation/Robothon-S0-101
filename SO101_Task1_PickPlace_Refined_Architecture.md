# SO-101 Task 1: Object Pick and Place — Refined Industry-Grade Architecture

**Date:** April 24, 2026
**Robot Platform:** LeRobot SO-101 (Standard Open Arm 101)
**Framework:** LeRobot + ROS 2 Jazzy + MuJoCo/Isaac Lab
**Task:** Reliable object pick and place with precision and stability

---

## Executive Summary

This document refines the pick-and-place pipeline for the SO-101 robotic arm into an industry-grade, robust architecture. The design follows the principle that **reliable manipulation is 70% perception and classical planning, 20% low-level control, and 10% learning-based refinement**.

The SO-101 is a 6-DOF (Degrees of Freedom) serial manipulator with a parallel-jaw gripper, driven by Feetech STS3215 serial bus servos. It provides full Cartesian workspace coverage (position + orientation), making it capable of general pick-and-place tasks when coupled with proper perception and planning [web:71][web:31].

---

## 1. Hardware Platform Profile: SO-101

### 1.1 Kinematics & Workspace
| Parameter | Specification |
|-----------|---------------|
| Degrees of Freedom | 6-DOF (J1–J6) + 1-DOF gripper |
| Joint Range | Shoulder pan: ±110°, Shoulder lift: ±100°, Elbow flex: ±97°, Wrist flex: ±95°, Wrist roll: continuous, Wrist yaw: ±90° [web:70] |
| Workspace | Full 6-DOF Cartesian freedom (any position + orientation within reach) [web:71] |
| Gripper Type | Parallel-jaw, driven by single STS3215 servo |
| Max Clamping Width | ~80 mm [web:83] |

### 1.2 Actuator & Sensor Specifications
| Parameter | STS3215 Servo (Arm Joints) | STS3215 Servo (Gripper) |
|-----------|---------------------------|------------------------|
| Stall Torque | 30 kg·cm @ 12V (C018 variant) / 19.5 kg·cm @ 7.4V [web:60][web:66] | 30 kg·cm @ 12V |
| Encoder | 12-bit magnetic absolute encoder (4096 steps, 0.088° resolution) [web:80] | 12-bit magnetic encoder |
| Feedback | Position, Load, Voltage, Current, Speed, Temperature [web:82][web:85] | Position, Load |
| Gear Ratio | 1:345 (high torque) / 1:191 (speed) [web:59] | 1:345 |
| Control Interface | TTL serial bus (1 Mbps) | TTL serial bus |

### 1.3 Key Hardware Insights for Pipeline Design
- **Load feedback available**: The STS3215 servos report real-time load values, enabling basic force estimation without external force/torque sensors [web:82][web:85]. This is critical for detecting grasp success and contact during placement.
- **Position resolution**: 0.088° per step provides adequate repeatability for pick-and-place, though backlash in the 1:345 gear train introduces ~1–2° mechanical hysteresis [web:80][web:81].
- **Current sensing**: Stall current is 2.7A; overload protection triggers at 80% stall torque for >2s. This can be used as a safety cutoff during grasping [web:82].
- **No external F/T sensor**: Gripper force must be inferred from servo load/current feedback, not direct measurement.

---

## 2. Refined System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    PERCEPTION STACK                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   RGB-D      │  │  Detection & │  │   6D Pose Estimation   │  │
│  │   Camera     │→ │ Segmentation │→ │  + Temporal Filtering │  │
│  │  (RealSense) │  │ (YOLO/SAM2)  │  │  (EKF/One-Euro Filter)│  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└────────────────────────┬────────────────────────────────────────┘
                         │ Filtered Object Pose (position + orientation)
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│                 GRASP GENERATION MODULE                          │
│  ┌──────────────────┐      ┌─────────────────────────────────┐   │
│  │ Candidate Gen    │      │   Scoring & Selection           │   │
│  │ - Top-down       │  →   │   - Antipodal metric            │   │
│  │ - Side grasps    │      │   - Force closure check         │   │
│  │ - Multi-angle    │      │   - Gripper width compatibility │   │
│  └──────────────────┘      └─────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────────┘
                         │ Best Grasp Pose (6-DOF)
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│            TASK & MOTION PLANNING LAYER                          │
│  ┌──────────────────────┐      ┌──────────────────────────┐     │
│  │   Task Planner       │      │   Motion Planner         │     │
│  │   (Behavior Tree)    │      │   (MoveIt 2)             │     │
│  │   - FSM for pick/place│     │   - IK solver            │     │
│  │   - Error handling   │      │   - Collision avoidance  │     │
│  │   - Retry logic      │      │   - Trajectory smoothing │     │
│  └──────────────────────┘      └──────────────────────────┘     │
└────────────────────────┬────────────────────────────────────────┘
                         │ Joint Trajectory + Gripper Command
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│            POLICY LAYER (Refinement Only)                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  ACT / Diffusion Policy (LeRobot)                         │   │
│  │  - Input: Image + Joint States                             │   │
│  │  - Output: Δ correction to planned trajectory             │   │
│  │  - Used for: fine approach, contact handling, recovery    │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────────┘
                         │ Refined Joint Targets
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│              LOW-LEVEL CONTROL                                     │
│  ┌────────────────────┐      ┌──────────────────────────────┐   │
│  │ Trajectory Tracking│      │      Gripper Control         │   │
│  │ - PID per joint    │      │ - Position control (open/close)│  │
│  │ - Velocity limits  │      │ - Load-based force estimation  │  │
│  │ - Acceleration ramps│     │ - Slip detection (position   │  │
│  └────────────────────┘      │    deviation under load)       │  │
│                              └──────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────────┘
                         │ Servo Commands (TTL Serial)
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│                    ROBOT EXECUTION                                 │
│                   (SO-101 Follower Arm)                            │
└─────────────────────────────────────────────────────────────────┘
                         │
                         ↓ Visual + Proprioceptive Feedback
┌─────────────────────────────────────────────────────────────────┐
│                 FEEDBACK LOOP (Closed-Loop)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  Re-detect   │  │  Grasp Verify │  │  Placement Verify    │  │
│  │  Object      │  │  (Load check) │  │  (Vision + Depth)    │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Perception Stack (Critical Upgrade)

### 3.1 Sensor Setup
| Sensor | Role | Specification | Mounting |
|--------|------|---------------|----------|
| Intel RealSense D405/D435i | RGB-D | 640×480 @ 30fps, depth FoV ~55°×42° | Static overhead or 45° front-facing |
| Optional: Wrist Camera | Close-up RGB | Webcam / RealSense D405 | Fixed to forearm near gripper |

> **Recommendation**: Use a **static overhead camera** for detection and a **wrist camera** for fine alignment. The overhead camera provides a stable global reference frame; the wrist camera provides local detail for grasp refinement [web:57][web:19].

### 3.2 Detection & Segmentation Layer

**Open-Source Models:**

| Model | Purpose | Speed | Accuracy | Repository |
|-------|---------|-------|----------|------------|
| **YOLOv8/v11** | Object detection + classification | ~30ms/frame | Good | `ultralytics/ultralytics` |
| **SAM 2** | Instance segmentation | ~50ms/frame | Excellent | `facebookresearch/segment-anything` |
| **OWL-ViT** | Open-vocabulary detection | ~100ms/frame | Good | `google-research/scenic` |

**Recommended Pipeline for Known Objects:**
1. **YOLOv8** for fast bounding box detection (trained on your object classes).
2. **SAM 2** to refine bounding box into precise object mask.
3. **Depth projection** to convert mask pixels into 3D point cloud segment.

**For Novel Objects (Zero-Shot):**
- Use **OWL-ViT** or **Grounding DINO** for text-prompted detection (e.g., "pick up the red cube"), then SAM 2 for segmentation [web:50].

### 3.3 6D Pose Estimation Layer

| Method | Input | Output | Use Case | Open-Source |
|--------|-------|--------|----------|-------------|
| **PnP + Depth** | Mask + point cloud | 6D pose | Known object geometry | OpenCV |
| **FoundationPose** | RGB-D + CAD/textured mesh | 6D pose + tracking | Novel objects, tracking | `NVlabs/FoundationPose` [web:36] |
| **FoundationPoseROS2** | ROS2 topic integration | PoseStamped | Real-time deployment | `ammar-n-abbas/FoundationPoseROS2` [web:51] |
| **BundleSDF** | RGB-D video | 6D pose + 3D reconstruction | Unknown objects | `NVlabs/BundleSDF` |

**Recommendation for SO-101:**
- Start with **PnP + centroid depth** for axis-symmetric objects (cubes, cylinders).
- Upgrade to **FoundationPoseROS2** for asymmetric objects requiring precise orientation alignment (e.g., placing a connector) [web:36][web:51].

### 3.4 State Estimation (Temporal Filtering)

Raw detections are noisy. Add filtering:

| Filter | State Dimension | Use Case | Library |
|--------|---------------|----------|---------|
| **One-Euro Filter** | 3D position | Smooth jitter in detection | Simple implementation |
| **Extended Kalman Filter (EKF)** | 6D pose + velocity | Full pose tracking with prediction | `robot_pose_ekf` (ROS2 port) [web:77] |
| **Kalman Filter (custom)** | 3D position + load | Grasp stability monitoring | Custom ROS2 node |

> **Critical**: Always add temporal smoothing. A single-frame detection failure should not crash the pipeline. The EKF predicts pose during occlusion and updates when detection resumes.

---

## 4. Grasp Generation Module (Hybrid Approach)

The SO-101 uses a **parallel-jaw gripper (1-DOF)**. This simplifies grasping but limits versatility.

### 4.1 Grasp Candidate Generation

| Strategy | Description | Applicability |
|----------|-------------|---------------|
| **Top-down grasp** | Approach vertically along world Z-axis | Flat objects on table (boxes, cylinders) |
| **Tilted grasp** | Approach at 15–30° angle | Objects with overhangs, rounded tops |
| **Side grasp** | Horizontal approach | Tall objects, objects near walls |
| **Antipodal sampling** | Sample grasp rays across object point cloud | General objects, requires point cloud |

**Algorithm: Antipodal Grasp Sampling for Parallel Jaw**
```
Input: Object point cloud P, gripper width W
For each point p in P:
    Compute surface normal n
    Cast ray along -n to find antipodal point p'
    If distance(p, p') < W:
        Compute grasp center = midpoint(p, p')
        Compute approach direction = n
        Add candidate G = (center, approach, width)
Score candidates by:
    - Force closure metric (antipodal distance)
    - Standoff distance from object surface
    - Clearance from neighboring objects
Return top-K candidates
```
[web:72]

### 4.2 Grasp Scoring & Selection

| Scoring Method | Type | Implementation | When to Use |
|----------------|------|----------------|-------------|
| **Force closure check** | Analytical | Ray-cast + surface normal alignment | Always (baseline) |
| **Grasp Quality CNN (GQ-CNN)** | Learned | Train on DexNet 2.0 data [web:37] | When analytic scoring insufficient |
| **GraspNet baseline** | Learned | `graspnet/graspnet-baseline` [web:38] | Complex object shapes, cluttered scenes |
| **Heuristic rules** | Rule-based | Top-down preference + width match | Simple objects, fast execution |

**Recommended Hybrid for SO-101:**
1. Generate candidates via **antipodal sampling** on segmented point cloud.
2. Filter by **heuristic rules**: prefer top-down, gripper width must match, no collision with table.
3. Rank remaining by **force closure metric**.
4. (Optional) Re-rank top-5 by a lightweight **GQ-CNN** if available.

### 4.3 Gripper Width & Force Considerations

| Object Property | Gripper Setting | Load Threshold |
|---------------|-----------------|----------------|
| Small, rigid object (cube, <100g) | Close to 50% max width | 20–30% stall load |
| Large, rigid object (box, <500g) | Match object width | 40–50% stall load |
| Fragile object | Close gently, monitor load | Stop at 10–15% stall load |
| Heavy object (near 500g limit) | Maximum width, close fully | 60–70% stall load |

> **Grasp Verification**: After closing, check if servo position remains stable under load. If the position drifts while load is high, the object is slipping.

---

## 5. Task & Motion Planning Layer

### 5.1 Task Planning: Behavior Trees (Industry Standard)

Use **BehaviorTree.CPP** with ROS2 integration for high-level task logic [web:64][web:68].

**Example Behavior Tree for Pick and Place:**
```xml
<Sequence name="PickAndPlace">
    <RetryUntilSuccessful num_attempts="3">
        <Sequence name="DetectAndGrasp">
            <DetectObject object_type="target" pose="{object_pose}"/>
            <ComputeGrasp object_pose="{object_pose}" grasp="{grasp_pose}"/>
            <MoveToPregrasp grasp="{grasp_pose}"/>
            <ExecuteGrasp grasp="{grasp_pose}"/>
            <VerifyGrasp/>
        </Sequence>
    </RetryUntilSuccessful>
    <RetryUntilSuccessful num_attempts="3">
        <Sequence name="TransportAndPlace">
            <MoveToPreplace place_pose="{place_pose}"/>
            <ExecutePlacement place_pose="{place_pose}"/>
            <VerifyPlacement/>
            <OpenGripper/>
            <Retreat/>
        </Sequence>
    </RetryUntilSuccessful>
</Sequence>
```

**Key ROS2 Packages:**
- `BehaviorTree.CPP`: Core behavior tree engine [web:64]
- `BehaviorTree.ROS2`: ROS2 action/service wrappers [web:64]
- Custom nodes: `DetectObject`, `ComputeGrasp`, `VerifyGrasp`, `VerifyPlacement`

### 5.2 Motion Planning: MoveIt 2

| Component | Tool | Purpose |
|-----------|------|---------|
| IK Solver | KDL / Trac-IK / LMA | Joint angles from Cartesian target [web:62] |
| Motion Planner | OMPL (RRTConnect, PRM) | Collision-free path [web:84] |
| Trajectory Generator | TOTG / Ruckig | Time-optimal, smooth trajectory |
| Collision Checker | FCL | Self-collision + environment collision |
| Planning Scene | MoveIt 2 | Dynamic updates from perception [web:41] |

**MoveIt Task Constructor (MTC) Pipeline for Pick and Place** [web:84][web:41]:
1. **Current State** → connect to pre-grasp pose
2. **Move Relative** (approach): linear approach along grasp Z-axis
3. **Generate Grasp Pose**: iterate grasp candidates
4. **Move To** (grasp): close gripper
5. **Move Relative** (lift): lift 10cm vertically
6. **Move To** (transport): navigate to pre-place
7. **Move Relative** (place approach): descend to place
8. **Move To** (release): open gripper
9. **Move Relative** (retreat): retract

> **Critical**: MoveIt 2 provides **collision-aware planning** and **kinematic constraints** (e.g., keep gripper horizontal during transport). This is essential for stability.

### 5.3 SO-101 MoveIt 2 Integration Status

| Resource | Status | Link |
|----------|--------|------|
| SO-100 ROS2 Package | Available (5-DOF, Gazebo, ROS2 Control) | `brukg/SO-100-arm` [web:62] |
| SO-101 ROS2 Package | Community WIP (Jazzy, Gazebo Harmonic, MoveIt2) | Reddit community [web:67] |
| MoveIt 2 Config | Basic configuration generated, integration pending | [web:62] |

**Recommendation**: Use the SO-100 ROS2 package as a base and extend to SO-101's 6th DOF. The URDF and joint limits are well-documented [web:70][web:62].

---

## 6. Policy Layer (Correctly Scoped)

### 6.1 Role of Learning in This Architecture

The policy layer is **optional and corrective**, not central. It handles:
- Fine end-effector adjustments near grasp/placement
- Recovery from small trajectory deviations
- Smoothing of human-demonstrated motions

### 6.2 Recommended Models

| Model | Framework | Input | Output | Best For | Open-Source |
|-------|-----------|-------|--------|----------|-------------|
| **ACT** | LeRobot | Image + joint states | Chunk of joint positions | Smooth motion, teleop mimicry | `lerobot` [web:45] |
| **Diffusion Policy** | LeRobot / diffusion-policy | Image + state | Action distribution | Multi-modal corrections | `diffusion-policy` [web:40] |
| **GR00T N1** | NVIDIA Isaac | Multimodal (VLA) | Joint actions | Sim-to-real, language commands | `nvidia/GR00T` [web:69] |

### 6.3 ACT Policy Configuration for SO-101

Based on community implementations [web:45][web:46][web:53]:

| Hyperparameter | Value | Notes |
|----------------|-------|-------|
| Chunk size | 50–100 | Number of future actions predicted |
| Learning rate | 1e-5 | Low LR for stability |
| Training steps | 30k–50k | Sufficient for 50–150 demos |
| Cameras | front + wrist | Multi-view improves generalization |
| Image size | 224×224 | Standard for ViT backbone |
| Augmentation | Color jitter, blur | Essential for sim-to-real |
| Loss | L1 + temporal smoothing | ACT default |

**Pretrained Checkpoint Available:**
- `davidlinjiahao/lerobot_so101_base_sim_pickplace` — trained on 105 human demonstrations in MuJoCo, loss converged to 0.089 [web:53].

### 6.4 When to Use vs. When to Avoid

| Use Policy | Do Not Use Policy |
|------------|-------------------|
| Fine approach after MoveIt brings arm near object | Full trajectory from home to grasp |
| Visual servoing for placement alignment | Collision avoidance in cluttered scenes |
| Gripper closing timing refinement | Grasp candidate generation |
| Recovery motions after failed grasp | Task-level decision making |

---

## 7. Low-Level Control

### 7.1 Joint-Level Trajectory Tracking

| Component | Implementation | Notes |
|-----------|---------------|-------|
| Interpolation | Cubic / quintic spline between waypoints | Smooth velocity profiles |
| Position control | PID per joint (built into STS3215) | Tunable via servo parameters |
| Velocity limits | Enforced in trajectory generation | Prevent mechanical stress |
| Acceleration limits | Ruckig time-optimal trajectory | Minimize vibration |

The STS3215 servos run **internal PID loops** at 1kHz with position feedback from the magnetic encoder. The host sends target positions at 30–50Hz, and the servo interpolates [web:80][web:82].

### 7.2 Gripper Control

| Mode | Control Variable | Feedback Signal | Use Case |
|------|-----------------|-----------------|----------|
| **Position control** | Target jaw opening (0–80mm) | Encoder position | Known object size |
| **Force-limited position** | Target position + max load | Servo load value | Fragile objects |
| **Slip detection** | Position hold + load monitoring | Position deviation under constant load | Verify grasp stability |

**Grasp Verification Logic:**
```python
def verify_grasp(servo):
    # Returns True if object is securely grasped
    load = servo.get_load()          # % of stall torque
    position = servo.get_position()  # current jaw opening

    # Conditions for stable grasp:
    # 1. Load is above minimum (contact made)
    # 2. Position is stable (not moving under load)
    # 3. Load is below overload threshold

    contact_made = load > 10  # >10% stall
    stable = abs(position - target_position) < 2  # < 2 encoder ticks drift
    safe = load < 80  # < 80% stall (before overload)

    return contact_made and stable and safe
```

### 7.3 Placement Precision Strategy

| Step | Action | Control Mode |
|------|--------|--------------|
| 1 | Move above target zone | MoveIt planned trajectory |
| 2 | Visual alignment (if needed) | Policy-based delta correction |
| 3 | Controlled descent | Linear motion, 5–10mm/s |
| 4 | Contact detection | Monitor load increase |
| 5 | Open gripper slowly | Position control, 20% speed |
| 6 | Verify object stability | Vision check + load release |
| 7 | Vertical retreat | 20mm upward, 50mm/s |

> **Precision Tip**: For tight tolerance placement, use **compliant motion**: command the arm to move downward with a force limit. When contact is detected (load spike), stop motion and open gripper. This avoids crushing the object or damaging the surface [web:63].

---

## 8. Closed-Loop Feedback (Mandatory)

### 8.1 Feedback Sources

| Source | Data | Update Rate | Purpose |
|--------|------|-------------|---------|
| **Overhead camera** | Object pose | 10–30 Hz | Pre-grasp detection, placement verification |
| **Wrist camera** | Local view | 10–30 Hz | Fine alignment, grasp quality |
| **Joint encoders** | Position, velocity | 50 Hz | Trajectory tracking, state estimation |
| **Servo load** | Torque estimate | 50 Hz | Grasp verification, contact detection |
| **Servo current** | Current draw | 50 Hz | Overload protection, force inference |

### 8.2 Correction Loops

| Loop | Trigger | Correction Action |
|------|---------|-------------------|
| **Pre-grasp re-detection** | Object not at expected pose after approach | Re-run perception, re-plan grasp |
| **Grasp verification** | Load too low / position drifting | Re-close gripper or abort and retry |
| **Transport monitoring** | Object slips (load drops suddenly) | Emergency stop, re-grasp |
| **Placement verification** | Object not in target zone after release | Re-detect, re-attempt placement |
| **Final check** | Post-task visual confirmation | Log success/failure, update dataset |

---

## 9. Simulation & Sim-to-Real Pipeline

### 9.1 Simulation Environments

| Simulator | SO-101 Support | Best For | Integration |
|-----------|--------------|----------|-------------|
| **MuJoCo** | Native (gym-so100-c) [web:65][web:86] | Policy training, RL | LeRobot, Gymnasium |
| **Isaac Lab** | NVIDIA official [web:69] | Sim-to-real, domain randomization | GR00T, LeRobot |
| **Gazebo Harmonic** | Community WIP [web:67] | ROS2 + MoveIt2 testing | ROS2 Control |

### 9.2 Isaac Lab + GR00T Pipeline (NVIDIA Recommended)

NVIDIA provides a complete learning path for SO-101 sim-to-real [web:69][web:74][web:78]:

| Stage | Action | Output |
|-------|--------|--------|
| 1 | Build standardized workspace (lightbox, cameras, mat) | Consistent real+sim environment [web:89] |
| 2 | Collect 50–200 teleop demos in Isaac Lab | Dataset with domain randomization |
| 3 | Train GR00T N1 VLA model | Policy checkpoint |
| 4 | Evaluate in simulation | Success rate, failure analysis [web:74] |
| 5 | Deploy to real SO-101 | Real-world evaluation [web:78] |
| 6 | Apply sim-to-real strategies | Domain randomization, co-training, actuator gap modeling |

### 9.3 MuJoCo + LeRobot Pipeline (Open-Source Standard)

| Stage | Command / Action | Notes |
|-------|-----------------|-------|
| 1 | Setup `gym-so100-c` environment | MuJoCo SO-101 arm, cube-to-bin task [web:65] |
| 2 | Collect demos via teleoperation | `lerobot-record` with leader arm |
| 3 | Train ACT policy | `lerobot-train` with config |
| 4 | Evaluate in sim | `lerobot-eval` with checkpoint [web:53] |
| 5 | Transfer to real | Load policy on real SO-101, fine-tune with 10–20 real demos |

---

## 10. Open-Source Ecosystem Summary

| Category | Tool / Dataset | Repository | Purpose |
|----------|--------------|------------|---------|
| **Framework** | LeRobot | `huggingface/lerobot` [web:18] | End-to-end training, dataset, deployment |
| **Framework** | ROS 2 Jazzy | `ros2` | Middleware, nodes, communication |
| **Planning** | MoveIt 2 | `moveit/moveit2` [web:84] | Motion planning, IK, collision checking |
| **Planning** | BehaviorTree.CPP | `BehaviorTree/BehaviorTree.CPP` [web:64] | Task-level behavior orchestration |
| **Simulation** | MuJoCo | `deepmind/mujoco` [web:23] | Physics simulation |
| **Simulation** | Isaac Lab | `isaac-sim/IsaacLab` [web:69] | NVIDIA sim-to-real pipeline |
| **Simulation** | Gazebo Harmonic | `gazebosim/gz-sim` [web:67] | ROS2-integrated simulation |
| **Perception** | YOLOv8 | `ultralytics/ultralytics` | Object detection |
| **Perception** | SAM 2 | `facebookresearch/segment-anything` | Instance segmentation |
| **Perception** | FoundationPose | `NVlabs/FoundationPose` [web:36] | 6D pose estimation |
| **Perception** | FoundationPoseROS2 | `ammar-n-abbas/FoundationPoseROS2` [web:51] | ROS2 wrapper |
| **Grasp** | GraspNet Baseline | `graspnet/graspnet-baseline` [web:38] | Grasp candidate scoring |
| **Grasp** | DexNet 2.0 Dataset | `berkeleyautomation/dexnet` [web:37] | GQ-CNN training data |
| **Grasp** | GraspNet-1Billion | `graspnet/graspnetAPI` [web:38] | Large-scale grasp benchmark |
| **Policy** | ACT | `lerobot` (integrated) [web:45] | Action chunking transformer |
| **Policy** | Diffusion Policy | `reke-dev/diffusion-policy` [web:40] | Diffusion-based policy |
| **Policy** | GR00T N1 | `nvidia/GR00T` [web:69] | Vision-language-action model |
| **Dataset** | LeRobot Datasets | `huggingface.co/lerobot` | Community robot datasets |
| **Pretrained** | SO-101 Sim Pick-Place | `davidlinjiahao/lerobot_so101_base_sim_pickplace` [web:53] | ACT checkpoint |

---

## 11. Implementation Roadmap

### Phase 1: Foundation (Weeks 1–2)
| Task | Deliverable |
|------|-------------|
| Assemble SO-101, calibrate servos | Functional follower arm |
| Mount RealSense, verify stream | RGB-D data in ROS2 |
| Setup ROS2 Jazzy + MoveIt 2 config | Planning pipeline for SO-101 |
| Test IK, basic joint trajectories | Verified motion capability |

### Phase 2: Perception + Grasping (Weeks 3–4)
| Task | Deliverable |
|------|-------------|
| Integrate YOLO + SAM2 detection | Object detection node |
| Add depth projection to 3D pose | Point cloud segment → 3D centroid |
| Implement antipodal grasp sampler | Grasp candidate generation |
| Test top-down grasps on known objects | >80% grasp success |

### Phase 3: Task Planning + Integration (Weeks 5–6)
| Task | Deliverable |
|------|-------------|
| Build BehaviorTree for pick-place | FSM with retry logic |
| Integrate MoveIt MTC pipeline | Full pick-place sequence |
| Add grasp verification (load check) | Closed-loop grasp confirmation |
| Add placement verification (vision) | Closed-loop placement confirmation |

### Phase 4: Learning Enhancement (Weeks 7–8)
| Task | Deliverable |
|------|-------------|
| Collect 50+ teleop demos in sim | LeRobot dataset |
| Train ACT policy for fine approach | Policy checkpoint |
| Evaluate in simulation | >90% success rate |
| Transfer to real, fine-tune | Real-world policy deployment |

### Phase 5: Robustness Hardening (Weeks 9–10)
| Task | Deliverable |
|------|-------------|
| Add domain randomization | Improved sim-to-real transfer |
| Test with object position variation | Generalization validation |
| Add failure recovery behaviors | Robust retry logic |
| Log metrics, iterate dataset | Continuous improvement pipeline |

---

## 12. Key Design Decisions & Justifications

| Decision | Rationale |
|----------|-----------|
| **MoveIt 2 over pure learning** | Classical planners guarantee collision-free, kinematically feasible paths. Learning is reserved for uncertainty handling [web:41][web:84]. |
| **Behavior Trees over scripted FSM** | BTs are the industry standard (Nav2, MoveIt2) for reactive, modular task switching with clean retry logic [web:64][web:68]. |
| **ACT as correction layer, not primary control** | ACT excels at smooth motion mimicry but lacks collision awareness. MoveIt handles structure; ACT handles finesse [web:45]. |
| **Hybrid grasp (analytic + learned)** | Analytic antipodal is fast, interpretable, and sufficient for parallel-jaw grippers. Learned scoring improves ranking in clutter [web:72][web:38]. |
| **Overhead + wrist camera** | Overhead provides global stability; wrist provides local detail. Dual-view redundancy improves robustness [web:57]. |
| **Servo load for grasp verification** | No external F/T sensor on SO-101. STS3215 load feedback is adequate for binary grasp success detection [web:82][web:85]. |
| **Isaac Lab for sim-to-real, MuJoCo for policy dev** | Isaac Lab offers NVIDIA-validated sim-to-real pipelines; MuJoCo is lighter for rapid policy iteration [web:69][web:65]. |

---

## 13. Expected Performance Metrics

| Metric | Baseline (Classical) | With ACT Refinement |
|--------|---------------------|---------------------|
| Grasp success rate | 85–90% | 90–95% |
| Placement accuracy | ±10 mm | ±5 mm |
| Cycle time | 15–20 sec | 12–18 sec |
| Success on position variation (±5cm) | 70% | 85% |
| Recovery from failed grasp | 60% (retry) | 80% (policy-adapted retry) |

> **Note**: These are estimates based on community reports with SO-100/101 arms. Actual performance depends on workspace calibration, lighting, and object properties [web:45][web:52][web:53].

---

## 14. Failure Modes & Mitigations

| Failure Mode | Cause | Mitigation |
|--------------|-------|------------|
| Detection miss | Occlusion, lighting change | Add temporal filter; retry with different camera angle |
| IK failure | Target near singularity / out of reach | Use approximate IK; select alternative grasp candidate |
| Grasp slip | Insufficient force, slippery object | Increase load threshold; add wrist camera for visual slip detection |
| Collision with table | Depth calibration error | Add table plane as collision object in MoveIt; use compliant descent |
| Placement miss | Object orientation error | Add visual alignment step before release |
| Policy divergence | Distribution shift | Fall back to classical planner; collect more real demos |

---

## 15. References & Resources

1. **SO-101 Hardware**: Seeed Studio Wiki [web:19], Waveshare Wiki [web:60], SVRC Specs [web:34]
2. **LeRobot Framework**: Hugging Face Docs [web:18], GitHub [web:18]
3. **ACT on SO-101**: Blog [web:45], YouTube [web:46], HuggingFace checkpoint [web:53]
4. **MoveIt 2 Pick-Place**: Automatic Addison tutorial [web:41], YouTube [web:84]
5. **ROS2 SO-101 Package**: brukg/SO-100-arm [web:62], Reddit community [web:67]
6. **Perception**: FoundationPose [web:36], FoundationPoseROS2 [web:51], OWG [web:50]
7. **Grasping**: GraspNet baseline [web:38], DexNet 2.0 [web:37], Antipodal grasping [web:72]
8. **Sim-to-Real**: NVIDIA Isaac Lab path [web:69], gym-so100-c [web:65][web:86]
9. **Control**: STS3215 specs [web:82][web:85], Servo testing [web:80][web:81]
10. **Task Planning**: BehaviorTree.CPP [web:64], ROS2 training [web:68]

---

*Document Version: 1.0 — Refined Industry-Grade Architecture for SO-101 Pick and Place*
