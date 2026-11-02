from datetime import datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.safety_event import AlertStatus, AlertType, SafetyEvent


class AlertRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, alert_id: UUID) -> SafetyEvent | None:
        return self.db.get(SafetyEvent, alert_id)

    def add(self, event: SafetyEvent) -> SafetyEvent:
        self.db.add(event)
        return event

    def count_open(self, patient_id: UUID) -> int:
        stmt = select(func.count()).select_from(SafetyEvent).where(
            SafetyEvent.patient_id == patient_id,
            SafetyEvent.status != AlertStatus.RESOLVED,
        )
        return int(self.db.scalar(stmt) or 0)

    def latest_open_of_type(self, patient_id: UUID, alert_type: AlertType) -> SafetyEvent | None:
        stmt = (
            select(SafetyEvent)
            .where(
                SafetyEvent.patient_id == patient_id,
                SafetyEvent.alert_type == alert_type,
                SafetyEvent.status != AlertStatus.RESOLVED,
            )
            .order_by(SafetyEvent.created_at.desc())
            .limit(1)
        )
        return self.db.scalar(stmt)

    def latest_of_type(self, patient_id: UUID, alert_type: AlertType) -> SafetyEvent | None:
        stmt = (
            select(SafetyEvent)
            .where(
                SafetyEvent.patient_id == patient_id,
                SafetyEvent.alert_type == alert_type,
            )
            .order_by(SafetyEvent.created_at.desc())
            .limit(1)
        )
        return self.db.scalar(stmt)

    def recent_help_request(self, patient_id: UUID, since: datetime) -> SafetyEvent | None:
        stmt = (
            select(SafetyEvent)
            .where(
                SafetyEvent.patient_id == patient_id,
                SafetyEvent.alert_type == AlertType.HELP_REQUEST,
                SafetyEvent.created_at >= since,
            )
            .order_by(SafetyEvent.created_at.desc())
            .limit(1)
        )
        return self.db.scalar(stmt)

    def list_for_patient(
        self,
        patient_id: UUID,
        *,
        page: int,
        page_size: int,
        status: AlertStatus | None = None,
        alert_type: AlertType | None = None,
    ) -> tuple[list[SafetyEvent], int]:
        filters = [SafetyEvent.patient_id == patient_id]
        if status is not None:
            filters.append(SafetyEvent.status == status)
        if alert_type is not None:
            filters.append(SafetyEvent.alert_type == alert_type)
        total = self.db.scalar(select(func.count()).select_from(SafetyEvent).where(*filters)) or 0
        stmt = (
            select(SafetyEvent)
            .where(*filters)
            .order_by(SafetyEvent.created_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        return list(self.db.scalars(stmt)), int(total)
