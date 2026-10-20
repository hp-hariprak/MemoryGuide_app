"""End-to-end integration test exercising the full patient & caregiver flows.
Uses FastAPI TestClient backed by the real local PostgreSQL database.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient
from app.main import app

def test_full_e2e_flow():
    client = TestClient(app)

    print("\n--- 1. Testing Patient Login ---")
    patient_login = client.post(
        "/api/v1/auth/login",
        json={"email": "patient.dev@example.com", "password": "DevPass123!"},
    )
    assert patient_login.status_code == 200, f"Patient login failed: {patient_login.text}"
    patient_token = patient_login.json()["data"]["access_token"]
    patient_headers = {"Authorization": f"Bearer {patient_token}"}
    print("Patient login SUCCESS. Access token acquired.")

    print("\n--- 2. Testing Caregiver Login ---")
    cg_login = client.post(
        "/api/v1/auth/login",
        json={"email": "caregiver.dev@example.com", "password": "DevPass123!"},
    )
    assert cg_login.status_code == 200, f"Caregiver login failed: {cg_login.text}"
    cg_token = cg_login.json()["data"]["access_token"]
    cg_headers = {"Authorization": f"Bearer {cg_token}"}
    print("Caregiver login SUCCESS. Access token acquired.")

    print("\n--- 3. Testing Patient Auth/Me & Profile ---")
    me_res = client.get("/api/v1/auth/me", headers=patient_headers)
    assert me_res.status_code == 200, f"Get me failed: {me_res.text}"
    patient_data = me_res.json()["data"]
    patient_id = patient_data["id"]
    link_code = patient_data["link_code"]
    print(f"Patient ID: {patient_id}, Link Code: {link_code}")
    assert link_code == "DEVLINK1", f"Unexpected link code: {link_code}"

    print("\n--- 4. Testing Caregiver Patients List ---")
    patients_res = client.get("/api/v1/caregivers/patients", headers=cg_headers)
    assert patients_res.status_code == 200, f"List patients failed: {patients_res.text}"
    linked_list = patients_res.json()["data"]
    print(f"Caregiver has {len(linked_list)} linked patient(s).")
    assert any(p["patient_id"] == patient_id for p in linked_list), "Seeded link missing!"

    print("\n--- 5. Testing Patient Location Posting ---")
    loc_res = client.post(
        f"/api/v1/patients/{patient_id}/locations",
        headers=patient_headers,
        json={
            "latitude": 37.7749,
            "longitude": -122.4194,
            "accuracy_meters": 5.0,
            "speed": 0.0,
        },
    )
    assert loc_res.status_code == 201, f"Post location failed: {loc_res.text}"
    print("Patient location reported successfully.")

    print("\n--- 6. Testing Patient Status Query ---")
    status_res = client.get(f"/api/v1/patients/{patient_id}/status", headers=patient_headers)
    assert status_res.status_code == 200, f"Get status failed: {status_res.text}"
    status_data = status_res.json()["data"]
    print(f"Patient Status: tracking_enabled={status_data['tracking_enabled']}, "
          f"inside_safe_zone={status_data['inside_safe_zone']}, "
          f"location_available={status_data['location_available']}")
    assert status_data["location_available"] is True, "Location should be available after posting!"

    print("\n--- 7. Testing Patient SOS Emergency Dispatch ---")
    help_res = client.post(
        f"/api/v1/patients/{patient_id}/help",
        headers=patient_headers,
        json={"latitude": 37.7749, "longitude": -122.4194, "message": "Manual SOS test"},
    )
    if help_res.status_code == 201:
        help_data = help_res.json()["data"]
        alert_id = help_data["alert"]["id"]
        notif = help_data["notification"]
        print(f"SOS Alert Dispatched! Alert ID: {alert_id}, Notification status: {notif['status']}, delivered: {notif['delivered_count']}")
    elif help_res.status_code == 409:
        print("Existing active SOS alert found (deduped/throttled as expected).")
        alerts_check = client.get(f"/api/v1/patients/{patient_id}/alerts", headers=cg_headers)
        assert alerts_check.status_code == 200
        alert_id = alerts_check.json()["data"]["items"][0]["id"]
        print(f"Using active alert ID: {alert_id}")
    else:
        raise AssertionError(f"Unexpected help request response: {help_res.text}")

    print("\n--- 8. Testing Caregiver Alerts Retrieval ---")
    alerts_res = client.get(f"/api/v1/patients/{patient_id}/alerts", headers=cg_headers)
    assert alerts_res.status_code == 200, f"Get alerts failed: {alerts_res.text}"
    alerts_list = alerts_res.json()["data"]["items"]
    assert any(a["id"] == alert_id for a in alerts_list), "Dispatched alert not found in caregiver's alert list!"
    print(f"Caregiver successfully retrieved alert {alert_id}.")

    print("\n--- 9. Testing Caregiver Alert Acknowledgment ---")
    ack_res = client.patch(
        f"/api/v1/alerts/{alert_id}",
        headers=cg_headers,
        json={"status": "acknowledged"},
    )
    assert ack_res.status_code == 200, f"Ack alert failed: {ack_res.text}"
    assert ack_res.json()["data"]["status"] == "acknowledged"
    print("Alert status updated to ACKNOWLEDGED.")

    print("\n--- 10. Testing Caregiver Alert Resolution ---")
    res_res = client.patch(
        f"/api/v1/alerts/{alert_id}",
        headers=cg_headers,
        json={"status": "resolved"},
    )
    assert res_res.status_code == 200, f"Resolve alert failed: {res_res.text}"
    assert res_res.json()["data"]["status"] == "resolved"
    print("Alert status updated to RESOLVED.")

    print("\n--- 11. Testing Safe Zone Settings Config ---")
    settings_res = client.get(f"/api/v1/patients/{patient_id}/settings", headers=cg_headers)
    assert settings_res.status_code == 200, f"Get settings failed: {settings_res.text}"
    
    update_settings = client.put(
        f"/api/v1/patients/{patient_id}/settings",
        headers=cg_headers,
        json={
            "safe_zone_enabled": True,
            "safe_zone_radius_meters": 250,
            "safe_zone_latitude": 37.7750,
            "safe_zone_longitude": -122.4190,
            "tracking_enabled": True,
        },
    )
    assert update_settings.status_code == 200, f"Update settings failed: {update_settings.text}"
    updated_data = update_settings.json()["data"]
    assert updated_data["safe_zone_radius_meters"] == 250
    assert updated_data["safe_zone_enabled"] is True
    print("Safe zone settings successfully updated by caregiver.")

    print("\n--- 12. Testing Landmarks Retrieval ---")
    landmarks_res = client.get(f"/api/v1/patients/{patient_id}/landmarks", headers=cg_headers)
    assert landmarks_res.status_code == 200, f"Get landmarks failed: {landmarks_res.text}"
    print(f"Retrieved {len(landmarks_res.json()['data'])} landmarks.")

    print("\n--- 13. Testing Caregiver Device Token Registration ---")
    token_val = "e2e_caregiver_fcm_token_sample_12345"
    reg_res = client.put(
        "/api/v1/devices/fcm-token",
        headers=cg_headers,
        json={"token": token_val, "platform": "android", "device_id": "device_pixel_e2e"},
    )
    assert reg_res.status_code == 200, f"Register token failed: {reg_res.text}"
    reg_data = reg_res.json()["data"]
    assert "id" in reg_data
    print(f"Device token registered successfully. Record ID: {reg_data['id']}")

    print("\n--- 14. Testing Patient Geofence Breach & Exit Alert Trigger ---")
    # Patient reports location far outside the 250m safe zone (safe zone center is ~37.7750, -122.4190)
    outside_loc = client.post(
        f"/api/v1/patients/{patient_id}/locations",
        headers=patient_headers,
        json={
            "latitude": 37.8100,
            "longitude": -122.4100,
            "accuracy_meters": 5.0,
            "speed": 1.2,
        },
    )
    assert outside_loc.status_code == 201, f"Post breach location failed: {outside_loc.text}"
    print("Breach location reported outside safe zone.")

    # Verify patient status reflects outside safe zone
    breach_status = client.get(f"/api/v1/patients/{patient_id}/status", headers=patient_headers)
    assert breach_status.status_code == 200
    assert breach_status.json()["data"]["inside_safe_zone"] is False, "Expected inside_safe_zone=False"
    print("Patient status confirmed outside safe zone.")

    # Verify caregiver alerts list includes geofence exit alert
    cg_alerts_breach = client.get(f"/api/v1/patients/{patient_id}/alerts", headers=cg_headers)
    assert cg_alerts_breach.status_code == 200
    exit_alerts = [a for a in cg_alerts_breach.json()["data"]["items"] if a["type"] == "geofence_exit"]
    assert len(exit_alerts) > 0, "Expected at least one geofence_exit alert in caregiver alerts list!"
    print(f"Geofence exit alert detected in caregiver alert feed (Alert ID: {exit_alerts[0]['id']}).")

    print("\n--- 15. Testing Caregiver Device Token Unregistration ---")
    unreg_res = client.request(
        "DELETE",
        "/api/v1/devices/fcm-token",
        headers=cg_headers,
        json={"token": token_val},
    )
    assert unreg_res.status_code == 204, f"Unregister token failed: {unreg_res.text}"
    print("Device token successfully unregistered.")

    print("\n==============================================")
    print(" ALL 15 END-TO-END FLOW CHECKS PASSED 100%! ")
    print("==============================================\n")

if __name__ == "__main__":
    test_full_e2e_flow()

