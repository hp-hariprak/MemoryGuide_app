# MemoryGuide Live Demo Runbook & Fallback Procedures

## 1. Demo Overview & Objectives
- **Target Duration**: 5 to 7 minutes.
- **Audience**: Clinical partners, engineering team, caregivers, and stakeholders.
- **Objective**: Demonstrate the end-to-end patient safety loop:
  1. Passive location tracking and safe zone monitoring.
  2. One-tap emergency Help SOS dispatch from the patient app.
  3. High-priority push notification delivered to caregiver device with in-app foreground banner.
  4. Caregiver acknowledgement and workflow management.
  5. Automatic geofence breach detection (safe zone exit) with automated caregiver alert and resolution.
  6. Resilience: automatic fallback to 10s polling when Firebase or network connections degrade.

---

## 2. Personas & Test Credentials

| Role | Account Email | Password | Display Name | Device / Screen |
| :--- | :--- | :--- | :--- | :--- |
| **Patient** | `patient.dev@example.com` | `DevPass123!` | John Doe | Left Screen: `patient_app` |
| **Caregiver** | `caregiver.dev@example.com` | `DevPass123!` | Mary Doe | Right Screen: `caregiver_app` |

---

## 3. Pre-Demo Setup Checklist

### 3.1 Backend & Database
1. Ensure the backend server is running:
   ```bash
   cd backend
   uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
   ```
2. Verify API documentation is accessible at `http://localhost:8000/docs`.
3. Verify test environment passes:
   ```bash
   uv run --with-requirements requirements.txt pytest
   ```

### 3.2 Display & Window Arrangement
- **Screen Resolution**: 1920 × 1080 (1080p) landscape.
- **Layout**: Side-by-side split screen:
  - **Left 50%**: Patient App (Android Emulator or mirrored physical device, portrait 1080×1920).
  - **Right 50%**: Caregiver App (Android Emulator or mirrored physical device, portrait 1080×1920).
- **Audio**: Dedicated microphone input, clear audio, system notification sounds unmuted to capture push chime.

---

## 4. Scene-by-Scene Script

```
+---------------------------------------+---------------------------------------+
|          PATIENT APP (LEFT)           |         CAREGIVER APP (RIGHT)         |
|  - Big, accessible SOS button         |  - Patient list & safety status       |
|  - High-contrast Safe Zone banner     |  - Interactive map & geofence circle  |
|  - Passive GPS reporting              |  - Alert tray (Ack / Resolve)         |
+---------------------------------------+---------------------------------------+
```

### Scene 1: Introduction & Dual-App Login (0:00 – 0:45)
- **Spoken Commentary**:
  > *"Welcome to the MemoryGuide live demonstration. MemoryGuide is a specialized safety platform designed for individuals living with early-to-moderate dementia and their caregivers. On the left is our Patient app—designed with ultra-high contrast, large touch targets, and zero cognitive load. On the right is the Caregiver app—providing family members real-time visibility, geofence monitoring, and instant emergency alerts."*
- **Action**:
  - Log in on Left (Patient): `patient.dev@example.com`.
  - Log in on Right (Caregiver): `caregiver.dev@example.com`.
- **Expected Visuals**:
  - Patient app restores session and displays green **"Inside Safe Zone"** banner and large red **"CALL HELP"** button.
  - Caregiver app lists linked patient *"John Doe"* with green status indicator.

### Scene 2: Safe Zone Baseline & Tracking (0:45 – 1:30)
- **Spoken Commentary**:
  > *"The patient app runs passive background GPS telemetry without draining battery or confusing the user. On the caregiver dashboard, we can see John's current coordinates centered around his home safe zone (250m radius). Everything is calm, safe, and synchronized."*
- **Action**:
  - In Caregiver app, tap on John Doe to open `CaregiverSafetyView`.
  - Highlight the safe zone circle on the map and the status badge showing *"Inside Safe Zone"*.
- **Expected Visuals**:
  - Safe zone perimeter shown in light blue; patient pin centered inside.

### Scene 3: Emergency SOS Trigger & Instant Push (1:30 – 2:45)
- **Spoken Commentary**:
  > *"Now imagine John becomes disoriented or falls. He taps the large 'CALL HELP' button. A 3-second safety countdown initiates to prevent accidental taps, accompanied by audible ticking, before dispatching."*
- **Action**:
  - Tap **"CALL HELP"** on the Patient app. Allow the 3s countdown to complete.
- **Expected Visuals & Audio**:
  - Patient app: Confirmation dialog appears: *"Help request sent. Your caregiver has been notified."*
  - Caregiver app: Within milliseconds, high-priority notification chime plays. A top banner/snackbar drops down:
    > **⚠️ Emergency Help Alert: John Doe requested immediate assistance**  
    > Action: **[Open]**
  - Alert tray on the Caregiver view immediately displays a red active card: *"SOS Help Requested"*.

### Scene 4: Caregiver Acknowledges Alert (2:45 – 3:30)
- **Spoken Commentary**:
  > *"The caregiver immediately sees the alert and taps 'Acknowledge'. This informs the system that help is on the way and prevents alert escalation, updating both the backend state and the audit trail."*
- **Action**:
  - On the Caregiver app, tap **"Acknowledge"** on the active SOS alert card.
- **Expected Visuals**:
  - Alert card status changes from red `ACTIVE` to orange `ACKNOWLEDGED`.
  - Audit timestamp recorded.

### Scene 5: Geofence Breach Simulation (3:30 – 4:45)
- **Spoken Commentary**:
  > *"Next, we demonstrate automatic geofence monitoring. Even if the patient cannot tap the SOS button, the system autonomously protects them. Watch what happens when the patient drifts outside the safe zone boundary."*
- **Action**:
  - Trigger breach via emulator GPS mock or run CLI script:
    ```bash
    python backend/scripts/demo_trigger.py --action outside
    ```
- **Expected Visuals**:
  - Patient app: Safe zone banner flips from green **"Inside Safe Zone"** to high-contrast red: **"Outside Safe Zone"**.
  - Caregiver app: Receives high-priority push:
    > **🚨 Safe Zone Breach: John Doe has exited the safe zone**
  - Caregiver alert tray pops a new active `geofence_exit` alert.

### Scene 6: Resolution & Recovery (4:45 – 5:30)
- **Spoken Commentary**:
  > *"The caregiver contacts John or locates him, and taps 'Resolve'. The system returns to normal monitoring. When John returns home, the banner automatically reverts to safe."*
- **Action**:
  - On Caregiver app, tap **"Resolve"** on all alerts.
  - Reset location back inside safe zone:
    ```bash
    python backend/scripts/demo_trigger.py --action inside
    ```
- **Expected Visuals**:
  - Patient app banner turns green **"Inside Safe Zone"**.
  - Caregiver alert tray shows *"No active alerts"*.

### Scene 7: Resilience & Architecture Wrap-up (5:30 – 6:15)
- **Spoken Commentary**:
  > *"Under the hood, MemoryGuide is built for high reliability. Push notifications are completely non-blocking: alerts are committed to the database before FCM dispatch. And even if Google Play Services or network connectivity drops, the caregiver app's 10-second polling fallback automatically synchronizes all safety events. Thank you."*

---

## 5. Live Demo Fallback Procedures

If unexpected issues occur during a live demonstration or presentation, execute these standard fallbacks smoothly without breaking presentation flow:

### Fallback A: Push Notification Delay or FCM Outage
- **Symptom**: Caregiver device does not receive the FCM push notification banner within 3 seconds.
- **Handling**:
  - **Narrative**: *"Notice how even if cellular networks delay push notifications, our built-in 10-second reactive polling fallback ensures the caregiver dashboard captures the alert automatically."*
  - **Action**: Within 10 seconds, `CaregiverSafetyView`'s background timer calls `/api/v1/patients/{id}/alerts` and the alert card pops into view automatically. You can also swipe down to refresh manually.

### Fallback B: Emulator GPS Mock Not Updating
- **Symptom**: Android emulator location mock is unresponsive or locked.
- **Handling**:
  - **Action**: Keep a terminal window open in the background. Execute:
    ```bash
    # To simulate instant SOS:
    python backend/scripts/demo_trigger.py --action help

    # To simulate geofence exit breach:
    python backend/scripts/demo_trigger.py --action outside

    # To simulate safe return:
    python backend/scripts/demo_trigger.py --action inside
    ```
  - **Narrative**: *"We can also simulate field telemetry directly via our verified integration gateway."*

### Fallback C: Corrupted Local State or Stale Database
- **Symptom**: 409 Conflict persists on SOS Help because an unresolved alert exists from prior testing.
- **Handling**:
  - **Action**: In Caregiver app, tap **"Resolve"** on the existing card, or run:
    ```bash
    uv run python backend/scripts/verify_e2e.py
    ```
    which creates, acknowledges, and resolves alerts cleanly.

---

## 6. Video Recording & Screen Capture Checklist

- [ ] Clean build of both mobile apps without debug banners (`--release` or debug banner hidden).
- [ ] Notification permissions pre-approved in Android system settings (`Settings -> Apps -> Caregiver App -> Notifications -> Allow`).
- [ ] Device volumes set to 75% for crisp notification audio playback.
- [ ] Resolution set to 1080p (1920×1080), 30fps or 60fps, MP4/WebM container.
- [ ] Terminal window minimized or hidden during mobile recording unless demonstrating CLI triggers.
- [ ] Total video duration stays between **5:00 and 7:00 minutes**.
