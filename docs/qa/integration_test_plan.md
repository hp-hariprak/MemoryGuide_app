# MemoryGuide Integration Test Plan

## 1. Overview and Objective
This document outlines the end-to-end integration test plan for **MemoryGuide** (Caregiver-Patient Safety System). As Member 5 (Notifications, Integration & QA Lead), this plan ensures complete validation across the FastAPI backend, Firebase Cloud Messaging (FCM) gateway, and Flutter mobile applications (`patient_app` and `caregiver_app`).

The primary goals are:
1. Validate seamless patient-to-caregiver alert flow (SOS Help & Geofence Exit alerts).
2. Ensure Firebase Cloud Messaging (FCM) notifications deliver reliably with high priority to linked caregivers.
3. Guarantee system resilience: notification failures must never block alert or location persistence.
4. Verify graceful degradation in development and testing environments when Firebase keys are absent.
5. Enforce privacy and safety standards (no raw FCM tokens or sensitive GPS coordinates exposed in logs or push payloads).

---

## 2. Test Architecture & Environment Matrix

| Environment | Backend Database | FCM Gateway | Mobile Network | Execution Scope |
| :--- | :--- | :--- | :--- | :--- |
| **Local CI / Pytest** | In-Memory SQLite | `FakeMessagingGateway` | N/A | Automated backend unit & integration tests (`uv run pytest`) |
| **Local Dev (Docker)** | PostgreSQL 15 | Mocked or Real FCM | Localhost / Emulator Loopback (`10.0.2.2`) | Scripted E2E verification (`verify_e2e.py`) |
| **Staging / QA** | Cloud PostgreSQL | Real Firebase Project | Wi-Fi / Cellular (Android Emulators & Devices) | Manual & recorded scenario tests |

---

## 3. Automated Test Coverage (Pytest)

The backend test suite contains **38 automated tests** executed via:
```bash
uv run --with-requirements requirements.txt pytest
```

### 3.1 Alert Flow Integration Tests (`backend/tests/test_integration_alert_flow.py`)
- **`test_full_patient_help_alert_and_push_lifecycle`**:
  - Exercises the entire SOS Help workflow:
    1. Patient and Caregiver authentication.
    2. Patient creates SOS Help alert (`POST /api/v1/patients/{id}/help`).
    3. Verifies alert committed with status `active` and notification status `sent`.
    4. Caregiver queries alerts (`GET /api/v1/patients/{id}/alerts`) and confirms alert presence.
    5. Caregiver acknowledges alert (`PATCH /api/v1/alerts/{id}` with `status="acknowledged"`).
    6. Caregiver resolves alert (`PATCH /api/v1/alerts/{id}` with `status="resolved"`).
    7. Verifies resolved alert lifecycle.
- **`test_full_geofence_exit_and_enter_lifecycle`**:
  - Configures safe zone center and radius for patient.
  - Posts location **inside** safe zone: verifies `inside_safe_zone=True` and no alert generated.
  - Posts location **outside** safe zone (breach): verifies `inside_safe_zone=False`, geofence exit alert created and committed, and `notify_geofence_exit` called with FCM push dispatched to linked caregiver.
  - Posts second consecutive outside location: verifies alert deduplication/throttling (no duplicate alert created).
  - Posts location back **inside** safe zone: verifies auto-recovery (`inside_safe_zone=True`) without throwing errors.

### 3.2 Notification Service Tests (`backend/tests/test_notifications.py`)
- **`test_send_alert_notification_sent`**: All tokens succeed -> delivery status `sent`.
- **`test_send_alert_notification_partial_and_prunes_invalid_tokens`**: Stale/unregistered tokens pruned automatically from DB; remaining valid tokens delivered -> status `partial`.
- **`test_send_alert_notification_all_failed`**: Gateway failure on all tokens -> delivery status `failed`, alert remains intact.
- **`test_send_alert_notification_no_devices`**: Caregiver has no registered device tokens -> delivery status `no_devices`.
- **`test_send_alert_notification_skipped_when_disabled`**: Notifications disabled in config -> delivery status `skipped`.
- **`test_notify_geofence_exit_suppresses_duplicate`**: Throttles duplicate exit pushes if an active geofence alert already exists.
- **`test_privacy_tokens_and_coordinates_not_logged`**: `caplog` inspection confirms raw FCM registration tokens and latitude/longitude coordinates are never written to logger output.

---

## 4. End-to-End Verification (`backend/scripts/verify_e2e.py`)

A 15-step sequential integration script validating real HTTP endpoints against the API contract:

```
[1]  Patient Login -> 200 OK, JWT returned
[2]  Caregiver Login -> 200 OK, JWT returned
[3]  Patient Auth /me & Profile -> Link code DEVLINK1 verified
[4]  Caregiver Patients List -> Linked patient verified
[5]  Patient Location Posting -> 201 Created
[6]  Patient Status Query -> location_available=True
[7]  Patient SOS Emergency Dispatch -> 201 Created (or 409 throttled)
[8]  Caregiver Alerts Retrieval -> SOS Alert present in items list
[9]  Caregiver Alert Acknowledgment -> status="acknowledged"
[10] Caregiver Alert Resolution -> status="resolved"
[11] Safe Zone Settings Config -> radius updated to 250m
[12] Landmarks Retrieval -> 200 OK
[13] Caregiver Device Token Registration -> 201 Created (FCM token registered)
[14] Geofence Breach Simulation -> Location outside safe zone triggers geofence exit alert
[15] Caregiver Device Token Unregistration -> 200 OK (FCM token cleaned up)
```

---

## 5. Mobile Client Integration & Manual Boundary Verification

### 5.1 Patient Application (`patient_app`)
| Test ID | Scenario | Expected Behavior | Verification Status |
| :--- | :--- | :--- | :--- |
| **MOB-PAT-01** | Cold boot without session | Displays `PatientLoginScreen`. | Code Verified |
| **MOB-PAT-02** | Cold boot with saved token | Restores session, mounts `SafeZoneHost`, shows green/red status banner. | Code Verified |
| **MOB-PAT-03** | SOS Button Pressed | Sends `POST /api/v1/patients/{id}/help`. Visual countdown (3s), audio feedback, confirmation dialog. | Code Verified |
| **MOB-PAT-04** | Duplicate SOS Pressed | 409 Conflict handled gracefully without error snackbar ("Help alert already active"). | Code Verified |
| **MOB-PAT-05** | GPS Location Reporting | Periodic updates posted to `/api/v1/patients/{id}/locations`. | Code Verified |
| **MOB-PAT-06** | Graceful Firebase degradation | Runs with `FakeMessagingGateway` if `google-services.json` is missing without crash. | Code Verified |

### 5.2 Caregiver Application (`caregiver_app`)
| Test ID | Scenario | Expected Behavior | Verification Status |
| :--- | :--- | :--- | :--- |
| **MOB-CG-01** | Login & Token Sync | Authenticates caregiver, calls `POST /api/v1/notifications/devices` with device FCM token. | Code Verified |
| **MOB-CG-02** | Foreground Push Notification | Push stream emits message -> Top snackbar/banner appears: *"Emergency Help Alert: [Patient Name]"* with **Open** action. | Code Verified |
| **MOB-CG-03** | Push Notification Tap | Tapping snackbar navigates/focuses directly on `CaregiverSafetyView` and refreshes alerts. | Code Verified |
| **MOB-CG-04** | 10s Polling Fallback | If FCM push is dropped or offline, timer polls `GET /api/v1/patients/{id}/alerts` every 10s and updates UI automatically. | Code Verified |
| **MOB-CG-05** | App Background to Foreground | `WidgetsBindingObserver.didChangeAppLifecycleState` triggers immediate alert refresh on resume. | Code Verified |
| **MOB-CG-06** | Logout & Token Cleanup | Calls `DELETE /api/v1/notifications/devices/{token}` and removes token from secure storage. | Code Verified |

---

## 6. Resilience & Failure Mode Validation

### 6.1 Non-Blocking Push Notification Policy
- **Requirement**: An FCM failure, network timeout, or Firebase quota exhaustion must **never** fail the HTTP request or roll back an alert or location point.
- **Verification**: In `AlertService.create_help` and `LocationService.report_location`, alerts and location coordinates are committed to the database **before** calling `notification_service`. The notification dispatch is enclosed in a `try...except` block logging errors at `ERROR` level without re-raising.

### 6.2 Firebase Gateway Fallback
- **Mobile**: Both mobile apps check `Firebase.apps.isNotEmpty` and verify the existence of native Google Services configuration before initializing Firebase Messaging. If absent, they inject `FakeMessagingGateway` and continue normal operation.
- **Backend**: If `FIREBASE_CREDENTIALS_FILE` is not set or missing on disk, `FirebaseMessagingGateway` falls back to `MockMessagingGateway`, returning simulated message IDs.

### 6.3 Privacy & Data Minimization
- **Requirement**: Never send latitude/longitude in the FCM push data payload or notification body.
- **Verification**: Push notification bodies contain only user-friendly text (e.g., *"John Doe requested emergency help"* or *"John Doe exited the safe zone"*). Payloads contain only `{"type": "help"|"geofence_exit", "alert_id": "...", "patient_id": "..."}`. Caregiver app fetches precise coordinates via authenticated REST endpoints.
- **Requirement**: FCM device tokens must never appear in log files.
- **Verification**: `notification_service.py` masks tokens as `[REDACTED]` or logs only device counts. Automated pytest `test_privacy_tokens_and_coordinates_not_logged` strictly asserts token absence in test log captures.
