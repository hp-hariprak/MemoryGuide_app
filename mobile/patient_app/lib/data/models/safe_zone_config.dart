import '../../core/utils/geo_utils.dart';

/// Configuration for a patient's safe zone and tracking policies.
///
/// Maps directly to the backend settings representation in
/// `GET /api/v1/patients/{patient_id}/settings`.
class SafeZoneConfig {
  final bool enabled;
  final double? latitude;
  final double? longitude;
  final int? radiusMeters;
  final String? name;
  final int locationIntervalSeconds;
  final bool trackingEnabled;
  final bool geofenceAlertsEnabled;

  const SafeZoneConfig({
    this.enabled = true,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.name,
    this.locationIntervalSeconds = 60,
    this.trackingEnabled = true,
    this.geofenceAlertsEnabled = true,
  });

  /// Factory constructing [SafeZoneConfig] from the unwrapped backend `data` object
  /// returned by `GET /api/v1/patients/{patient_id}/settings`.
  factory SafeZoneConfig.fromSettingsJson(Map<String, dynamic> data) {
    return SafeZoneConfig(
      enabled: data['safe_zone_enabled'] as bool? ?? false,
      latitude: (data['safe_zone_latitude'] as num?)?.toDouble(),
      longitude: (data['safe_zone_longitude'] as num?)?.toDouble(),
      radiusMeters: (data['safe_zone_radius_meters'] as num?)?.toInt(),
      name: data['name'] as String? ??
          data['safe_zone_name'] as String? ??
          data['zone_name'] as String? ??
          'Home Zone',
      locationIntervalSeconds:
          (data['location_interval_seconds'] as num?)?.toInt() ?? 60,
      trackingEnabled: data['tracking_enabled'] as bool? ?? true,
      geofenceAlertsEnabled:
          data['geofence_alerts_enabled'] as bool? ?? true,
    );
  }

  /// Whether the safe zone has all necessary fields set to perform
  /// reliable geofence evaluations (enabled, valid coordinates, and radius within 50m–10,000m).
  bool get isUsable {
    return enabled &&
        latitude != null &&
        longitude != null &&
        radiusMeters != null &&
        isValidLatitude(latitude!) &&
        isValidLongitude(longitude!) &&
        radiusMeters! >= 50 &&
        radiusMeters! <= 10000;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SafeZoneConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          radiusMeters == other.radiusMeters &&
          name == other.name &&
          locationIntervalSeconds == other.locationIntervalSeconds &&
          trackingEnabled == other.trackingEnabled &&
          geofenceAlertsEnabled == other.geofenceAlertsEnabled;

  @override
  int get hashCode => Object.hash(
        enabled,
        latitude,
        longitude,
        radiusMeters,
        name,
        locationIntervalSeconds,
        trackingEnabled,
        geofenceAlertsEnabled,
      );

  @override
  String toString() {
    return 'SafeZoneConfig(enabled: $enabled, lat: $latitude, lon: $longitude, '
        'radius: ${radiusMeters}m, name: $name, interval: ${locationIntervalSeconds}s)';
  }
}
