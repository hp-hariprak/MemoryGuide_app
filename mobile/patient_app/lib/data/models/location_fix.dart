import 'package:geolocator/geolocator.dart';

/// A normalized, validated snapshot of geographic position and device accuracy.
class LocationFix {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime timestamp;
  final double? altitudeMeters;
  final double? speedMps;
  final double? headingDegrees;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    required this.timestamp,
    this.altitudeMeters,
    this.speedMps,
    this.headingDegrees,
  });

  /// Validates whether the coordinates and metrics represent a physically possible fix.
  bool get isValid {
    if (latitude.isNaN || latitude.isInfinite || latitude < -90.0 || latitude > 90.0) {
      return false;
    }
    if (longitude.isNaN || longitude.isInfinite || longitude < -180.0 || longitude > 180.0) {
      return false;
    }
    if (accuracyMeters != null &&
        (accuracyMeters!.isNaN || accuracyMeters!.isInfinite || accuracyMeters! < 0.0)) {
      return false;
    }
    return true;
  }

  /// Determines whether this fix is older than the provided [threshold].
  bool isStale(Duration threshold, [DateTime? referenceTime]) {
    final now = (referenceTime ?? DateTime.now()).toUtc();
    return now.difference(timestamp.toUtc()).abs() > threshold;
  }

  /// Factory converting a geolocator [Position] into a sanitized [LocationFix].
  ///
  /// Negative, infinite, or NaN accuracies and metrics are sanitized to null.
  factory LocationFix.fromPosition(Position p) {
    double? sanitizeMetric(double? val, {bool allowNegative = true, double? max}) {
      if (val == null || val.isNaN || val.isInfinite) return null;
      if (!allowNegative && val < 0) return null;
      if (max != null && val > max) return null;
      return val;
    }

    return LocationFix(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMeters: sanitizeMetric(p.accuracy, allowNegative: false),
      timestamp: p.timestamp.toUtc(),
      altitudeMeters: sanitizeMetric(p.altitude),
      speedMps: sanitizeMetric(p.speed, allowNegative: false),
      headingDegrees: sanitizeMetric(p.heading, allowNegative: false, max: 360.0),
    );
  }

  /// Converts this fix into the exact payload expected by
  /// `POST /api/v1/patients/{patient_id}/locations`.
  Map<String, dynamic> toApiJson() {
    final utc = timestamp.toUtc();
    final iso = utc.toIso8601String();
    final recordedAt = iso.endsWith('Z') ? iso : '${iso}Z';

    final json = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'recorded_at': recordedAt,
    };

    if (accuracyMeters != null) {
      json['accuracy_meters'] = accuracyMeters;
    }
    if (altitudeMeters != null) {
      json['altitude_meters'] = altitudeMeters;
    }
    if (speedMps != null) {
      json['speed_mps'] = speedMps;
    }
    if (headingDegrees != null) {
      json['heading_degrees'] = headingDegrees;
    }

    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationFix &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          accuracyMeters == other.accuracyMeters &&
          timestamp == other.timestamp &&
          altitudeMeters == other.altitudeMeters &&
          speedMps == other.speedMps &&
          headingDegrees == other.headingDegrees;

  @override
  int get hashCode => Object.hash(
        latitude,
        longitude,
        accuracyMeters,
        timestamp,
        altitudeMeters,
        speedMps,
        headingDegrees,
      );

  @override
  String toString() {
    return 'LocationFix(lat: $latitude, lon: $longitude, acc: ${accuracyMeters}m, time: $timestamp)';
  }
}
