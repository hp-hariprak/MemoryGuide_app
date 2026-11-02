from __future__ import annotations

import enum
from dataclasses import dataclass

from app.models.patient_settings import PatientSettings
from app.utils.geo import haversine_meters, is_valid_latitude, is_valid_longitude


class GeofenceDecision(str, enum.Enum):
    INSIDE = "inside"
    OUTSIDE = "outside"
    UNCERTAIN = "uncertain"
    NO_ZONE = "no_zone"
    INVALID_FIX = "invalid_fix"


@dataclass
class GeofenceEvaluation:
    decision: GeofenceDecision
    distance_meters: float | None = None
    margin_meters: float | None = None
    accuracy_meters: float | None = None
    is_inside: bool | None = None
    reason: str = ""


class GeofenceService:
    DEFAULT_MAX_ACCURACY_METERS = 100.0

    @classmethod
    def evaluate(
        cls,
        settings: PatientSettings | None,
        latitude: float,
        longitude: float,
        accuracy_meters: float | None = None,
        max_acceptable_accuracy_meters: float = DEFAULT_MAX_ACCURACY_METERS,
    ) -> GeofenceEvaluation:
        if (
            settings is None
            or not settings.safe_zone_enabled
            or settings.safe_zone_latitude is None
            or settings.safe_zone_longitude is None
            or settings.safe_zone_radius_meters is None
        ):
            return GeofenceEvaluation(
                decision=GeofenceDecision.NO_ZONE,
                reason="Safe zone is unconfigured or disabled",
            )

        if not is_valid_latitude(latitude) or not is_valid_longitude(longitude):
            return GeofenceEvaluation(
                decision=GeofenceDecision.INVALID_FIX,
                reason="Coordinates are out of physical bounds",
            )

        distance = haversine_meters(
            latitude,
            longitude,
            settings.safe_zone_latitude,
            settings.safe_zone_longitude,
        )
        radius = float(settings.safe_zone_radius_meters)
        margin = radius - distance
        acc = accuracy_meters if accuracy_meters is not None else 0.0

        if accuracy_meters is not None and accuracy_meters > max_acceptable_accuracy_meters:
            return GeofenceEvaluation(
                decision=GeofenceDecision.UNCERTAIN,
                distance_meters=distance,
                margin_meters=margin,
                accuracy_meters=accuracy_meters,
                reason=f"GPS accuracy ({accuracy_meters}m) exceeds max acceptable ({max_acceptable_accuracy_meters}m)",
            )

        if distance + acc <= radius:
            return GeofenceEvaluation(
                decision=GeofenceDecision.INSIDE,
                distance_meters=distance,
                margin_meters=margin,
                accuracy_meters=accuracy_meters,
                is_inside=True,
                reason="Confirmed inside safe zone boundary",
            )

        if distance - acc > radius:
            return GeofenceEvaluation(
                decision=GeofenceDecision.OUTSIDE,
                distance_meters=distance,
                margin_meters=margin,
                accuracy_meters=accuracy_meters,
                is_inside=False,
                reason="Confirmed outside safe zone boundary",
            )

        return GeofenceEvaluation(
            decision=GeofenceDecision.UNCERTAIN,
            distance_meters=distance,
            margin_meters=margin,
            accuracy_meters=accuracy_meters,
            reason="GPS accuracy circle overlaps the safe zone perimeter",
        )

    @classmethod
    def inside_safe_zone(
        cls,
        settings: PatientSettings | None,
        latitude: float,
        longitude: float,
        accuracy_meters: float | None = None,
    ) -> bool | None:
        res = cls.evaluate(settings, latitude, longitude, accuracy_meters)
        if res.decision == GeofenceDecision.INSIDE:
            return True
        if res.decision == GeofenceDecision.OUTSIDE:
            return False
        return None

