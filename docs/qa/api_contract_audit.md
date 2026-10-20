# API Contract Audit: Mobile Clients vs. Backend Contract

This audit inspects every endpoint documented in [api_contract.md](file:///f:/MemoryGuide_app/docs/api/api_contract.md) against actual mobile client implementations in `mobile/patient_app` and `mobile/caregiver_app`.

## Summary Table

| # | HTTP Method | Endpoint Path | Patient App Usage | Caregiver App Usage | Audit Status | Primary Concern / Discrepancy |
|---|---|---|---|---|---|---|
| 1 | `GET` | `/health` | Not Called | Not Called | **NOT USED** | Health/liveness probe primarily intended for load balancers/devops. |
| 2 | `GET` | `/ready` | Not Called | Not Called | **NOT USED** | Readiness probe with DB ping. Not called by mobile clients. |
| 3 | `POST` | `/api/v1/auth/register` | `AuthRepository.register` (sends: `email`, `password`, `full_name`, `role="patient"`, `phone`) | `CaregiverAuthRepository.register` (sends: `email`, `password`, `full_name`, `role="caregiver"`, `phone`) | **OK** | Both parse `{access_token, user}` envelope correctly. |
| 4 | `POST` | `/api/v1/auth/login` | `AuthRepository.login` (sends: `email`, `password`) | `CaregiverAuthRepository.login` (sends: `email`, `password`) | **OK** | Both parse `{access_token, user}` envelope correctly. |
| 5 | `GET` | `/api/v1/auth/me` | `AuthRepository.getMe` | `CaregiverAuthRepository.getMe` | **OK** | Bearer auth header sent; user profile parsed. Patient receives `link_code`. |
| 6 | `POST` | `/api/v1/caregivers/patients` | Not Called (Caregiver-only) | `CaregiverRepository.linkPatient` (sends: `link_code`) | **OK** | Sends uppercase trimmed code; parses `LinkedPatient`. |
| 7 | `GET` | `/api/v1/caregivers/patients` | Not Called (Caregiver-only) | `CaregiverRepository.listLinkedPatients` | **OK** | Retrieves active linked patients for caregiver. |
| 8 | `GET` | `/api/v1/patients/{patient_id}` | Not Called (Uses `/auth/me`) | `CaregiverRepository.getPatient` | **OK** | Retrieves linked patient details; parses `PatientSummary`. |
| 9 | `GET` | `/api/v1/patients/{patient_id}/settings` | `PatientRepository.fetchSettings`, `ApiSafeZoneConfigRepository.load` | `CaregiverRepository.getPatientSettings` | **OK** | Both models read optional `patient_id` which defaults to `""` since backend schema omits it. Safe. |
| 10 | `PUT` | `/api/v1/patients/{patient_id}/settings` | `PatientRepository.updateSettings` | `CaregiverRepository.updatePatientSettings` | **OK** | Partial merge contract honored. |
| 11 | `POST` | `/api/v1/patients/{patient_id}/locations` | `PatientRepository.recordLocation`, `ApiLocationUploader.upload` | Not Called (Patient-only) | **OK** | `latitude`, `longitude`, `accuracy_meters`, etc. sent. |
| 12 | `GET` | `/api/v1/patients/{patient_id}/status` | `PatientRepository.fetchStatus` | `CaregiverRepository.getPatientStatus` | **OK** | Parses `tracking_enabled`, `latest_location`, `inside_safe_zone`, `open_alert_count`. |
| 13 | `GET` | `/api/v1/patients/{patient_id}/locations` | Not Called | `CaregiverRepository.getPatientLocations` | **OK** | Query params `page`, `page_size`, `since`, `until` supported; parses `response['items']`. |
| 14 | `GET` | `/api/v1/patients/{patient_id}/alerts` | Not Called | `CaregiverRepository.getPatientAlerts` | **OK** | Query params `status`, `alert_type`, pagination supported; parses `AlertItem`. |
| 15 | `POST` | `/api/v1/patients/{patient_id}/help` | `PatientRepository.triggerHelp` | Not Called (Patient-only) | **OK** | Backend creates alert before push. Returns `HelpRequestResultModel`. (UI error handling note in F4). |
| 16 | `PATCH` | `/api/v1/alerts/{alert_id}` | Not Called | `CaregiverRepository.patchAlert` | **OK** | Transitions: `{"status": "acknowledged" \| "resolved"}`. |
| 17 | `GET` | `/api/v1/patients/{patient_id}/landmarks` | `PatientRepository.fetchLandmarks` | `CaregiverRepository.getLandmarks` | **MISMATCH** | Backend returns field `notes`; both apps attempt to parse `description`. Field is dropped in UI. |
| 18 | `POST` | `/api/v1/patients/{patient_id}/landmarks` | Not Called | `CaregiverRepository.createLandmark` | **MISMATCH** | Caregiver app sends `description`; backend expects `notes`. Silently ignored by backend. |
| 19 | `PUT` | `/api/v1/patients/{patient_id}/landmarks/{landmark_id}` | Not Called | Not Called | **NOT USED** | Backend provides partial update; neither mobile client implements landmark editing. |
| 20 | `DELETE` | `/api/v1/patients/{patient_id}/landmarks/{landmark_id}` | Not Called | `CaregiverRepository.deleteLandmark` | **OK** | Expects 204 No Content. |
| 21 | `PUT` | `/api/v1/devices/fcm-token` | Not Called | Not Called | **NOT USED** | Neither mobile client currently registers FCM tokens. To be implemented in Stage 2 (Member 5). |
| 22 | `DELETE` | `/api/v1/devices/fcm-token` | Not Called | Not Called | **NOT USED** | Neither mobile client currently deletes FCM tokens on logout. To be implemented in Stage 2 (Member 5). |

---

## Detailed Mismatches & Action Items

### 1. Landmark Notes vs. Description (Mismatches on #17 and #18)
- **Contract Specification**:
  - `LandmarkCreate` / `LandmarkData` use schema property `notes: str | None = None`.
- **Client Implementation**:
  - `mobile/caregiver_app/lib/data/repositories/caregiver_repository.dart` (`createLandmark`, line 138): sends `'description': description.trim()`.
  - `mobile/caregiver_app/lib/data/models/caregiver_models.dart` (`LandmarkItem.fromJson`, line 240): parses `description: json['description']?.toString()`.
  - `mobile/patient_app/lib/data/models/patient_model.dart` (`LandmarkModel.fromJson`, line 134): parses `description: json['description']?.toString()`.
- **Impact**:
  - When a caregiver adds landmark notes, the payload field `'description'` is ignored by Pydantic (extra fields permitted but not mapped to `notes`). The landmark is created with `notes = null`.
  - When landmarks are retrieved, `json['notes']` is present in the response envelope, but both Flutter models look for `json['description']`, resulting in `null`.
- **Owner**: Member 4 (Caregiver App Dashboard/Landmarks) and Member 1 (Patient App Models).

### 2. Device Token Registration & Cleanup (#21 and #22)
- **Contract Specification**:
  - `PUT /api/v1/devices/fcm-token`: `{token, device_id?, platform: "android"}`.
  - `DELETE /api/v1/devices/fcm-token`: `{token}`.
- **Client Implementation**:
  - Completely missing in both mobile apps.
- **Impact**:
  - No devices register tokens, so backend help requests and geofence alerts always yield `notification_status="no_devices"` (or `"skipped"`).
- **Owner**: Member 5 (Stage 2 implementation).

### 3. Patient ID in Settings Model (#9)
- **Contract Specification**:
  - `PatientSettingsData` contains tracking, geofence, and safe-zone configurations, but does not duplicate `patient_id` in the JSON response body.
- **Client Implementation**:
  - `mobile/caregiver_app/lib/data/models/caregiver_models.dart` line 157: `patientId: json['patient_id']?.toString() ?? ''`.
  - `mobile/patient_app/lib/data/models/patient_model.dart` line 68: `patientId: json['patient_id']?.toString() ?? ''`.
- **Impact**:
  - Harmless fallback to empty string `''`.
- **Owner**: Member 4 / Member 1.
