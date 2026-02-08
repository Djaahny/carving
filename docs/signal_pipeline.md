# IMU Signal Pipeline (Dedup → Resample → Denoise → Feature Extraction)

This note captures a robust, offline-friendly IMU pipeline designed to handle bursty delivery, occasional sensor glitches, and missing data. It is organized as three stages: **(1) physical envelope checks**, **(2) filtering stack**, and **(3) validation + feature extraction**.

## 1) Physical envelope (“reality firewall”)

**Goal:** Tag every IMU sample as `OK / suspicious / invalid` based on plausible boot-mounted motion. These flags act as a control plane for the rest of the pipeline.

### 1.1 Unit sanity check (gyro)

Before applying thresholds, confirm gyro units:

- If typical |ω| during steady skiing is around **0–5**, treat the data as **rad/s**.
- If typical |ω| is **50–300**, treat it as **deg/s**.

Once units are known, apply thresholds in that unit system.

### 1.2 Acceleration magnitude envelope

Let `a = sqrt(Ax^2 + Ay^2 + Az^2)` (in **g** if Ax/Ay/Az are in g):

- **Normal:** ~0.8–2.5 g
- **Hard but plausible:** up to ~5–6 g (short spikes)
- **Probably wrong:** > 8 g (unless you expect cliff drops)

### 1.3 Gyro magnitude envelope (rad/s example)

Let `ω = sqrt(Gx^2 + Gy^2 + Gz^2)`:

- **Normal:** typically < 10 rad/s
- **Suspicious:** 20–35 rad/s
- **Invalid:** > 35 rad/s

Adjust these thresholds upward if you confirm the data is in deg/s.

### 1.4 Left vs right consistency checks

Skiing is asymmetric, but not wildly so. For any time `t` where both feet exist:

- If one foot’s `ω` is ~10× the other for multiple consecutive samples → flag the high channel as **bad** for that segment.
- Same check for acceleration magnitude.

### 1.5 Output of envelope stage

Store for each sample:

- `valid_imu_left`, `valid_imu_right`
- `quality_left`, `quality_right` (0..1)
- `reason_flags` (e.g., `GYRO_SPIKE`, `ACC_SPIKE`, `DUP_TIMESTAMP`)

## 2) Filtering stack (dedup → resample → de-spike → low-pass)

This is the core of the pipeline. It prevents Bluetooth bursts and spikes from being misclassified as turns.

### 2.1 Deduplicate by timestamp

Data can contain repeated timestamps. For each timestamp bucket:

- Prefer **median** of each channel (robust to spikes).
- Alternatively, keep the **last sample** if ordering is trusted.

### 2.2 Resample to fixed rate

Most filtering assumes uniform dt. Resample after de-duplication:

- Choose **50 Hz** for efficiency or **100 Hz** for cleaner turn boundaries.
- Use **linear interpolation** per channel.
- If gap `dt > 0.2–0.5s`, **do not interpolate**; mark as invalid segment.

### 2.3 De-spike (before low-pass)

Remove spikes so they don’t smear into the signal:

- **Hampel filter** (median + MAD), window ≈ 0.3s, `k=4–6`.
- Or **median filter** window 5–9 samples (simple fallback).

### 2.4 Low-pass filter

Ski turns are low-frequency. Boot vibration is high-frequency noise.

- Use 2nd–4th order **Butterworth** with cutoff **6–8 Hz** for turn detection.
- If you need chatter later, consider **10–12 Hz**.
- Use **zero-phase** (filtfilt) if offline.

## 3) Validation + feature extraction

### 3.1 Turn window detection (IMU-only)

A robust starting approach:

1. Compute gyro magnitude `ω(t)` (after filtering).
2. Smooth with a low-pass envelope (≈ 3–4 Hz).
3. Detect activity segments where `ω_s(t)` exceeds a threshold:
   - `thr = median(ω_s) + 2.5 * MAD(ω_s)` (adaptive)
4. Enforce minimum half-cycle duration ≈ **0.4–0.6 s**.
5. Define turn boundaries at **local minima** between peaks.

**Two-foot fusion:**

- Detect turns per foot, then merge if boundaries are within ±0.2 s.
- If one foot is invalid (envelope stage), use the other.

### 3.2 “Fall-line” moment per turn

For a practical proxy without GPS:

- Define fall-line index as time of **max `ω_s(t)`** within the turn window.

### 3.3 Slope pitch estimate per turn

Estimate gravity with a very low-pass accelerometer filter:

- `a_lp` cutoff ≈ **0.3 Hz**.
- `g_hat = a_lp / ||a_lp||`.

If a “standing still” calibration segment exists (low gyro + speed ≈ 0), use its gravity vector as upright reference. Pitch can be defined as the angle between `g_hat` and your forward axis (if known), or as a relative change vs calibration.

### 3.4 Quality gating

For each turn window, compute a **quality score**:

- % of valid samples
- # of spike flags
- dt gap count
- left/right consistency score

If quality < threshold, mark the turn unreliable and skip pitch metrics.

---

## Implementation skeleton (logic only)

```
RAW SAMPLES
  → dedup by timestamp (median)
  → resample to fixed Fs (mark gaps)
  → per-foot envelope flags (acc/gyro plausibility)
  → de-spike (Hampel/median)
  → low-pass for turn signals (6–8 Hz)
  → very-low-pass accel for gravity (0.3 Hz)
  → turn detection from ω envelope (per foot)
  → merge turns L/R with quality gating
  → fall-line per turn (max ω envelope)
  → pitch at fall-line (gravity estimate + calibration)
  → per-turn outputs + confidence
```
