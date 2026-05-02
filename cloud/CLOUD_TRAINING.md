# Training SO-101 ACT Policies in the Cloud (Fast Path)

Your M4 CPU is doing ~1.2-1.7 s/step. A free Colab T4 GPU does the same step
in ~0.05-0.1 s — that's **17-35× faster**. The compressed 8-hour CPU plan
becomes ~30-40 minutes on a T4. The original "full quality" plan
(50k / 60k / 40k steps with the full-size ACT model) becomes ~3-4 hours.

This folder gives you everything you need to move training to the cloud
**without disturbing the run currently going on your Mac.** When that finishes
or you decide to swap, follow this guide.

---

## TL;DR — what to use when

| Option                | Cost              | Speed vs M4 CPU | Setup pain | Session limits     | Best for                                       |
| --------------------- | ----------------- | --------------- | ---------- | ------------------ | ---------------------------------------------- |
| **Colab Free (T4)**   | $0                | ~17-35×         | low        | 12 h, can drop     | Single-task quick retrains                     |
| **Colab Pro (V100/L4)** | $10-12 / mo     | ~30-50×         | low        | 24 h, more stable  | Trying multiple hyperparam runs                |
| **Modal (A10G)**      | ~$1.10 / hr (~$3-8 total) | ~30-50× | medium     | none               | Unattended end-to-end training of all 3 tasks  |
| **RunPod / Vast.ai**  | ~$0.30-0.80 / hr  | ~30-100×        | higher     | none               | Lowest cost if you don't mind community GPUs   |
| **HF Inference Endpoints / Spaces** | n/a | n/a    | n/a        | n/a                | These are for serving inference, **not training** — skip |

If you're doing this once: **use Colab Free**. If you'll do many runs and don't want to babysit: **use Modal**.

---

## Step 0 (one-time): get a HuggingFace account

1. Sign up at <https://huggingface.co/join> (free).
2. Create a **write** access token at <https://huggingface.co/settings/tokens> →
   *New token* → role *Write* → copy it. You'll need this in steps 1 and 2.

Make a note of your HF username; it goes everywhere `<HF_USER>` appears below.

---

## Step 1: push the local datasets to the Hub (one-time, ~5-10 min)

This copies your three demo datasets (~1.6 GB total) to private repos on
your HF account so cloud runners can pull them down.

```bash
# Log in once on your Mac (does not affect the running training)
.conda/bin/huggingface-cli login   # paste your write token

# Push all three datasets
./cloud/upload_datasets_to_hf.sh <HF_USER> all

# Or push only one (e.g. you finished pick locally and just need plug/pour):
./cloud/upload_datasets_to_hf.sh <HF_USER> plug
./cloud/upload_datasets_to_hf.sh <HF_USER> pour
```

After this you should see three private dataset repos at
`https://huggingface.co/datasets/<HF_USER>/so101_pick_v1` (and `_plug_v1`, `_pour_v1`).

> **Heads-up:** the upload script only **reads** the local datasets. It will
> not interrupt or corrupt the training currently running on your Mac.

---

## Step 2 (Path A): Train on **Google Colab Free**

Best for: single-task training, no spend.

1. Go to <https://colab.research.google.com/>.
2. *File → Upload notebook* → choose `cloud/lerobot_train_colab.ipynb`.
3. *Runtime → Change runtime type → Hardware accelerator: T4 GPU* → Save.
4. In the **first code cell**, edit:
   - `TASK = "pick"` (or `"plug"` / `"pour"`)
   - `HF_USERNAME = "<HF_USER>"`
   - `FULL_QUALITY = False` (compressed, ~10 min) or `True` (full-size, ~30-90 min)
5. *Runtime → Run all*.
6. When prompted by `huggingface_hub.login()`, paste your write token.
7. The last cell pushes the trained policy to `<HF_USER>/act_<task>_v1` on the Hub.
8. Repeat steps 4-7 for `plug` and `pour` (each takes a few minutes).

**Pull the trained policies back to your Mac:**

```bash
.conda/bin/huggingface-cli download <HF_USER>/act_pick_v1 \
  --local-dir outputs/act_pick_v1/checkpoints/last/pretrained_model

.conda/bin/huggingface-cli download <HF_USER>/act_plug_v1 \
  --local-dir outputs/act_plug_v1/checkpoints/last/pretrained_model

.conda/bin/huggingface-cli download <HF_USER>/act_pour_v1 \
  --local-dir outputs/act_pour_v1/checkpoints/last/pretrained_model
```

After this, `scripts/run_full_demo.sh` works exactly as planned — it picks
up the policies from `outputs/act_*/checkpoints/last/pretrained_model`.

### Colab tips
- **Idle disconnect:** Colab kicks idle browsers off after ~30 min. Keep the
  tab focused or run a tiny `while True: time.sleep(60); print('.')` cell in
  parallel if needed.
- **Compute-units exhaustion:** the free tier has a daily/weekly cap. If you
  hit it, switch to a different Google account or use Modal/RunPod.
- **Want even better quality?** Set `FULL_QUALITY=True` and let it run for an
  hour — you'll get the original ACT-base model with 50k/60k/40k steps and the
  highest expected success rates.

---

## Step 2 (Path B): Train on **Modal** (unattended, all three at once)

Best for: not babysitting, no session timeouts, full-quality runs of all 3 tasks.

1. Sign up at <https://modal.com> (uses your Google/GitHub account; gives you $30 free credit, more than enough).
2. On your Mac (in a NEW terminal so the running training is undisturbed):
   ```bash
   .conda/bin/pip install modal
   .conda/bin/modal setup        # one-click browser auth
   ```
3. Add your HF token as a Modal secret:
   - Go to <https://modal.com/secrets>
   - *Create new secret* → *HuggingFace* template → name it `huggingface-secret`
   - Paste your HF write token in the `HF_TOKEN` field → save.
4. Run all three trainings end-to-end (sequential; ~2-3 h total, ~$3-8):
   ```bash
   HF_USER=<HF_USER> .conda/bin/modal run cloud/modal_train.py::run_all
   ```
   Or just one:
   ```bash
   HF_USER=<HF_USER> .conda/bin/modal run cloud/modal_train.py::run_one --task pick
   ```
5. Logs stream live to your terminal. When finished each policy is pushed to
   `<HF_USER>/act_<task>_v1`. Pull them down with the `huggingface-cli download`
   commands shown above.

**Why Modal vs Colab:**
- No 12 h disconnect risk.
- One terminal command kicks off all three trainings unattended.
- A10G has more VRAM than the free T4, so you can use larger batches if you experiment.
- Costs about $3-8 in total (well within the $30 free credit).

---

## Step 2 (Path C): RunPod / Vast.ai (cheapest if you want to tinker)

If you've used these before:

1. Spin up an RTX 3090 or A4000 community pod with the *PyTorch 2.4* template (~$0.30-0.50/hr).
2. SSH in and run:
   ```bash
   pip install lerobot==0.5.1 huggingface_hub
   huggingface-cli login
   huggingface-cli download <HF_USER>/so101_pick_v1 --repo-type dataset \
     --local-dir ~/.cache/huggingface/lerobot/<HF_USER>/so101_pick_v1
   ```
3. Run the same `lerobot-train` command from `cloud/lerobot_train_colab.ipynb`'s
   training cell, with `--policy.device=cuda`.

Skip this path if you're not already comfortable on a remote Linux box. Modal
or Colab is simpler.

---

## What about HuggingFace AutoTrain / Spaces / Inference Endpoints?

Short answer: **they don't fit our use case.**

- **AutoTrain** is built for tabular / NLP / image-classification fine-tuning,
  not LeRobot's ACT/Diffusion training pipeline.
- **Spaces** are for hosting interactive demos. Free Spaces don't have GPUs;
  paid GPU Spaces are designed for inference, not multi-hour training jobs.
- **Inference Endpoints** are pay-per-inference servers. They serve a model;
  they don't train one.

The Hub is great for **storing and shipping** datasets and trained checkpoints
(steps 1, 2, and the final pull). For the actual training compute, use Colab
or Modal.

---

## After cloud training: zero-change deployment

The directory layout under `outputs/act_*/checkpoints/last/pretrained_model`
is exactly what `scripts/run_full_demo.sh` expects, so once you've downloaded
the checkpoints you can simply run:

```bash
./scripts/run_full_demo.sh
```

…and the autonomous Pick → Plug → Pour sequence kicks off on your physical
robot, using the cloud-trained policies.

---

## Decision shortcut

- *"I want it free and don't mind clicking through Colab once per task."* → **Path A (Colab Free)**
- *"I want one command that trains everything overnight while I sleep."* → **Path B (Modal)**
- *"I'm a power user with my own RunPod account."* → **Path C**

Most people in your situation should pick **Path A** first; if you find Colab too flaky or want to over-train at full quality, jump to **Path B** — total spend will be under $10.
