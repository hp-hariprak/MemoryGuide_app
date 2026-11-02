"""Extended tests verifying precision geofence evaluation, GPS uncertainty handling,
and hysteresis / duplicate exit prevention rules.
"""

from uuid import UUID
import pytest

from app.models.patient_settings import PatientSettings
from app.models.safety_event import AlertStatus, AlertType
from app.models.user import User
from app.schemas.location import LocationCreate
from app.services.geofence_service import GeofenceDecision, GeofenceService
from app.services.location_service import LocationService
from app.utils.geo import haversine_meters, is_valid_latitude, is_valid_longitude
from tests.helpers import auth_header, linked_pair


def test_haversine_and_coordinate_validation():
    # 1. Coordinate boundary validation
    assert is_valid_latitude(0.0) is True
    assert is_valid_latitude(90.0) is True
    assert is_valid_latitude(-90.0) is True
    assert is_valid_latitude(90.01) is False
    assert is_valid_latitude(-90.01) is False

    assert is_valid_longitude(0.0) is True
    assert is_valid_longitude(180.0) is True
    assert is_valid_longitude(-180.0) is True
    assert is_valid_longitude(180.1) is False
    assert is_valid_longitude(-180.1) is False

    # 2. Known distance: (12.9716, 77.5946) to (12.9725, 77.5946) = ~100m
    dist = haversine_meters(12.9716, 77.5946, 12.9725, 77.5946)
    assert 99.0 <= dist <= 101.5

    # 3. Same point -> 0m
    assert haversine_meters(12.9716, 77.5946, 12.9716, 77.5946) == 0.0


def test_geofence_decision_matrix():
    settings = PatientSettings(
        safe_zone_enabled=True,
        safe_zone_latitude=12.9716,
        safe_zone_longitude=77.5946,
        safe_zone_radius_meters=150,
    )

    # A. Center point with 5m accuracy -> INSIDE
    res_center = GeofenceService.evaluate(settings, 12.9716, 77.5946, accuracy_meters=5.0)
    assert res_center.decision == GeofenceDecision.INSIDE
    assert res_center.is_inside is True

    # B. Distance 100m with 10m accuracy (100 + 10 = 110 <= 150) -> INSIDE
    res_inside = GeofenceService.evaluate(settings, 12.9725, 77.5946, accuracy_meters=10.0)
    assert res_inside.decision == GeofenceDecision.INSIDE

    # C. Straddling boundary: distance 140m with 20m accuracy (140 - 20 = 120 <= 150, 140 + 20 = 160 > 150) -> UNCERTAIN
    # lat 12.9716 + 0.00126 is ~140m
    res_straddle = GeofenceService.evaluate(settings, 12.9716 + 0.00126, 77.5946, accuracy_meters=20.0)
    assert res_straddle.decision == GeofenceDecision.UNCERTAIN
    assert res_straddle.is_inside is None

    # D. Large GPS uncertainty: accuracy 120m (> max 100m) -> UNCERTAIN
    res_poor_accuracy = GeofenceService.evaluate(settings, 12.9716, 77.5946, accuracy_meters=120.0)
    assert res_poor_accuracy.decision == GeofenceDecision.UNCERTAIN

    # E. Far outside: distance ~10 km with 15m accuracy -> OUTSIDE
    res_outside = GeofenceService.evaluate(settings, 13.05, 77.70, accuracy_meters=15.0)
    assert res_outside.decision == GeofenceDecision.OUTSIDE
    assert res_outside.is_inside is False

    # F. Disabled safe zone -> NO_ZONE
    disabled_settings = PatientSettings(safe_zone_enabled=False)
    res_disabled = GeofenceService.evaluate(disabled_settings, 12.9716, 77.5946)
    assert res_disabled.decision == GeofenceDecision.NO_ZONE

    # G. Out-of-bounds latitude -> INVALID_FIX
    res_invalid = GeofenceService.evaluate(settings, 999.0, 77.5946)
    assert res_invalid.decision == GeofenceDecision.INVALID_FIX


def test_hysteresis_and_duplicate_exit_prevention(db, client):
    """Verifies:
    1. Uncertain fix does NOT trigger exit alert.
    2. 1st outside fix triggers an exit alert.
    3. Subsequent outside fixes do NOT create duplicate exit alerts.
    4. Returning inside resolves the exit alert and enters safe zone.
    5. Exiting again generates a new exit alert.
    """
    pair = linked_pair(client)
    patient_id = pair["patient_id"]
    patient_uuid = UUID(patient_id)
    caregiver_token = pair["caregiver"]["access_token"]

    # 1. Configure safe zone (center 12.9716, 77.5946, radius 150m)
    client.put(
        f"/api/v1/patients/{patient_id}/settings",
        headers=auth_header(caregiver_token),
        json={
            "safe_zone_enabled": True,
            "safe_zone_latitude": 12.9716,
            "safe_zone_longitude": 77.5946,
            "safe_zone_radius_meters": 150,
            "geofence_alerts_enabled": True,
        },
    )

    loc_svc = LocationService(db)
    db.expire_all()
    patient_user = db.query(User).filter_by(id=patient_uuid).first()

    # Step A: Patient reports fix outside but with poor accuracy (150m) -> UNCERTAIN
    loc_svc.record(
        patient_user,
        patient_uuid,
        LocationCreate(latitude=13.05, longitude=77.70, accuracy_meters=150.0),
    )
    alerts = loc_svc.alerts.list_for_patient(patient_uuid, page=1, page_size=10)[0]
    assert len(alerts) == 0, "Uncertain GPS fix must not generate alerts"

    # Step B: Patient reports confirmed outside fix (accuracy 10m) -> EXIT alert created
    loc_svc.record(
        patient_user,
        patient_uuid,
        LocationCreate(latitude=13.05, longitude=77.70, accuracy_meters=10.0),
    )
    alerts = loc_svc.alerts.list_for_patient(patient_uuid, page=1, page_size=10)[0]
    exit_alerts = [a for a in alerts if a.alert_type == AlertType.GEOFENCE_EXIT]
    assert len(exit_alerts) == 1
    first_exit_id = exit_alerts[0].id

    # Step C: Patient continues walking outside (more pings) -> NO duplicate exit alerts
    loc_svc.record(
        patient_user,
        patient_uuid,
        LocationCreate(latitude=13.06, longitude=77.71, accuracy_meters=10.0),
    )
    loc_svc.record(
        patient_user,
        patient_uuid,
        LocationCreate(latitude=13.07, longitude=77.72, accuracy_meters=8.0),
    )
    alerts = loc_svc.alerts.list_for_patient(patient_uuid, page=1, page_size=10)[0]
    exit_alerts = [a for a in alerts if a.alert_type == AlertType.GEOFENCE_EXIT]
    assert len(exit_alerts) == 1, "Must NOT create duplicate exit alerts while continuously outside"

    # Step D: Caregiver acknowledges the alert, but patient is still outside
    exit_alerts[0].status = AlertStatus.ACKNOWLEDGED
    db.commit()

    # More outside pings while acknowledged -> still NO new exit alert
    loc_svc.record(
        patient_user,
        patient_uuid,
        LocationCreate(latitude=13.08, longitude=77.73, accuracy_meters=12.0),
    )
    alerts = loc_svc.alerts.list_for_patient(patient_uuid, page=1, page_size=10)[0]
    exit_alerts = [a for a in alerts if a.alert_type == AlertType.GEOFENCE_EXIT]
    assert len(exit_alerts) == 1, "Must not create duplicate alert when previous is acknowledged but no return"

    # Step E: Patient returns inside safe zone -> exit alert is resolved, enter recorded
    loc_svc.record(
        patient_user,
        patient_uuid,
        LocationCreate(latitude=12.9716, longitude=77.5946, accuracy_meters=5.0),
    )
    alerts = loc_svc.alerts.list_for_patient(patient_uuid, page=1, page_size=10)[0]
    resolved_exits = [a for a in alerts if a.alert_type == AlertType.GEOFENCE_EXIT and a.status == AlertStatus.RESOLVED]
    assert len(resolved_exits) == 1

    # Step F: Patient exits again -> a NEW exit alert is now created
    loc_svc.record(
        patient_user,
        patient_uuid,
        LocationCreate(latitude=13.05, longitude=77.70, accuracy_meters=10.0),
    )
    alerts = loc_svc.alerts.list_for_patient(patient_uuid, page=1, page_size=10)[0]
    new_open_exits = [a for a in alerts if a.alert_type == AlertType.GEOFENCE_EXIT and a.status == AlertStatus.OPEN]
    assert len(new_open_exits) == 1
    assert new_open_exits[0].id != first_exit_id, "New exit after confirmed return must create a fresh alert"
