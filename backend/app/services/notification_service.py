from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Protocol
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.safety_event import SafetyEvent
from app.repositories.device_repository import DeviceRepository
from app.repositories.relationship_repository import RelationshipRepository

logger = logging.getLogger(__name__)


@dataclass
class NotificationSendResult:
    attempted: bool
    delivered_count: int
    status: str
    firebase_configured: bool


class NotificationGateway(Protocol):
    def send_to_tokens(self, tokens: list[str], title: str, body: str, data: dict[str, str]) -> tuple[int, list[str]]:
        """Return (success_count, invalid_tokens)."""


class DisabledNotificationGateway:
    def send_to_tokens(self, tokens: list[str], title: str, body: str, data: dict[str, str]) -> tuple[int, list[str]]:
        return 0, []


class FirebaseNotificationGateway:
    def __init__(self) -> None:
        self._initialized = False
        self._error: str | None = None
        settings = get_settings()
        if not settings.firebase_enabled:
            self._error = "not_configured"
            return
        try:
            import firebase_admin
            from firebase_admin import credentials

            if not firebase_admin._apps:
                cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_FILE)
                options = {}
                if settings.FIREBASE_PROJECT_ID:
                    options["projectId"] = settings.FIREBASE_PROJECT_ID
                firebase_admin.initialize_app(cred, options or None)
            self._initialized = True
        except Exception:
            logger.exception("Firebase Admin SDK failed to initialize")
            self._error = "init_failed"

    @property
    def configured(self) -> bool:
        return self._initialized

    def send_to_tokens(self, tokens: list[str], title: str, body: str, data: dict[str, str]) -> tuple[int, list[str]]:
        if not self._initialized or not tokens:
            return 0, []
        from firebase_admin import messaging

        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data=data,
            tokens=tokens,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="memoryguide_alerts",
                    priority="high",
                    sound="default",
                ),
            ),
        )
        response = messaging.send_each_for_multicast(message)
        invalid: list[str] = []
        for idx, send_response in enumerate(response.responses):
            if send_response.success:
                continue
            error = send_response.exception
            code = getattr(getattr(error, "code", None), "value", None) or str(error)
            logger.warning("FCM delivery failed for a device token: %s", code)
            if "registration-token-not-registered" in str(error).lower() or "invalid-argument" in str(error).lower():
                invalid.append(tokens[idx])
        return response.success_count, invalid


class NotificationService:
    def __init__(self, db: Session, gateway: NotificationGateway | None = None) -> None:
        self.db = db
        self.devices = DeviceRepository(db)
        self.rels = RelationshipRepository(db)
        if gateway is not None:
            self.gateway = gateway
            self.firebase_configured = not isinstance(gateway, DisabledNotificationGateway)
        else:
            firebase_gateway = FirebaseNotificationGateway()
            self.gateway = firebase_gateway if firebase_gateway.configured else DisabledNotificationGateway()
            self.firebase_configured = firebase_gateway.configured

    def _notify_alert(
        self,
        alert: SafetyEvent,
        title: str,
        body: str,
        alert_type: str,
    ) -> NotificationSendResult:
        caregiver_ids = [rel.caregiver_id for rel in self.rels.list_active_caregivers(alert.patient_id)]
        tokens = [device.token for device in self.devices.list_for_users(caregiver_ids)]
        if not self.firebase_configured:
            return NotificationSendResult(
                attempted=False,
                delivered_count=0,
                status="skipped",
                firebase_configured=False,
            )
        if not tokens:
            return NotificationSendResult(
                attempted=True,
                delivered_count=0,
                status="no_devices",
                firebase_configured=True,
            )
        try:
            delivered, invalid = self.gateway.send_to_tokens(
                tokens,
                title=title,
                body=body,
                data={
                    "type": alert_type,
                    "alert_id": str(alert.id),
                    "patient_id": str(alert.patient_id),
                },
            )
            self._drop_invalid(invalid)
            status = "sent" if delivered == len(tokens) and delivered > 0 else "partial" if delivered else "failed"
            return NotificationSendResult(
                attempted=True,
                delivered_count=delivered,
                status=status,
                firebase_configured=True,
            )
        except Exception:
            logger.exception("Notification delivery failed after alert persistence")
            return NotificationSendResult(
                attempted=True,
                delivered_count=0,
                status="failed",
                firebase_configured=True,
            )

    def notify_help_request(self, alert: SafetyEvent, patient_name: str) -> NotificationSendResult:
        return self._notify_alert(
            alert=alert,
            title="MemoryGuide help request",
            body=f"{patient_name} requested help",
            alert_type="help_request",
        )

    def notify_geofence_exit(self, alert: SafetyEvent, patient_name: str) -> NotificationSendResult:
        return self._notify_alert(
            alert=alert,
            title="MemoryGuide safe-zone alert",
            body=f"{patient_name} left the safe zone",
            alert_type="geofence_exit",
        )

    def _drop_invalid(self, tokens: list[str]) -> None:
        for token in tokens:
            device = self.devices.get_by_token(token)
            if device is not None:
                self.devices.delete(device)
        if tokens:
            self.db.commit()
