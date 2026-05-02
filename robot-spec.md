# **1\. Exact Robot Names (No Confusion)**

From the **robot manual (image)**:

* **WOWROBO SO-ARM101 Dual Arm Desktop Robot**  
* Version: **Assembled Version Only**

From the **hackathon problem statement (PDF)**:

* **LeRobot SO101**

Clarification:

* These refer to the **same robot platform used in the competition context**  
* Use **LeRobot SO101** when referring to the hackathon  
* Use **WOWROBO SO-ARM101** when referring to the physical hardware/manual

---

# **2\. Important Links (Exact)**

From the robot manual:

1. YouTube Setup / Operation Guide  
    https://www.youtube.com/watch?v=70GzU2t8yk  
2. Official Documentation  
    [https://huggingface.co/docs/lerobot/so101](https://huggingface.co/docs/lerobot/so101)  
3. Community Support (Discord)  
    https://discord.gg/GnTGTv0C4

---

# **3\. Setup and Power Requirements**

* Leader Arm: **5V / 6A power supply**  
* Follower Arm: **12V / 8A power supply**  
* Camera: connect via **USB port**

---

# **4\. Operation and Calibration Instructions**

* Servo calibration must be performed **before first use**  
* Incorrect calibration can cause:  
  * Wrong movement direction  
  * Unstable or unintended behavior  
* If abnormal movement occurs:  
  * Stop immediately  
  * Re-run calibration procedure

---

# **5\. Safety Constraints**

* Maximum payload: **400 grams**  
* Exceeding payload limit:  
  * Can damage servos  
* Damage due to:  
  * Overload  
  * Improper operation  
     is **not covered under warranty**

---

# **6\. Hackathon Tasks (Semifinal Round)**

According to the problem statement :

Each team must perform **three independent tasks**.

---

## **Task 1 – Object Pick and Place**

Robot must:

1. Detect an object at a known location using onboard sensors  
2. Grasp the object securely with the end effector  
3. Move the object to a specified target location  
4. Place the object precisely and release it

Challenge:

* Consistent detection and grasp under varying poses  
* Precision during movement

Success Metric:

* Object reaches target within tight tolerance  
* Object is not dropped  
* Completion time may be considered

---

## **Task 2 – Charger Plugging**

Robot must:

1. Detect a cable and connector within its workspace  
2. Grasp the connector firmly  
3. Align the connector with the socket  
4. Insert the connector until fully engaged

Challenge:

* Precise alignment of a flexible connector  
* Handling small misalignments

Success Metric:

* Successful insertion on first attempt  
* Minimal orientation error  
* Connector remains secure during pull test

---

## **Task 3 – Liquid Pouring**

Robot must:

1. Grasp a bottle containing liquid  
2. Move the bottle above a receiving cup  
3. Tilt the bottle to pour liquid  
4. Stop pouring at the desired volume

Challenge:

* Controlling pour angle and rate  
* Avoiding spills  
* Accurate volume transfer

Success Metric:

* Volume matches target within tolerance  
* No liquid spills outside the container

---

# **7\. Additional Task (Separate)**

## **Task 4 – Dynamic Humanoid Walking**

Robot must:

1. Use humanoid URDF for walking simulation without falling  
2. Use webcam-based pose estimation (e.g., MediaPipe)  
3. Handle mismatch between human and robot joint limits  
4. Maintain stability while following human motion

This task is:

* Separate from the main three manipulation tasks  
* Not part of the final sequential challenge

---

# **8\. Final Round Requirement**

Teams must execute the following **in sequence without human intervention**:

1. Object Pick and Place  
2. Charger Plugging  
3. Liquid Pouring

Key requirement:

* Smooth transitions between tasks  
* Robustness to variations in environment

---

# **9\. Robot Platform Specification**

From the problem statement :

* Semifinal round:  
  * Simulation only  
  * No physical robot provided  
* Final round:  
  * Physical robot provided:  
    * **LeRobot SO101**  
* Provided resources:  
  * URDF (Unified Robot Description Format)  
  * Environment models  
  * Baseline implementation

---

# **10\. Simulation Environment Options**

Supported simulators:

* MuJoCo  
* Webots  
* Gazebo

Teams are allowed to:

* Build custom control algorithms  
* Design their own perception pipelines

---

# **11\. Key Technical Domains Required**

From the problem statement:

* Embedded AI  
* Vision-Language-Action (VLA) models  
* Physical AI system design  
* Simulation to real-world transfer  
* Reinforcement learning for robotics

