"""Full end-to-end integration tests exercising the entire alert & push chain with a mocked Firebase gateway."""

from uuid import UUID
import pytest

from app.models.safety_event import AlertStatus, AlertType
from app.models.user import User
from app.schemas.location import LocationCreate
from app.services.location_service import LocationService
from app.services.notification_service import NotificationService
from tests.helpers import auth_header, linked_pair, register_user
from tests.test_notifications import MockGateway


def test_full_patient_help_alert_and_push_lifecycle(db, client):
    """End-to-end chain:
    1. Register patient and caregiver.
    2. Link with link code.
    3. Caregiver registers device FCM token.
    4. Patient triggers SOS help request.
    5. Mock gateway receives correct push token, title, body, and payload without coordinates.
    6. Caregiver lists alerts and sees the open help request.
    7. Caregiver acknowledges alert.
    8. Caregiver resolves alert.
    """
    pair = linked_pair(client)
    patient_id = pair["patient_id"]
    patient_uuid = UUID(patient_id)
    patient_token = pair["patient"]["access_token"]
    caregiver_token = pair["caregiver"]["access_token"]
    caregiver_user_id = pair["caregiver"]["user"]["id"]

    # 3. Caregiver registers FCM device token
    fcm_token = "cg-device-fcm-test-token-777"
    reg_res = client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": fcm_token, "platform": "android"},
    )
    assert reg_res.status_code == 200

    # Attach mock notification gateway
    mock_gw = MockGateway(mode="sent")
    notif_svc = NotificationService(db, gateway=mock_gw)

    db.expire_all()
    patient_user = db.query(User).filter_by(id=patient_uuid).first()

    # 4. Patient calls SOS help request using AlertService with wired notification service
    from app.services.alert_service import AlertService
    from app.schemas.alert import HelpRequestCreate

    alert_svc = AlertService(db, notifications=notif_svc)
    help_result = alert_svc.create_help(
        actor=patient_user,
        patient_id=patient_uuid,
        payload=HelpRequestCreate(message="Emergency: feeling dizzy", latitude=12.9716, longitude=77.5946),
    )

    assert help_result.alert.status == AlertStatus.OPEN
    assert help_result.alert.alert_type == AlertType.HELP_REQUEST
    assert help_result.notification.status == "sent"
    assert help_result.notification.delivered_count == 1

    # 5. Verify Gateway received push
    assert len(mock_gw.sent_messages) == 1
    sent_msg = mock_gw.sent_messages[0]
    assert sent_msg["tokens"] == [fcm_token]
    assert sent_msg["title"] == "MemoryGuide help request"
    assert "Pat Patient" in sent_msg["body"]
    assert sent_msg["data"]["type"] == "help_request"
    assert sent_msg["data"]["alert_id"] == str(help_result.alert.id)
    assert sent_msg["data"]["patient_id"] == str(patient_uuid)
    assert "latitude" not in sent_msg["data"]
    assert "longitude" not in sent_msg["data"]

    # 6. Caregiver lists alerts
    alerts_res = client.get(
        f"/api/v1/patients/{patient_id}/alerts",
        headers=auth_header(caregiver_token),
    )
    assert alerts_res.status_code == 200
    alert_items = alerts_res.json()["data"]["items"]
    matching = [a for a in alert_items if a["id"] == str(help_result.alert.id)]
    assert len(matching) == 1
    assert matching[0]["status"] == "open"

    # 7. Caregiver acknowledges alert
    ack_res = client.patch(
        f"/api/v1/alerts/{help_result.alert.id}",
        headers=auth_header(caregiver_token),
        json={"status": "acknowledged"},
    )
    assert ack_res.status_code == 200
    assert ack_res.json()["data"]["status"] == "acknowledged"

    # 8. Caregiver resolves alert
    resolve_res = client.patch(
        f"/api/v1/alerts/{help_result.alert.id}",
        headers=auth_header(caregiver_token),
        json={"status": "resolved"},
    )
    assert resolve_res.status_code == 200
    assert resolve_res.json()["data"]["status"] == "resolved"


def test_full_geofence_exit_and_enter_lifecycle(db, client):
    """End-to-end chain for geofence exit:
    1. Configure safe zone for patient.
    2. Caregiver registers FCM token.
    3. Patient reports location outside safe zone.
    4. Mock gateway receives geofence_exit push notification.
    5. Caregiver views open alert in alerts list.
    6. Patient reports location inside safe zone.
    7. Exit alert automatically transitions to resolved.
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
            "tracking_enabled": True,
        },
    )

    # 2. Caregiver registers FCM token
    fcm_token = "cg-geofence-push-token-888"
    client.put(
        "/api/v1/devices/fcm-token",
        headers=auth_header(caregiver_token),
        json={"token": fcm_token, "platform": "android"},
    )

    mock_gw = MockGateway(mode="sent")
    notif_svc = NotificationService(db, gateway=mock_gw)
    loc_svc = LocationService(db, notifications=notif_svc)

    db.expire_all()
    actor = db.query(User).filter_by(id=patient_uuid).first()

    # 3. Patient reports location outside safe zone (lat 13.05, lon 77.65 -> ~10 km away)
    loc_svc.record(actor, patient_uuid, LocationCreate(latitude=13.05, longitude=77.65))

    # 4. Verify mock gateway received geofence_exit push
    assert len(mock_gw.sent_messages) == 1
    exit_msg = mock_gw.sent_messages[0]
    assert exit_msg["tokens"] == [fcm_token]
    assert exit_msg["title"] == "MemoryGuide safe-zone alert"
    assert "left the safe zone" in exit_msg["body"]
    assert exit_msg["data"]["type"] == "geofence_exit"
    assert "latitude" not in exit_msg["data"]

    # 5. Caregiver views open alerts
    alerts_res = client.get(
        f"/api/v1/patients/{patient_id}/alerts",
        headers=auth_header(caregiver_token),
    )
    assert alerts_res.status_code == 200
    items = alerts_res.json()["data"]["items"]
    open_exits = [a for a in items if a["alert_type"] == "geofence_exit" and a["status"] == "open"]
    assert len(open_exits) == 1

    # 6. Patient reports location back inside safe zone (lat 12.9716, lon 77.5946)
    loc_svc.record(actor, patient_uuid, LocationCreate(latitude=12.9716, longitude=77.5946))

    # 7. Check that exit alert is now resolved and no new push sent for enter
    assert len(mock_gw.sent_messages) == 1, "Enter alert must not send a push"
    updated_alerts = client.get(
        f"/api/v1/patients/{patient_id}/alerts",
        headers=auth_header(caregiver_token),
    ).json()["data"]["items"]
    assert any(a["alert_type"] == "geofence_exit" and a["status"] == "resolved" for a in updated_alerts)
    assert any(a["alert_type"] == "geofence_enter" and a["status"] == "open" for a in updated_alerts)
