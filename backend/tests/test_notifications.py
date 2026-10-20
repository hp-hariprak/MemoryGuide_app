import logging
from uuid import UUID, uuid4
import pytest

from app.models.safety_event import AlertStatus, AlertType, SafetyEvent
from app.models.user import User
from app.services.location_service import LocationService
from app.services.notification_service import (
    DisabledNotificationGateway,
    NotificationSendResult,
    NotificationService,
)
from app.schemas.location import LocationCreate
from tests.helpers import auth_header, linked_pair, register_user


class MockGateway:
    def __init__(self, mode: str = "sent", invalid_tokens: list[str] | None = None) -> None:
        self.mode = mode
        self.invalid_tokens = invalid_tokens or []
        self.sent_messages: list[dict] = []

    def send_to_tokens(self, tokens: list[str], title: str, body: str, data: dict[str, str]) -> tuple[int, list[str]]:
        self.sent_messages.append({
            "tokens": list(tokens),
            "title": title,
            "body": body,
            "data": dict(data),
        })
        if self.mode == "raise":
            raise RuntimeError("FCM gateway connection timeout")
        if self.mode == "sent":
            return len(tokens), self.invalid_tokens
        if self.mode == "partial":
            return max(1, len(tokens) - 1), self.invalid_tokens
        if self.mode == "failed":
            return 0, self.invalid_tokens
        return 0, []


def test_notification_status_skipped_when_disabled(db):
    """When Firebase is not configured, status is skipped and no push attempted."""
    svc = NotificationService(db, gateway=DisabledNotificationGateway())
    assert svc.firebase_configured is False
    event = SafetyEvent(
        patient_id=uuid4(),
        alert_type=AlertType.HELP_REQUEST,
        status=AlertStatus.OPEN,
        message="Need help",
        notification_status="pending",
    )
    result = svc.notify_help_request(event, "Patient Name")
    assert result.status == "skipped"
    assert result.attempted is False
    assert result.delivered_count == 0
    assert result.firebase_configured is False


def test_notification_status_no_devices(db, client):
    """When Firebase is configured but caregiver has no registered FCM tokens."""
    pair = linked_pair(client)
    patient_uuid = UUID(pair["patient_id"])
    gateway = MockGateway(mode="sent")
    svc = NotificationService(db, gateway=gateway)

    event = SafetyEvent(
        patient_id=patient_uuid,
        alert_type=AlertType.HELP_REQUEST,
        status=AlertStatus.OPEN,
        message="Help needed",
        notification_status="pending",
    )
    db.add(event)
    db.commit()

    result = svc.notify_help_request(event, "Pat Patient")
    assert result.status == "no_devices"
    assert result.attempted is True
    assert result.delivered_count == 0
    assert len(gateway.sent_messages) == 0


def test_notification_status_sent_and_payload_no_coordinates(db, client):
    """When push is delivered to all devices, status is sent and payload contains no coordinates."""
    pair = linked_pair(client)
    patient_uuid = UUID(pair["patient_id"])
    caregiver_token = pair["caregiver"]["access_token"]

    # Register caregiver device token
    reg = client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": "test-fcm-token-12345", "platform": "android"},
    )
    assert reg.status_code == 200

    gateway = MockGateway(mode="sent")
    svc = NotificationService(db, gateway=gateway)

    event = SafetyEvent(
        patient_id=patient_uuid,
        alert_type=AlertType.HELP_REQUEST,
        status=AlertStatus.OPEN,
        latitude=12.9716,
        longitude=77.5946,
        message="Emergency assistance",
        notification_status="pending",
    )
    db.add(event)
    db.commit()

    result = svc.notify_help_request(event, "Pat Patient")
    assert result.status == "sent"
    assert result.delivered_count == 1
    assert len(gateway.sent_messages) == 1

    msg = gateway.sent_messages[0]
    assert msg["title"] == "MemoryGuide help request"
    assert "Pat Patient" in msg["body"]
    assert msg["data"]["type"] == "help_request"
    assert msg["data"]["alert_id"] == str(event.id)
    assert msg["data"]["patient_id"] == str(patient_uuid)

    # Privacy constraint: No coordinates in the push data payload
    assert "latitude" not in msg["data"]
    assert "longitude" not in msg["data"]
    assert "12.9716" not in str(msg["data"])
    assert "77.5946" not in str(msg["data"])


def test_notification_status_partial_and_invalid_token_cleanup(db, client):
    """Partial delivery drops invalid tokens automatically from the repository."""
    pair = linked_pair(client)
    patient_uuid = UUID(pair["patient_id"])
    caregiver_token = pair["caregiver"]["access_token"]

    client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": "valid-token-1", "platform": "android"},
    )
    # Register second device for caregiver
    client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": "stale-invalid-token-2", "platform": "android"},
    )

    gateway = MockGateway(mode="partial", invalid_tokens=["stale-invalid-token-2"])
    svc = NotificationService(db, gateway=gateway)

    event = SafetyEvent(
        patient_id=patient_uuid,
        alert_type=AlertType.HELP_REQUEST,
        status=AlertStatus.OPEN,
        notification_status="pending",
    )
    db.add(event)
    db.commit()

    result = svc.notify_help_request(event, "Pat Patient")
    assert result.status == "partial"
    assert result.delivered_count == 1

    # Verify stale token was removed
    caregiver_uuid = UUID(pair["caregiver"]["user"]["id"])
    remaining = [d.token for d in svc.devices.list_for_users([caregiver_uuid])]
    assert "valid-token-1" in remaining
    assert "stale-invalid-token-2" not in remaining


def test_notification_status_failed_on_exception(db, client):
    """When gateway raises an unhandled error, status is failed and alert is not affected."""
    pair = linked_pair(client)
    patient_uuid = UUID(pair["patient_id"])
    caregiver_token = pair["caregiver"]["access_token"]

    client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": "some-token", "platform": "android"},
    )

    gateway = MockGateway(mode="raise")
    svc = NotificationService(db, gateway=gateway)

    event = SafetyEvent(
        patient_id=patient_uuid,
        alert_type=AlertType.HELP_REQUEST,
        status=AlertStatus.OPEN,
        notification_status="pending",
    )
    db.add(event)
    db.commit()

    result = svc.notify_help_request(event, "Pat Patient")
    assert result.status == "failed"
    assert result.delivered_count == 0


def test_geofence_exit_push_once_and_no_push_on_enter(db, client):
    """Geofence exit dispatches push once; duplicate exit does not re-push; entering safe zone does not push."""
    pair = linked_pair(client)
    patient_id = pair["patient_id"]
    patient_uuid = UUID(patient_id)
    caregiver_token = pair["caregiver"]["access_token"]

    # Configure safe zone: center (12.97, 77.59), radius 200m
    client.put(
        f"/api/v1/patients/{patient_id}/settings",
        headers=auth_header(caregiver_token),
        json={
            "safe_zone_enabled": True,
            "safe_zone_latitude": 12.97,
            "safe_zone_longitude": 77.59,
            "safe_zone_radius_meters": 200,
            "geofence_alerts_enabled": True,
            "tracking_enabled": True,
        },
    )

    # Caregiver registers token
    client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": "caregiver-fcm-token", "platform": "android"},
    )

    gateway = MockGateway(mode="sent")
    notif_svc = NotificationService(db, gateway=gateway)
    loc_svc = LocationService(db, notifications=notif_svc)

    db.expire_all()
    actor = db.query(User).filter_by(id=patient_uuid).first()

    # 1. Post location OUTSIDE safe zone (far away: lat 13.5, lon 78.0)
    fix_exit = LocationCreate(latitude=13.5, longitude=78.0)
    loc_svc.record(actor, patient_uuid, fix_exit)

    assert len(gateway.sent_messages) == 1
    exit_msg = gateway.sent_messages[0]
    assert exit_msg["title"] == "MemoryGuide safe-zone alert"
    assert "left the safe zone" in exit_msg["body"]
    assert exit_msg["data"]["type"] == "geofence_exit"
    assert "latitude" not in exit_msg["data"]

    # Verify alert notification_status was recorded as sent
    alerts = loc_svc.alerts.list_for_patient(patient_uuid, page=1, page_size=10)[0]
    exit_alert = next(a for a in alerts if a.alert_type == AlertType.GEOFENCE_EXIT)
    assert exit_alert.notification_status == "sent"

    # 2. Duplicate location outside safe zone: must NOT create duplicate alert and must NOT re-push
    fix_exit_again = LocationCreate(latitude=13.6, longitude=78.1)
    loc_svc.record(actor, patient_uuid, fix_exit_again)
    assert len(gateway.sent_messages) == 1, "Duplicate exit must not send another push"

    # 3. Post location INSIDE safe zone (lat 12.97, lon 77.59): resolves exit alert, creates enter alert, NO push
    fix_enter = LocationCreate(latitude=12.97, longitude=77.59)
    loc_svc.record(actor, patient_uuid, fix_enter)
    assert len(gateway.sent_messages) == 1, "Geofence enter must not send a push notification"


def test_push_failure_does_not_rollback_location_or_alert(db, client):
    """When notification fails or throws, the location and alert must remain committed in database."""
    pair = linked_pair(client)
    patient_id = pair["patient_id"]
    patient_uuid = UUID(patient_id)
    caregiver_token = pair["caregiver"]["access_token"]

    client.put(
        f"/api/v1/patients/{patient_id}/settings",
        headers=auth_header(caregiver_token),
        json={
            "safe_zone_enabled": True,
            "safe_zone_latitude": 12.97,
            "safe_zone_longitude": 77.59,
            "safe_zone_radius_meters": 200,
            "geofence_alerts_enabled": True,
        },
    )
    client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": "caregiver-fcm-token", "platform": "android"},
    )

    # Gateway throws error
    gateway = MockGateway(mode="raise")
    notif_svc = NotificationService(db, gateway=gateway)
    loc_svc = LocationService(db, notifications=notif_svc)
    actor = db.query(User).filter_by(id=patient_uuid).first()

    # Post location outside safe zone
    loc_data = loc_svc.record(actor, patient_uuid, LocationCreate(latitude=13.5, longitude=78.0))
    assert loc_data is not None
    assert loc_data.latitude == 13.5

    # Location and alert must still exist
    latest_loc = loc_svc.locations.latest(patient_uuid)
    assert latest_loc is not None
    assert latest_loc.latitude == 13.5

    alerts = loc_svc.alerts.list_for_patient(patient_uuid, page=1, page_size=10)[0]
    assert any(a.alert_type == AlertType.GEOFENCE_EXIT for a in alerts)


def test_privacy_tokens_never_logged_or_exposed(client, caplog):
    """Raw FCM tokens must never appear in API responses or log messages."""
    caplog.set_level(logging.DEBUG)
    pair = linked_pair(client)
    secret_token = "secret-fcm-token-never-leak-this-value-xyz-987"
    caregiver_token = pair["caregiver"]["access_token"]

    res = client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": secret_token, "platform": "android"},
    )
    assert res.status_code == 200
    res_text = res.text

    # Response body must not contain the raw token
    assert secret_token not in res_text
    assert "id" in res.json()["data"]

    # Logs must not contain the raw token
    for record in caplog.records:
        assert secret_token not in record.message
