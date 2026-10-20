# MemoryGuide: Firebase Cloud Messaging (FCM) Setup Guide

A complete, beginner-friendly, step-by-step manual setup guide for Member 5 to configure Firebase Cloud Messaging for both the Patient and Caregiver mobile apps and the FastAPI backend.

---

## 1. Create a Firebase Project

1. Open your browser and navigate to the [Firebase Console](https://console.firebase.google.com/).
2. Sign in with your Google account.
3. Click **Add project** (or **Create a project**).
4. Project Name: Enter `memoryguide-safety` (or a name of your choice).
5. Google Analytics: You can disable Google Analytics for this project (not needed for notifications) and click **Create project**.
6. Wait for the project creation to complete, then click **Continue**.

---

## 2. Register Both Android Apps in Firebase

A single Firebase project will host **two** Android apps (one for the patient, one for the caregiver).

### App A: Patient App
1. On the Project Overview page in the Firebase Console, click the **Android** icon (or go to **Project Settings** > **General** > **Add app** > **Android**).
2. **Android package name**: Enter exactly:
   ```text
   com.example.patient_app
   ```
3. **App nickname** (optional): `MemoryGuide Patient`
4. Click **Register app**.
5. **Download config file**: Click **Download google-services.json**.
6. Move the downloaded file into the patient app directory:
   ```text
   mobile/patient_app/android/app/google-services.json
   ```
7. Click **Next**, skip the SDK steps (already configured in Gradle), and finish the wizard.

### App B: Caregiver App
1. In the Firebase Console, go to **Project Settings** (gear icon) > **General** tab.
2. Scroll down to the **Your apps** section and click **Add app** > **Android**.
3. **Android package name**: Enter exactly:
   ```text
   com.example.caregiver_app
   ```
4. **App nickname** (optional): `MemoryGuide Caregiver`
5. Click **Register app**.
6. **Download config file**: Click **Download google-services.json**.
7. Move this second downloaded file into the caregiver app directory:
   ```text
   mobile/caregiver_app/android/app/google-services.json
   ```
8. Click **Next**, skip the SDK steps, and finish the wizard.

---

## 3. Generate Service Account Credentials for Backend

The FastAPI backend uses the Firebase Admin Python SDK to dispatch pushes to FCM.

1. In the Firebase Console, click the **Settings gear** icon (top left) and select **Project settings**.
2. Select the **Service accounts** tab.
3. Verify that **Firebase Admin SDK** is selected with language `Python`.
4. Click the blue button: **Generate new private key**, then confirm by clicking **Generate key**.
5. A JSON key file will download (e.g. `memoryguide-safety-firebase-adminsdk-xxxxx.json`).
6. **Security Rule**: Never commit this file to git! (It is already listed in `.gitignore`).
7. Save this file to a secure local folder on your computer, for example:
   ```text
   f:/MemoryGuide_app/backend/secrets/firebase-service-account.json
   ```
8. Copy your Firebase **Project ID** from the same Project Settings page (e.g. `memoryguide-safety-12345`).

---

## 4. Configure Backend Environment

1. Open `backend/.env` (or copy from `backend/.env.example` if `.env` does not exist yet).
2. Set the following environment variables:
   ```env
   FIREBASE_CREDENTIALS_FILE=F:/MemoryGuide_app/backend/secrets/firebase-service-account.json
   FIREBASE_PROJECT_ID=memoryguide-safety-12345
   ```
3. Start (or restart) the backend:
   ```powershell
   cd f:\MemoryGuide_app\backend
   uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
   ```
4. Inspect the startup terminal output. You should **not** see `"Firebase Admin SDK failed to initialize"`.

---

## 5. Emulators and Device Requirements

> [!IMPORTANT]
> **FCM Requires Google Play Services!**
> Standard Android emulator system images ("AOSP / Android Open Source Project" or "ARM without Google APIs") do **NOT** contain Google Play Services and cannot receive push notifications.
>
> **Requirements**:
> - Use an Android Virtual Device (AVD) image created with the **Google Play** target (indicated by the Google Play Store icon in Android Studio Device Manager), OR
> - Use a physical Android smartphone connected via USB debugging.

### Allow Notifications (Android 13+ / API 33+)
When running the apps on Android 13 or newer, a system dialog will appear asking:
`"Allow MemoryGuide to send you notifications?"`
You must tap **Allow**.

---

## 6. How to Read `notification.status`

When the patient presses **CALL HELP** (`POST /api/v1/patients/{patient_id}/help`), the API response contains:

```json
{
  "success": true,
  "data": {
    "alert": {
      "id": "e4b52fc2-...",
      "alert_type": "help_request",
      "status": "open"
    },
    "notification": {
      "attempted": true,
      "delivered_count": 1,
      "status": "sent",
      "firebase_configured": true
    }
  },
  "message": "Help request created"
}
```

### Possible Status Values
| Status | Meaning | What to Do |
|---|---|---|
| `sent` | Push successfully handed off to FCM for all registered caregiver devices. | Verified! Push will arrive momentarily. |
| `partial` | Some devices received push, but at least one token failed or was invalid. | Check token list; stale tokens are auto-pruned. |
| `no_devices` | Caregiver has never logged into an app on a device with FCM, or relationship is inactive. | Ensure caregiver app logs in first so it registers its FCM token. |
| `skipped` | `FIREBASE_CREDENTIALS_FILE` is not configured or empty. | Expected in local dev without Firebase. Push is skipped; alert is still saved. |
| `failed` | Firebase Admin SDK encountered a network error, credentials error, or FCM rejected the batch. | Check backend logs for FCM exceptions. |

---

## 7. Troubleshooting Matrix

| Problem | Root Cause | Solution |
|---|---|---|
| `notification.status == "skipped"` | Backend `.env` missing `FIREBASE_CREDENTIALS_FILE` or path is invalid. | Check file path in `backend/.env`. Use forward slashes or escaped backslashes. |
| `notification.status == "no_devices"` | Caregiver has not registered a token, or the link code was not connected. | 1. Caregiver logs in.<br>2. App calls `PUT /devices/fcm-token`.<br>3. Verify in DB `device_tokens` table. |
| App crashes on launch with missing google-services | Gradle plugin applied without JSON file. | Our build script conditionally applies `com.google.gms.google-services` only when `google-services.json` is physically present. Check file placement in `android/app/`. |
| Notification received only when app is backgrounded | Foreground messaging handler absent. | `PushNotificationService` listens to `FirebaseMessaging.onMessage` and displays an in-app banner/snackbar when open. |
| Emulator does not receive notifications | AVD lacks Google Play services. | Create a new AVD in Android Studio with target: **Google Play (API 34/35)**. |
| Backend returns 409 `DUPLICATE_HELP_REQUEST` | Help request cooldown active (default 60 seconds). | Wait 60 seconds or acknowledge/resolve the active alert in the caregiver app. |

---

## 8. Exact Commands to Run Both Apps

### Terminal 1: Backend
```powershell
cd f:\MemoryGuide_app\backend
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Terminal 2: Seed Dev Database
```powershell
cd f:\MemoryGuide_app\backend
uv run python scripts/seed_dev.py
```

### Terminal 3: Caregiver App (on Device/Emulator 1)
```powershell
cd f:\MemoryGuide_app\mobile\caregiver_app
flutter run -d <emulator-1-id> --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

### Terminal 4: Patient App (on Device/Emulator 2)
```powershell
cd f:\MemoryGuide_app\mobile\patient_app
flutter run -d <emulator-2-id> --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

*(Note: On physical Android devices connected via USB or Wi-Fi, replace `10.0.2.2` with your computer's LAN IP address, e.g. `http://192.168.1.50:8000/api/v1`).*
