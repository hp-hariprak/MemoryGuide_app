import '../../core/config/app_config.dart';
import '../../core/errors/failures.dart';
import '../../core/network/api_client.dart';
import '../models/safe_zone_config.dart';

/// Contract for loading patient safe zone settings.
abstract class SafeZoneConfigRepository {
  Future<SafeZoneConfig> load();
  Future<void> save(SafeZoneConfig config);
}

/// Default repository returning a realistic in-memory demo safe zone
/// matching the Member 1 UI specifications.
class MockSafeZoneConfigRepository implements SafeZoneConfigRepository {
  SafeZoneConfig config;

  MockSafeZoneConfigRepository({
    SafeZoneConfig? customConfig,
  }) : config = customConfig ??
            const SafeZoneConfig(
              enabled: true,
              latitude: 12.9716,
              longitude: 77.5946,
              radiusMeters: 150,
              name: 'Home (Maple Street)',
              locationIntervalSeconds: 30,
              trackingEnabled: true,
              geofenceAlertsEnabled: true,
            );

  @override
  Future<SafeZoneConfig> load() async => config;

  @override
  Future<void> save(SafeZoneConfig newConfig) async {
    config = newConfig;
  }
}

/// Remote repository fetching settings from `GET /api/v1/patients/{patient_id}/settings`.
class ApiSafeZoneConfigRepository implements SafeZoneConfigRepository {
  final ApiClient apiClient;
  final Future<String?> Function() tokenProvider;
  final String? Function()? patientIdProvider;
  final String? patientId;

  ApiSafeZoneConfigRepository({
    ApiClient? apiClient,
    required this.tokenProvider,
    this.patientIdProvider,
    this.patientId,
  })  : apiClient = apiClient ?? ApiClient();

  @override
  Future<SafeZoneConfig> load() async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw const AuthFailure(
        'Authentication token required to fetch safe zone configuration',
        'AUTH_TOKEN_MISSING',
      );
    }

    final resolvedId = patientIdProvider?.call() ??
        patientId ??
        AppConfig.patientId;

    final headers = {'Authorization': 'Bearer $token'};
    final response = await apiClient.get(
      '/patients/$resolvedId/settings',
      headers: headers,
    );

    if (response is Map<String, dynamic>) {
      return SafeZoneConfig.fromSettingsJson(response);
    }

    throw const ServerFailure('Invalid response data received for patient settings');
  }

  @override
  Future<void> save(SafeZoneConfig newConfig) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) return;

    final resolvedId = patientIdProvider?.call() ??
        patientId ??
        AppConfig.patientId;

    final headers = {'Authorization': 'Bearer $token'};
    await apiClient.put(
      '/patients/$resolvedId/settings',
      {
        'safe_zone_enabled': newConfig.enabled,
        'safe_zone_latitude': newConfig.latitude,
        'safe_zone_longitude': newConfig.longitude,
        'safe_zone_radius_meters': newConfig.radiusMeters,
      },
      headers: headers,
    );
  }
}
