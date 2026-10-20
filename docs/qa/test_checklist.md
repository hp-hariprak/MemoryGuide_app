# MemoryGuide QA Test Checklist

A shared test verification matrix covering core API security, role-based access control, alerting workflows, push notification delivery, and mobile client resiliency.

**Legend**:
- `[ ]` Not run / Pending
- `[x]` Verified / Passing
- **Automation Status**: Automated in `backend/tests/...` or `mobile/.../test/...`, or Manual.

---

## 1. Authentication & Identity

| ID | Test Scenario | Steps | Expected Result | Owner | Automated? | Status |
|---|---|---|---|---|---|---|
| AUTH-01 | Patient Registration | `POST /api/v1/auth/register` with valid email, password, full_name, `role="patient"` | Returns `201 Created`, JWT token, user profile, and unique `link_code` generated | Member 3 | Yes (`backend/tests/test_auth.py:test_register_patient`) | [ ] |
| AUTH-02 | Caregiver Registration | `POST /api/v1/auth/register` with `role="caregiver"` | Returns `201 Created`, JWT token, user profile; `link_code` is null | Member 3 | Yes (`backend/tests/test_auth.py:test_register_caregiver`) | [ ] |
| AUTH-03 | Duplicate Email Rejection | Register with already registered email | Returns `409 Conflict` (`DUPLICATE_EMAIL`) | Member 3 | Yes (`backend/tests/test_auth.py:test_register_duplicate_email`) | [ ] |
| AUTH-04 | User Login (Success) | `POST /api/v1/auth/login` with seeded credentials | Returns `200 OK`, JWT `access_token`, user object | Member 3 | Yes (`backend/tests/test_auth.py:test_login_success`) | [ ] |
| AUTH-05 | Login Wrong Password | `POST /api/v1/auth/login` with invalid password | Returns `401 Unauthorized` (`AUTHENTICATION_FAILED`) with opaque error message | Member 3 | Yes (`backend/tests/test_auth.py:test_login_wrong_password`) | [ ] |
| AUTH-06 | Login Unknown Email | `POST /api/v1/auth/login` with non-existent email | Returns `401 Unauthorized` (`AUTHENTICATION_FAILED`) identical to wrong password | Member 3 | Yes (`backend/tests/test_auth.py:test_login_unknown_email`) | [ ] |
| AUTH-07 | Current User Me (`/auth/me`) | `GET /api/v1/auth/me` with valid bearer token | Returns `200 OK` with user details; patient includes `link_code`; password hash never returned | Member 3 | Yes (`backend/tests/test_auth.py:test_get_me_patient`) | [ ] |
| AUTH-08 | Expired / Invalid Token | `GET /api/v1/auth/me` with expired or forged JWT | Returns `401 Unauthorized` (`TOKEN_EXPIRED` or `TOKEN_INVALID`) | Member 3 | Yes (`backend/tests/test_auth.py:test_expired_token`) | [ ] |

---

## 2. Caregiver–Patient Linking (Consent Flow)

| ID | Test Scenario | Steps | Expected Result | Owner | Automated? | Status |
|---|---|---|---|---|---|---|
| LINK-01 | Link via Valid Code | Caregiver calls `POST /api/v1/caregivers/patients` with `{ "link_code": "DEVLINK1" }` | Returns `201 Created` relationship; caregiver is now linked | Member 3 | Yes (`backend/tests/test_relationships.py:test_link_success`) | [ ] |
| LINK-02 | Link with Invalid Code | Caregiver submits non-existent code `INVALID99` | Returns `404 Not Found` (`NOT_FOUND`) | Member 3 | Yes (`backend/tests/test_relationships.py:test_link_invalid_code`) | [ ] |
| LINK-03 | Duplicate Link Attempt | Caregiver submits code for already linked patient | Returns `409 Conflict` (`ALREADY_LINKED`) | Member 3 | Yes (`backend/tests/test_relationships.py:test_link_already_linked`) | [ ] |
| LINK-04 | Patient Cannot Call Link | Patient token calls `POST /api/v1/caregivers/patients` | Returns `403 Forbidden` (`FORBIDDEN`) | Member 3 | Yes (`backend/tests/test_authorization.py`) | [ ] |
| LINK-05 | List Linked Patients | Caregiver calls `GET /api/v1/caregivers/patients` | Returns `200 OK` list containing only actively linked patients | Member 3 | Yes (`backend/tests/test_relationships.py:test_list_patients`) | [ ] |

---

## 3. Patient Settings & Safe Zones

| ID | Test Scenario | Steps | Expected Result | Owner | Automated? | Status |
|---|---|---|---|---|---|---|
| SET-01 | Get Default Settings | Call `GET /api/v1/patients/{patient_id}/settings` | Returns `200 OK` with defaults: `tracking_enabled=true`, `interval=60s`, `safe_zone_enabled=false` | Member 3 | Yes (`backend/tests/test_settings.py:test_get_default_settings`) | [ ] |
| SET-02 | Partial Update Merge | Call `PUT .../settings` submitting only `location_interval_seconds: 120` | Returns `200 OK`; only interval changes, tracking and geofence flags preserved | Member 3 | Yes (`backend/tests/test_settings.py:test_partial_update`) | [ ] |
| SET-03 | Safe Zone Radius Bounds | Submit `safe_zone_radius_meters: 30` (min is 50) and `15000` (max is 10000) | Returns `422 Validation Error` rejecting out-of-bound values | Member 3 | Yes (`backend/tests/test_settings.py:test_radius_limits`) | [ ] |
| SET-04 | Location Interval Bounds | Submit `location_interval_seconds: 5` (min 15) or `7200` (max 3600) | Returns `422 Validation Error` rejecting out-of-bound values | Member 3 | Yes (`backend/tests/test_settings.py:test_interval_limits`) | [ ] |
| SET-05 | Safe Zone Activation Validation | Submit `safe_zone_enabled: true` without latitude/longitude/radius | Returns `422 Validation Error` requiring coordinates when enabling safe zone | Member 3 | Yes (`backend/tests/test_settings.py:test_safe_zone_missing_coords`) | [ ] |

---

## 4. Location Tracking & Ingestion

| ID | Test Scenario | Steps | Expected Result | Owner | Automated? | Status |
|---|---|---|---|---|---|---|
| LOC-01 | Patient Posts GPS Location | Patient calls `POST /api/v1/patients/{patient_id}/locations` with lat/lon | Returns `201 Created` with persisted location record | Member 2 / 3 | Yes (`backend/tests/test_locations.py:test_post_location`) | [ ] |
| LOC-02 | Caregiver Location Post Blocked | Caregiver attempts `POST .../locations` | Returns `403 Forbidden` (`FORBIDDEN`); caregiver cannot write patient GPS | Member 3 | Yes (`backend/tests/test_locations.py:test_caregiver_cannot_post_location`) | [ ] |
| LOC-03 | Future Timestamp Rejection | Submit `recorded_at` > 5 minutes in future | Returns `422 Validation Error` rejecting unrealistic future timestamps | Member 3 | Yes (`backend/tests/test_locations.py:test_future_timestamp_rejected`) | [ ] |
| LOC-04 | Patient Status Reflection | Call `GET /api/v1/patients/{patient_id}/status` after posting location | Returns `200 OK` with `location_available: true`, latest location, and safe-zone evaluation | Member 3 | Yes (`backend/tests/test_locations.py:test_patient_status`) | [ ] |
| LOC-05 | Location History Query | Call `GET .../locations?page=1&page_size=10` | Returns `200 OK` paginated newest-first items and metadata | Member 3 | Yes (`backend/tests/test_locations.py:test_list_locations`) | [ ] |

---

## 5. Geofencing & Automatic Alerts

| ID | Test Scenario | Steps | Expected Result | Owner | Automated? | Status |
|---|---|---|---|---|---|---|
| GEO-01 | Safe Zone Exit Alert Creation | Safe zone configured. Patient posts coordinates outside configured radius | Alert `geofence_exit` created in `open` state with `notification_status` recorded | Member 2 / 3 | Yes (`backend/tests/test_geofencing.py:test_exit_alert`) | [ ] |
| GEO-02 | Duplicate Exit Deduplication | Patient posts consecutive locations outside safe zone | Exactly one `geofence_exit` alert remains open; duplicates are not created | Member 2 / 3 | Yes (`backend/tests/test_geofencing.py:test_dedup_exit_alert`) | [ ] |
| GEO-03 | Return to Safe Zone (Resolution) | Patient with open `geofence_exit` posts location inside safe zone | `geofence_exit` alert automatically marked `resolved`; new `geofence_enter` logged | Member 2 / 3 | Yes (`backend/tests/test_geofencing.py:test_enter_resolves_exit`) | [ ] |
| GEO-04 | Push Notification on Exit | On new `geofence_exit`, backend dispatches push to linked caregivers | Push payload sent with `type="geofence_exit"`, `alert_id`, `patient_id` (NO GPS coordinates) | Member 5 | Yes (`backend/tests/test_notifications.py` - Stage 1) | [ ] |
| GEO-05 | No Push on Enter | Patient returns inside safe zone | Enter alert recorded; NO push notification is sent to caregivers | Member 5 | Yes (`backend/tests/test_notifications.py` - Stage 1) | [ ] |

---

## 6. SOS Help Requests & Alert Lifecycle

| ID | Test Scenario | Steps | Expected Result | Owner | Automated? | Status |
|---|---|---|---|---|---|---|
| SOS-01 | Patient Dispatches SOS | Patient calls `POST /api/v1/patients/{patient_id}/help` | Alert saved to DB first; then FCM push attempted; returns `201 Created` with alert and notification status | Member 1 / 3 / 5 | Yes (`backend/tests/test_alerts.py:test_create_help_request`) | [ ] |
| SOS-02 | SOS Cooldown (409 Duplicate) | Patient sends another help request within 60s cooldown | Returns `409 Conflict` (`DUPLICATE_HELP_REQUEST`); client UI recognizes it as already active | Member 1 / 3 / 5 | Yes (`backend/tests/test_alerts.py:test_help_request_cooldown`) | [ ] |
| SOS-03 | Caregiver Cannot Create SOS | Caregiver calls `POST .../help` | Returns `403 Forbidden` (`FORBIDDEN`); only patient can trigger SOS | Member 3 | Yes (`backend/tests/test_alerts.py:test_caregiver_cannot_trigger_help`) | [ ] |
| SOS-04 | Caregiver Acknowledges Alert | Caregiver calls `PATCH /api/v1/alerts/{alert_id}` with `status: "acknowledged"` | Returns `200 OK`; status transitions from `open` -> `acknowledged` | Member 4 | Yes (`backend/tests/test_alerts.py:test_acknowledge_alert`) | [ ] |
| SOS-05 | Caregiver Resolves Alert | Caregiver calls `PATCH /api/v1/alerts/{alert_id}` with `status: "resolved"` | Returns `200 OK`; status transitions to `resolved` with `resolved_at` timestamp | Member 4 | Yes (`backend/tests/test_alerts.py:test_resolve_alert`) | [ ] |
| SOS-06 | Forbidden State Reversal | Attempt transition from `acknowledged` -> `open` or `resolved` -> `open` | Returns `422 Validation Error`; backward status transitions rejected | Member 3 | Yes (`backend/tests/test_alerts.py:test_invalid_transition`) | [ ] |

---

## 7. Device Token Management & FCM Push Delivery

| ID | Test Scenario | Steps | Expected Result | Owner | Automated? | Status |
|---|---|---|---|---|---|---|
| FCM-01 | Register Device Token | Authenticated user calls `PUT /api/v1/devices/fcm-token` with `{token, platform: "android"}` | Returns `200 OK`; token saved and mapped to user | Member 5 | Yes (Backend unit test - Stage 1) | [ ] |
| FCM-02 | Idempotent Re-registration | Same user registers the same token again | Returns `200 OK`; updates `last_seen_at` without duplicate row error | Member 5 | Yes (Backend unit test - Stage 1) | [ ] |
| FCM-03 | Token Reassignment | User B registers token previously held by User A | Returns `200 OK`; token reassigned to User B | Member 5 | Yes (Backend unit test - Stage 1) | [ ] |
| FCM-04 | Unregister Own Token | User calls `DELETE /api/v1/devices/fcm-token` with `{token}` | Returns `204 No Content`; token deleted | Member 5 | Yes (Backend unit test - Stage 1) | [ ] |
| FCM-05 | Cannot Delete Other's Token | User A attempts to DELETE token owned by User B | Returns `404 Not Found`; User A cannot delete foreign token | Member 5 | Yes (Backend unit test - Stage 1) | [ ] |
| FCM-06 | Push Delivery: `sent` | All linked caregiver tokens deliver successfully via gateway | `notification.status = "sent"`, `delivered_count = N` | Member 5 | Yes (Stage 1 test suite) | [ ] |
| FCM-07 | Push Delivery: `partial` | Gateway reports partial delivery (1 success, 1 failure) | `notification.status = "partial"`, invalid token dropped | Member 5 | Yes (Stage 1 test suite) | [ ] |
| FCM-08 | Push Delivery: `no_devices` | Caregiver has no registered device tokens | `notification.status = "no_devices"`, `attempted = true` | Member 5 | Yes (Stage 1 test suite) | [ ] |
| FCM-09 | Push Delivery: `skipped` | Firebase not configured (`FIREBASE_CREDENTIALS_FILE` missing) | `notification.status = "skipped"`, alert saved normally | Member 5 | Yes (Stage 1 test suite) | [ ] |
| FCM-10 | Invalid Token Pruning | Gateway reports `registration-token-not-registered` | Stale token is automatically deleted from DB | Member 5 | Yes (Stage 1 test suite) | [ ] |
| FCM-11 | Privacy & Payload Check | Inspect push payload and log outputs | No GPS coordinates in payload; raw tokens never logged (`caplog`) | Member 5 | Yes (Stage 1 test suite) | [ ] |

---

## 8. Mobile Client Integration & Resiliency

| ID | Test Scenario | Steps | Expected Result | Owner | Automated? | Status |
|---|---|---|---|---|---|---|
| APP-01 | Graceful Missing Firebase | Launch both mobile apps without `google-services.json` | Apps launch smoothly; push service logs warning and disables itself without crashing | Member 5 | Yes (Flutter widget/unit test) | [ ] |
| APP-02 | Caregiver Foreground Push Banner | Caregiver app open in foreground receives push event | In-app notification banner appears with alert message and "Open" action | Member 5 | Yes (Flutter widget test) | [ ] |
| APP-03 | Caregiver Notification Tap | Tap push notification from system tray or background | Navigates to Safety View for that patient and refreshes alert list via API | Member 4 / 5 | Yes (Flutter widget test) | [ ] |
| APP-04 | Caregiver 10s Fallback Polling | Disable FCM. Trigger SOS or geofence exit | Caregiver safety screen automatically refreshes and displays alert within 10 seconds | Member 5 | Yes (Flutter test) | [ ] |
| APP-05 | Patient App Session Restore | Launch patient app after previous login | Automatically restores session and renders `SafeZoneHost`/Home without demo mode | Member 1 / 5 | Yes (Flutter test) | [ ] |
| APP-06 | Patient 409 Cooldown Display | Patient presses SOS while alert is already open | UI reflects "Alert already active / Waiting for caregiver" without showing error dialog | Member 1 / 5 | Yes (Flutter test) | [ ] |
| APP-07 | Android 13+ Notification Permission | Launch on Android 13+ device | Prompts user for `POST_NOTIFICATIONS` runtime permission | Member 5 | Manual device test | [ ] |
| APP-08 | GPS Off / Location Denied | Device GPS disabled or location permission denied | Patient app shows honest locating/permission banner; does not crash | Member 1 / 2 | Manual device test | [ ] |
| APP-09 | Backend Offline Recovery | Backend stopped while mobile apps are running | Network errors handled gracefully; retry on next timer/action | Members 1, 4, 5 | Manual device test | [ ] |

---

## 9. End-to-End Demo Script Checklist

| ID | Step Description | Action / Trigger | Verification Criteria | Status |
|---|---|---|---|---|
| DEMO-01 | Pre-flight Setup | Start DB & FastAPI backend, execute `seed_dev.py` | Health `/health` returns 200, seeded patient and caregiver ready | [ ] |
| DEMO-02 | Caregiver Login | Login with `caregiver.dev@example.com` | Dashboard loads linked patient Elaine | [ ] |
| DEMO-03 | Patient Login | Login with `patient.dev@example.com` | Safe zone banner shows "Safe Zone Active" | [ ] |
| DEMO-04 | Push Token Exchange | Both apps register FCM tokens on startup | Backend DB records tokens for caregiver | [ ] |
| DEMO-05 | Patient SOS Trigger | Patient taps CALL HELP button on phone | Large button confirms dispatch; backend creates alert | [ ] |
| DEMO-06 | Caregiver Push Arrival | Caregiver phone receives push notification | Notification banner appears: "Elaine requested help" | [ ] |
| DEMO-07 | Caregiver Acknowledge | Caregiver taps notification, clicks "Acknowledge" | Status changes to "Acknowledged" on both devices | [ ] |
| DEMO-08 | Caregiver Resolve | Caregiver taps "Resolve Alert" | Alert dismissed and moved to resolved history | [ ] |
| DEMO-09 | Safe Zone Exit Alert | Patient moves outside safe zone (or `demo_trigger.py --exit`) | Caregiver receives "Elaine left the safe zone" push; alert shows open | [ ] |
| DEMO-10 | Fallback Demonstration | Firebase disabled; trigger SOS | Caregiver app reflects alert within 10s via periodic polling | [ ] |
