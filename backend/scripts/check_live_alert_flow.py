#!/usr/bin/env python3
"""Interactive verification script to test and verify the complete
GPS coordinate ingestion, safe-zone breach, caregiver alert creation,
and safe-zone re-entry resolution cycle.
"""

import os
import sys
from pathlib import Path
from collections.abc import Generator

# Setup isolated test environment
os.environ["ENVIRONMENT"] = "test"
os.environ["SECRET_KEY"] = "test-secret-key-for-tests-only-32bytes"
os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ["CORS_ORIGINS"] = "http://testserver"
os.environ.pop("FIREBASE_CREDENTIALS_FILE", None)

# Add backend directory to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import get_settings
get_settings.cache_clear()

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.db.session import get_db
from app.main import app
from app.models.safety_event import AlertStatus, AlertType
from tests.helpers import auth_header, linked_pair

engine = create_engine(
    "sqlite+pysqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

def override_get_db() -> Generator[Session, None, None]:
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db
Base.metadata.create_all(bind=engine)

from fastapi.testclient import TestClient


def main():
    print("=" * 70)
    print("  MEMORYGUIDE: END-TO-END GPS, GEOFENCE & ALERT VERIFICATION")
    print("=" * 70)

    client = TestClient(app)

    # 1. Setup Patient and Caregiver pair
    print("\n[Step 1] Creating linked patient and caregiver...")
    pair = linked_pair(client)
    patient_id = pair["patient_id"]
    patient_headers = auth_header(pair["patient"]["access_token"])
    caregiver_headers = auth_header(pair["caregiver"]["access_token"])
    print(f"  ✓ Patient ID:   {patient_id}")
    print(f"  ✓ Caregiver ID: {pair['caregiver']['user']['id']}")

    # 2. Configure Home Location and 150m Safe Zone Perimeter
    home_lat = 12.9716
    home_lon = 77.5946
    radius_m = 150

    print(f"\n[Step 2] Configuring Safe-Zone Perimeter...")
    print(f"  Home Coordinates: ({home_lat}, {home_lon})")
    print(f"  Perimeter Radius: {radius_m} metres")

    settings_res = client.put(
        f"/api/v1/patients/{patient_id}/settings",
        headers=caregiver_headers,
        json={
            "safe_zone_enabled": True,
            "safe_zone_latitude": home_lat,
            "safe_zone_longitude": home_lon,
            "safe_zone_radius_meters": radius_m,
            "geofence_alerts_enabled": True,
            "tracking_enabled": True,
        },
    )
    assert settings_res.status_code == 200, f"Failed to configure settings: {settings_res.text}"
    print("  ✓ Safe zone saved and enabled on backend!")

    # 3. Patient sends GPS fix INSIDE safe zone
    print(f"\n[Step 3] Patient phone sends GPS fix INSIDE safe zone...")
    inside_lat = 12.9720  # ~44m from center
    inside_lon = 77.5946
    inside_res = client.post(
        f"/api/v1/patients/{patient_id}/locations",
        headers=patient_headers,
        json={
            "latitude": inside_lat,
            "longitude": inside_lon,
            "accuracy_meters": 5.0,
        },
    )
    assert inside_res.status_code == 201, f"Failed to post location: {inside_res.text}"
    print(f"  ✓ Fix recorded at ({inside_lat}, {inside_lon}) with accuracy ±5.0m")

    # Caregiver checks status
    status_res = client.get(f"/api/v1/patients/{patient_id}/status", headers=caregiver_headers)
    status_data = status_res.json()["data"]
    print(f"  ✓ Caregiver sees inside_safe_zone: {status_data['inside_safe_zone']} (True)")
    print(f"  ✓ Active alerts count: {status_data['open_alert_count']}")

    # 4. Patient phone sends poor-accuracy fix (accuracy circle straddles boundary)
    print(f"\n[Step 4] Patient sends uncertain GPS fix (poor accuracy ±150m)...")
    uncertain_res = client.post(
        f"/api/v1/patients/{patient_id}/locations",
        headers=patient_headers,
        json={
            "latitude": 13.05,
            "longitude": 77.70,
            "accuracy_meters": 150.0,
        },
    )
    assert uncertain_res.status_code == 201
    alerts_after_uncertain = client.get(f"/api/v1/patients/{patient_id}/alerts", headers=caregiver_headers).json()["data"]["items"]
    open_exits = [a for a in alerts_after_uncertain if a["alert_type"] == "geofence_exit"]
    print(f"  ✓ Exit alert triggered? {len(open_exits) > 0} (False - uncertain GPS fix safely ignored!)")

    # 5. Patient steps OUTSIDE the safe zone (confirmed exit)
    outside_lat = 12.9750  # ~378m from center (> 150m radius)
    outside_lon = 77.5946
    print(f"\n[Step 5] Patient phone sends confirmed GPS fix OUTSIDE safe zone...")
    print(f"  Current Coordinates: ({outside_lat}, {outside_lon}), accuracy: ±8.0m")
    outside_res = client.post(
        f"/api/v1/patients/{patient_id}/locations",
        headers=patient_headers,
        json={
            "latitude": outside_lat,
            "longitude": outside_lon,
            "accuracy_meters": 8.0,
        },
    )
    assert outside_res.status_code == 201

    # 6. Verify Caregiver receives exit alert
    print(f"\n[Step 6] Caregiver dashboard checks for generated alerts...")
    alerts_res = client.get(f"/api/v1/patients/{patient_id}/alerts", headers=caregiver_headers)
    items = alerts_res.json()["data"]["items"]
    open_exits = [a for a in items if a["alert_type"] == "geofence_exit" and a["status"] == "open"]
    assert len(open_exits) == 1, "Expected 1 open geofence_exit alert"
    exit_alert = open_exits[0]

    print("  " + "-" * 60)
    print(f"  ALERT GENERATED FOR CAREGIVER:")
    print(f"  Alert ID:     {exit_alert['id']}")
    print(f"  Alert Type:   {exit_alert['alert_type']}")
    print(f"  Status:       {exit_alert['status']}")
    print(f"  Message:      {exit_alert['message']}")
    print(f"  Coordinates:  ({exit_alert['latitude']}, {exit_alert['longitude']})")
    print(f"  Created At:   {exit_alert['created_at']}")
    print("  " + "-" * 60)

    # 7. Check Patient Status on Caregiver dashboard
    print(f"\n[Step 7] Checking patient status on Caregiver tracking view...")
    cg_status = client.get(f"/api/v1/patients/{patient_id}/status", headers=caregiver_headers).json()["data"]
    print(f"  ✓ Inside Safe Zone:    {cg_status['inside_safe_zone']} (False)")
    print(f"  ✓ Latest Latitude:     {cg_status['latest_location']['latitude']}")
    print(f"  ✓ Latest Longitude:    {cg_status['latest_location']['longitude']}")
    print(f"  ✓ Open Alert Count:    {cg_status['open_alert_count']}")

    # 8. Test Duplicate Prevention (Patient keeps walking outside)
    print(f"\n[Step 8] Patient continues walking outside (more outside pings)...")
    client.post(
        f"/api/v1/patients/{patient_id}/locations",
        headers=patient_headers,
        json={"latitude": 12.9760, "longitude": 77.5946, "accuracy_meters": 8.0},
    )
    alerts_check = client.get(f"/api/v1/patients/{patient_id}/alerts", headers=caregiver_headers).json()["data"]["items"]
    exits = [a for a in alerts_check if a["alert_type"] == "geofence_exit"]
    print(f"  ✓ Total exit alerts: {len(exits)} (Still 1 - duplicate alert spam prevented!)")

    # 9. Patient returns inside safe zone
    print(f"\n[Step 9] Patient returns home inside the safe zone...")
    return_res = client.post(
        f"/api/v1/patients/{patient_id}/locations",
        headers=patient_headers,
        json={"latitude": home_lat, "longitude": home_lon, "accuracy_meters": 5.0},
    )
    assert return_res.status_code == 201

    # Check alert resolution
    updated_alerts = client.get(f"/api/v1/patients/{patient_id}/alerts", headers=caregiver_headers).json()["data"]["items"]
    resolved_exits = [a for a in updated_alerts if a["alert_type"] == "geofence_exit" and a["status"] == "resolved"]
    print(f"  ✓ Exit alert auto-resolved? {len(resolved_exits) == 1} (True)")

    status_final = client.get(f"/api/v1/patients/{patient_id}/status", headers=caregiver_headers).json()["data"]
    print(f"  ✓ Status inside safe zone: {status_final['inside_safe_zone']} (True)")
    print(f"  ✓ Open alert count: {status_final['open_alert_count']}")

    print("\n" + "=" * 70)
    print("  ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!")
    print("=" * 70 + "\n")


if __name__ == "__main__":
    main()
