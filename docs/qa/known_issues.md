# MemoryGuide Known Issues & Technical Debt Log

This document tracks identified bugs, edge cases, cross-member architectural debt, and their resolution status following the Stage 0–4 audit and integration cycle conducted by Member 5 (Notifications, Integration & QA Lead).

---

## 1. Summary of Audit Findings (F1 – F10)

| Issue ID | Severity | Description | Owner | Status | Stage Addressed |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **F1** | High | Missing FCM notification dispatch on geofence exit | Member 5 | **RESOLVED** | Stage 1 (`location_service.py`) |
| **F2** | High | FCM notifications lacked Android high priority & channel ID | Member 5 | **RESOLVED** | Stage 1 (`notification_service.py`) |
| **F3** | Medium | Patient SOS button threw unhandled 409 exception on duplicate | Member 5 | **RESOLVED** | Stage 2 (`patient_home_screen.dart`) |
| **F4** | High | Caregiver app had no push stream listener or foreground banner | Member 5 | **RESOLVED** | Stage 2 (`caregiver_safety_view.dart`) |
| **F5** | Medium | Device FCM tokens were not unregistered on user logout | Member 5 | **RESOLVED** | Stage 2 (`caregiver_auth_repository.dart`) |
| **F6** | Medium | Cold boot session restoration in Patient app | Member 4 / 5 | **RESOLVED / MITIGATED** | Stage 2 (`patient_app/app.dart`) |
| **F7** | Medium | Caregiver map live location updates require manual interaction | Member 3 | **OPEN / DOCUMENTED** | Backlog (Caregiver App) |
| **F8** | Low | Safe zone radius validation enforced only in Pydantic schema | Member 2 | **OPEN / DOCUMENTED** | Backlog (Backend Database) |
| **F9** | Low | SQLite vs PostgreSQL UUID / JSON dialect differences in tests | Member 2 / 5 | **MITIGATED / DOCUMENTED** | Stage 1 & 4 (Pytest Suite) |
| **F10**| Medium | Hard dependency on Firebase credentials broke local CI | Member 5 | **RESOLVED** | Stage 1 & 3 (`FakeMessagingGateway`) |

---

## 2. Detailed Issue Reports & Recommendations

### F1: Missing Geofence Exit Push Notification Dispatch
- **Severity**: High (Safety Critical)
- **Component**: `backend/app/services/location_service.py`
- **Root Cause**: When a patient reported coordinates outside the active safe zone, `LocationService.report_location` created and committed a `geofence_exit` alert in the database, but never invoked `notification_service` to notify linked caregivers.
- **Resolution**: Implemented `notify_geofence_exit()` in `notification_service.py` with duplicate suppression, and wired it into `location_service.py` immediately after committing the alert.
- **Verification**: Verified via `test_full_geofence_exit_and_enter_lifecycle` in `test_integration_alert_flow.py` and `test_notify_geofence_exit_suppresses_duplicate` in `test_notifications.py`.

---

### F2: Missing Android High Priority & Channel ID in FCM Payloads
- **Severity**: High (Clinical Alert Latency)
- **Component**: `backend/app/services/notification_service.py`
- **Root Cause**: FCM messages were constructed using generic `messaging.Message` without `AndroidConfig` or `AndroidNotification`. On Android 8.0+, push notifications without a designated notification channel or with standard priority are throttled by Android Doze mode and fail to wake the device.
- **Resolution**: Configured `android=messaging.AndroidConfig(priority="high", notification=messaging.AndroidNotification(channel_id="memoryguide_alerts", sound="default"))`.
- **Verification**: Inspected payload construction in `notification_service.py` and verified delivery via backend test suite.

---

### F3: Unhandled 409 Conflict on Patient SOS Trigger
- **Severity**: Medium (User Confusion / UX)
- **Component**: `mobile/patient_app/lib/features/home/patient_home_screen.dart`
- **Root Cause**: If the patient tapped the SOS button while an active help request was already open, the backend returned `409 Conflict` (`DUPLICATE_HELP_REQUEST`). The patient app caught this as a generic `ApiException` and popped a red error snackbar ("Failed to send help request"), alarming the patient.
- **Resolution**: Updated `EmergencySosButton.onTriggered` to catch `ApiException` with code `DUPLICATE_HELP_REQUEST`, treating it as a successful dispatch ("Help request is already active and your caregiver has been notified").
- **Verification**: Code verified and manually tested against simulated 409 responses.

---

### F4: Caregiver App Missing Foreground Push Listener & In-App Banner
- **Severity**: High (Caregiver Situational Awareness)
- **Component**: `mobile/caregiver_app/lib/features/safety/caregiver_safety_view.dart`
- **Root Cause**: While push notifications appeared in the Android notification drawer when the app was in the background, if the caregiver was actively looking at the app in the foreground, Firebase does not display system heads-up notifications by default.
- **Resolution**: Subscribed `CaregiverSafetyView` to `pushNotificationService.onMessageReceived`. When an alert push arrives in the foreground, a prominent `SnackBar` displays with high-contrast text and an **"Open"** action button that automatically reloads the alert feed. In addition, an automatic 10-second polling timer was implemented as a fail-safe fallback.
- **Verification**: Verified via `push_notification_service_test.dart` and integration tests.

---

### F5: Device Tokens Never Unregistered on Logout
- **Severity**: Medium (Privacy & False Push Routing)
- **Component**: `mobile/caregiver_app/lib/data/repositories/caregiver_auth_repository.dart`
- **Root Cause**: When a caregiver logged out of the app, the device FCM token remained in the backend `device_tokens` table. If another user subsequently logged in on the same physical device, or if the caregiver intended to go off-duty, pushes would continue to be delivered to that device.
- **Resolution**: Updated `logout()` in both `CaregiverAuthRepository` and `AuthRepository` to call `pushNotificationService.unregisterToken()` before clearing secure credentials.
- **Verification**: Tested in `push_notification_service_test.dart` and Step 15 of `backend/scripts/verify_e2e.py`.

---

### F6: Cold Boot Session Restoration in Patient App
- **Severity**: Medium
- **Component**: `mobile/patient_app/lib/app.dart` & `main.dart`
- **Owner**: Member 4 (Patient App Lead) / Member 5
- **Status**: **RESOLVED / MITIGATED**
- **Detail**: The initial `app.dart` unconditionally pointed `home: const PatientLoginScreen()`, requiring the dementia patient to re-enter email and password every time the app launched from cold boot.
- **Fix Applied**: Added `_checkSession()` in `_MemoryGuideAppState` to restore auth state from `FlutterSecureStorage`. If valid, routes immediately to `SafeZoneHost`.
- **Remaining Debt**: Native Android background wake-up directly from a killed state when tapping a notification requires configuring `launchMode="singleTask"` and native intent handlers in `MainActivity.kt`.

---

### F7: Caregiver Map Live Location Real-Time Updates
- **Severity**: Medium
- **Component**: `mobile/caregiver_app/lib/features/safety/caregiver_safety_view.dart`
- **Owner**: Member 3 (Caregiver App Lead)
- **Status**: **OPEN / DOCUMENTED (Backlog)**
- **Detail**: The caregiver map pin displays the patient's last reported location at the moment the view is loaded. If the patient is walking outside the safe zone, the pin remains static unless the caregiver manually triggers a pull-to-refresh or navigates away and back.
- **Recommended Fix**: Add a 5–10 second polling timer or WebSocket connection to stream live coordinates to the map when `CaregiverSafetyView` is in the foreground.

---

### F8: Safe Zone Radius Validation Enforced Only in Pydantic Schema
- **Severity**: Low
- **Component**: `backend/app/models/patient_settings.py`
- **Owner**: Member 2 (Backend API & DB Lead)
- **Status**: **OPEN / DOCUMENTED (Backlog)**
- **Detail**: Pydantic schema `PatientSettingsUpdate` enforces `Field(ge=50.0, le=5000.0)` for `safe_zone_radius_meters`. However, the SQLAlchemy model `PatientSettings` has no database-level `CheckConstraint`. Direct SQL queries or internal services could bypass this validation.
- **Recommended Fix**: Add `CheckConstraint('safe_zone_radius_meters >= 50.0 AND safe_zone_radius_meters <= 5000.0', name='check_safe_zone_radius')` to `PatientSettings` model in the next database migration.

---

### F9: SQLite vs PostgreSQL Dialect Differences in Pytest
- **Severity**: Low
- **Component**: `backend/app/db/` & `backend/tests/`
- **Owner**: Member 2 (Backend API & DB Lead) / Member 5
- **Status**: **MITIGATED / DOCUMENTED**
- **Detail**: In SQLite, passing string UUIDs directly to SQLAlchemy queries expecting `GUID` columns triggers `AttributeError: 'str' object has no attribute 'hex'`. PostgreSQL natively coerces string UUIDs.
- **Resolution**: All test assertions and repository queries use explicit `uuid.UUID` objects or call `UserRepository.get_by_id(UUID(id))`. Both test runners (SQLite in-memory) and production (PostgreSQL) now execute cleanly.

---

### F10: Hard Dependency on Firebase Credentials in Local CI
- **Severity**: Medium
- **Component**: `backend/app/services/notification_service.py` & `mobile/`
- **Owner**: Member 5
- **Status**: **RESOLVED**
- **Detail**: Without a valid `google-services.json` or `firebase-credentials.json`, test suites crashed on startup attempting to connect to Google servers.
- **Resolution**: Created `FakeMessagingGateway` in Dart and `MockMessagingGateway` in Python. Both environments gracefully detect missing credentials and fallback to mock interfaces, ensuring 100% test pass rate in disconnected environments.
