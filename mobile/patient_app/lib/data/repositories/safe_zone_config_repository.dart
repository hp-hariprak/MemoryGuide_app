import '../../core/config/app_config.dart';
import '../../core/errors/failures.dart';
import '../../core/network/api_client.dart';
import '../models/safe_zone_config.dart';

/// Contract for loading patient safe zone settings.
abstract class SafeZoneConfigRepository {
  Future<SafeZoneConfig> load();
}

/// Default repository returning a realistic in-memory demo safe zone
/// matching the Member 1 UI specifications.
class MockSafeZoneConfigRepository implements SafeZoneConfigRepository {
  final SafeZoneConfig config;

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
}

/// Remote repository fetching settings from `GET /api/v1/patients/{patient_id}/settings`.
class ApiSafeZoneConfigRepository implements SafeZoneConfigRepository {
  final ApiClient apiClient;
  final Future<String?> Function() tokenProvider;
  final String patientId;

  ApiSafeZoneConfigRepository({
    ApiClient? apiClient,
    required this.tokenProvider,
    String? patientId,
  })  : apiClient = apiClient ?? ApiClient(),
        patientId = patientId ?? AppConfig.patientId;

  @override
  Future<SafeZoneConfig> load() async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw const AuthFailure(
        'Authentication token required to fetch safe zone configuration',
        'AUTH_TOKEN_MISSING',
      );
    }

    final headers = {'Authorization': 'Bearer $token'};
    final response = await apiClient.get(
      '/patients/$patientId/settings',
      headers: headers,
    );

    if (response is Map<String, dynamic>) {
      return SafeZoneConfig.fromSettingsJson(response);
    }

    throw const ServerFailure('Invalid response data received for patient settings');
  }
}
