class CaregiverUser {
  final String id;
  final String email;
  final String role;
  final String fullName;
  final String? phone;
  final bool isActive;

  const CaregiverUser({
    required this.id,
    required this.email,
    required this.role,
    required this.fullName,
    this.phone,
    required this.isActive,
  });

  factory CaregiverUser.fromJson(Map<String, dynamic> json) {
    return CaregiverUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'caregiver',
      fullName: json['full_name']?.toString() ?? 'Caregiver',
      phone: json['phone']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'full_name': fullName,
        'phone': phone,
        'is_active': isActive,
      };
}

class PatientSummary {
  final String id;
  final String email;
  final String fullName;
  final String? phone;

  const PatientSummary({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone,
  });

  factory PatientSummary.fromJson(Map<String, dynamic> json) {
    return PatientSummary(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? 'Patient',
      phone: json['phone']?.toString(),
    );
  }
}

class LinkedPatient {
  final String id;
  final String caregiverId;
  final String patientId;
  final String status;
  final DateTime? createdAt;
  final PatientSummary patient;

  const LinkedPatient({
    required this.id,
    required this.caregiverId,
    required this.patientId,
    required this.status,
    this.createdAt,
    required this.patient,
  });

  factory LinkedPatient.fromJson(Map<String, dynamic> json) {
    return LinkedPatient(
      id: json['id']?.toString() ?? '',
      caregiverId: json['caregiver_id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      patient: PatientSummary.fromJson(json['patient'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class PatientStatus {
  final String patientId;
  final bool trackingEnabled;
  final Map<String, dynamic>? latestLocation;
  final bool? insideSafeZone;
  final int openAlertCount;
  final bool locationAvailable;

  const PatientStatus({
    required this.patientId,
    required this.trackingEnabled,
    this.latestLocation,
    this.insideSafeZone,
    required this.openAlertCount,
    required this.locationAvailable,
  });

  factory PatientStatus.fromJson(Map<String, dynamic> json) {
    return PatientStatus(
      patientId: json['patient_id']?.toString() ?? '',
      trackingEnabled: json['tracking_enabled'] as bool? ?? true,
      latestLocation: json['latest_location'] as Map<String, dynamic>?,
      insideSafeZone: json['inside_safe_zone'] as bool?,
      openAlertCount: (json['open_alert_count'] as num?)?.toInt() ?? 0,
      locationAvailable: json['location_available'] as bool? ?? false,
    );
  }

  double? get latitude =>
      (latestLocation?['latitude'] as num?)?.toDouble();

  double? get longitude =>
      (latestLocation?['longitude'] as num?)?.toDouble();

  double? get accuracyMeters =>
      (latestLocation?['accuracy_meters'] as num?)?.toDouble();

  DateTime? get recordedAt => latestLocation?['recorded_at'] != null
      ? DateTime.tryParse(latestLocation!['recorded_at'].toString())
      : null;
}

class PatientSettings {
  final String patientId;
  final bool trackingEnabled;
  final int locationIntervalSeconds;
  final bool geofenceAlertsEnabled;
  final bool safeZoneEnabled;
  final double? safeZoneLatitude;
  final double? safeZoneLongitude;
  final double safeZoneRadiusMeters;
  final int helpAlertCooldownSeconds;

  const PatientSettings({
    required this.patientId,
    required this.trackingEnabled,
    required this.locationIntervalSeconds,
    required this.geofenceAlertsEnabled,
    required this.safeZoneEnabled,
    this.safeZoneLatitude,
    this.safeZoneLongitude,
    required this.safeZoneRadiusMeters,
    required this.helpAlertCooldownSeconds,
  });

  factory PatientSettings.fromJson(Map<String, dynamic> json) {
    return PatientSettings(
      patientId: json['patient_id']?.toString() ?? '',
      trackingEnabled: json['tracking_enabled'] as bool? ?? true,
      locationIntervalSeconds:
          (json['location_interval_seconds'] as num?)?.toInt() ?? 60,
      geofenceAlertsEnabled:
          json['geofence_alerts_enabled'] as bool? ?? true,
      safeZoneEnabled: json['safe_zone_enabled'] as bool? ?? true,
      safeZoneLatitude: (json['safe_zone_latitude'] as num?)?.toDouble() ?? 11.03000,
      safeZoneLongitude: (json['safe_zone_longitude'] as num?)?.toDouble() ?? 77.00600,
      safeZoneRadiusMeters:
          (json['safe_zone_radius_meters'] as num?)?.toDouble() ?? 200.0,
      helpAlertCooldownSeconds:
          (json['help_alert_cooldown_seconds'] as num?)?.toInt() ?? 60,
    );
  }
}

class AlertItem {
  final String id;
  final String patientId;
  final String alertType; // 'geofence_exit', 'geofence_enter', 'help_request'
  final String status; // 'open', 'acknowledged', 'resolved'
  final String? message;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const AlertItem({
    required this.id,
    required this.patientId,
    required this.alertType,
    required this.status,
    this.message,
    this.latitude,
    this.longitude,
    required this.createdAt,
    this.resolvedAt,
  });

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      alertType: json['alert_type']?.toString() ?? 'help_request',
      status: json['status']?.toString() ?? 'open',
      message: json['message']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'].toString())
          : null,
    );
  }
}

class LandmarkItem {
  final String id;
  final String patientId;
  final String name;
  final double latitude;
  final double longitude;
  final String? description;

  const LandmarkItem({
    required this.id,
    required this.patientId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.description,
  });

  factory LandmarkItem.fromJson(Map<String, dynamic> json) {
    return LandmarkItem(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      description: json['description']?.toString(),
    );
  }
}
