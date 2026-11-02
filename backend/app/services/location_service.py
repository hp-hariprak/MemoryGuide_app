from datetime import datetime
from math import ceil
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.exceptions import ForbiddenError
from app.core.permissions import require_patient_access
from app.models.location import Location
from app.models.safety_event import AlertStatus, AlertType, SafetyEvent
from app.models.user import User, UserRole
from app.repositories.alert_repository import AlertRepository
from app.repositories.location_repository import LocationRepository
from app.repositories.settings_repository import SettingsRepository
from app.repositories.user_repository import UserRepository
from app.schemas.common import PaginatedData, PaginationMeta
from app.schemas.location import (
    LatestLocationData,
    LocationCreate,
    LocationData,
    PatientStatusData,
)
from app.services.geofence_service import GeofenceDecision, GeofenceService
from app.services.notification_service import NotificationService
from app.utils.time import ensure_utc, utcnow


class LocationService:
    def __init__(self, db: Session, notifications: NotificationService | None = None) -> None:
        self.db = db
        self.locations = LocationRepository(db)
        self.settings = SettingsRepository(db)
        self.alerts = AlertRepository(db)
        self.users = UserRepository(db)
        self.notifications = notifications or NotificationService(db)

    def record(self, actor: User, patient_id: UUID, payload: LocationCreate) -> LocationData:
        require_patient_access(self.db, actor, patient_id)
        if actor.role == UserRole.CAREGIVER or (actor.id != patient_id and actor.role != UserRole.ADMIN):
            raise ForbiddenError("Only the patient can submit location updates")
        recorded_at = ensure_utc(payload.recorded_at) if payload.recorded_at else utcnow()
        location = Location(
            patient_id=patient_id,
            latitude=payload.latitude,
            longitude=payload.longitude,
            accuracy_meters=payload.accuracy_meters,
            altitude_meters=payload.altitude_meters,
            speed_mps=payload.speed_mps,
            heading_degrees=payload.heading_degrees,
            recorded_at=recorded_at,
        )
        self.locations.add(location)
        created_exit_alert = self._maybe_geofence_alert(
            patient_id,
            payload.latitude,
            payload.longitude,
            payload.accuracy_meters,
        )
        self.db.commit()
        self.db.refresh(location)

        if created_exit_alert is not None:
            try:
                self.db.refresh(created_exit_alert)
                patient = self.users.get_by_id(patient_id)
                patient_name = patient.full_name if patient else "Patient"
                notify = self.notifications.notify_geofence_exit(created_exit_alert, patient_name)
                created_exit_alert.notification_status = notify.status
                self.db.commit()
            except Exception:
                # Notification failures must never prevent location ingestion from succeeding
                pass

        return LocationData.model_validate(location)

    def status(self, actor: User, patient_id: UUID) -> PatientStatusData:
        require_patient_access(self.db, actor, patient_id)
        settings = self.settings.get(patient_id)
        latest = self.locations.latest(patient_id)
        latest_data = None
        inside = None
        if latest is not None:
            latest_data = LatestLocationData(
                latitude=latest.latitude,
                longitude=latest.longitude,
                accuracy_meters=latest.accuracy_meters,
                recorded_at=latest.recorded_at,
            )
            inside = GeofenceService.inside_safe_zone(
                settings,
                latest.latitude,
                latest.longitude,
                latest.accuracy_meters,
            )
        return PatientStatusData(
            patient_id=patient_id,
            tracking_enabled=bool(settings.tracking_enabled) if settings else True,
            latest_location=latest_data,
            inside_safe_zone=inside,
            open_alert_count=self.alerts.count_open(patient_id),
            location_available=latest is not None,
        )

    def history(
        self,
        actor: User,
        patient_id: UUID,
        *,
        page: int,
        page_size: int,
        since: datetime | None = None,
        until: datetime | None = None,
    ) -> PaginatedData[LocationData]:
        require_patient_access(self.db, actor, patient_id)
        items, total = self.locations.list_for_patient(
            patient_id,
            page=page,
            page_size=page_size,
            since=since,
            until=until,
        )
        return PaginatedData(
            items=[LocationData.model_validate(item) for item in items],
            pagination=PaginationMeta(
                page=page,
                page_size=page_size,
                total=total,
                total_pages=ceil(total / page_size) if page_size else 0,
            ),
        )

    def _maybe_geofence_alert(
        self,
        patient_id: UUID,
        latitude: float,
        longitude: float,
        accuracy_meters: float | None = None,
    ) -> SafetyEvent | None:
        settings = self.settings.get(patient_id)
        if settings is None or not settings.geofence_alerts_enabled or not settings.safe_zone_enabled:
            return None

        evaluation = GeofenceService.evaluate(settings, latitude, longitude, accuracy_meters)
        if evaluation.decision == GeofenceDecision.UNCERTAIN:
            # Uncertain fixes must never trigger exit or enter transitions
            return None

        if evaluation.decision == GeofenceDecision.INSIDE:
            # Patient is confirmed inside.
            # Resolve any open exit alerts.
            open_exit = self.alerts.latest_open_of_type(patient_id, AlertType.GEOFENCE_EXIT)
            if open_exit is not None:
                open_exit.status = AlertStatus.RESOLVED
                open_exit.resolved_at = utcnow()

            # Record an open enter event if none is currently open
            open_enter = self.alerts.latest_open_of_type(patient_id, AlertType.GEOFENCE_ENTER)
            if open_enter is None:
                enter_event = SafetyEvent(
                    patient_id=patient_id,
                    alert_type=AlertType.GEOFENCE_ENTER,
                    status=AlertStatus.OPEN,
                    latitude=latitude,
                    longitude=longitude,
                    notification_status="skipped",
                    message="Patient returned to safe zone",
                    created_at=utcnow(),
                )
                self.alerts.add(enter_event)
            return None

        if evaluation.decision == GeofenceDecision.OUTSIDE:
            # 1. Do not create another exit alert if an open one already exists
            existing_open = self.alerts.latest_open_of_type(patient_id, AlertType.GEOFENCE_EXIT)
            if existing_open is not None:
                return None

            # 2. Prevent repeated alerts: check if patient has returned inside since last exit
            latest_exit = self.alerts.latest_of_type(patient_id, AlertType.GEOFENCE_EXIT)
            if latest_exit is not None:
                if latest_exit.status != AlertStatus.RESOLVED:
                    return None
                latest_enter = self.alerts.latest_of_type(patient_id, AlertType.GEOFENCE_ENTER)
                # If there has been no enter event after the last exit, do not generate a duplicate alert
                if latest_enter is None or latest_enter.created_at < latest_exit.created_at:
                    return None

            # Resolve any open enter event
            open_enter = self.alerts.latest_open_of_type(patient_id, AlertType.GEOFENCE_ENTER)
            if open_enter is not None:
                open_enter.status = AlertStatus.RESOLVED
                open_enter.resolved_at = utcnow()

            dist_str = f"{evaluation.distance_meters:.0f}m" if evaluation.distance_meters is not None else "unknown"
            radius_str = f"{settings.safe_zone_radius_meters}m"
            acc_str = f" (±{accuracy_meters:.0f}m)" if accuracy_meters is not None else ""
            event = SafetyEvent(
                patient_id=patient_id,
                alert_type=AlertType.GEOFENCE_EXIT,
                status=AlertStatus.OPEN,
                latitude=latitude,
                longitude=longitude,
                notification_status="pending",
                message=f"Warning: Patient has exited the configured safe zone ({dist_str} from center, radius {radius_str}{acc_str})",
                created_at=utcnow(),
            )
            self.alerts.add(event)
            return event

        return None
