import 'package:flutter/foundation.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../features/safe_zones/geofence_evaluator.dart';
import '../models/location_fix.dart';

/// Contract for uploading verified location fixes to the backend server.
abstract class LocationUploader {
  Future<void> upload(LocationFix fix);
}

/// No-op uploader used in offline or mock modes.
class NoopLocationUploader implements LocationUploader {
  const NoopLocationUploader();

  @override
  Future<void> upload(LocationFix fix) async {
    // No operation in mock mode
  }
}

/// Dispatches location fixes to `POST /api/v1/patients/{patient_id}/locations`.
class ApiLocationUploader implements LocationUploader {
  final ApiClient apiClient;
  final Future<String?> Function() tokenProvider;
  final String patientId;
  final double maxAcceptableAccuracyMeters;

  ApiLocationUploader({
    ApiClient? apiClient,
    required this.tokenProvider,
    String? patientId,
    this.maxAcceptableAccuracyMeters = GeofenceEvaluator.defaultMaxAcceptableAccuracyMeters,
  })  : apiClient = apiClient ?? ApiClient(),
        patientId = patientId ?? AppConfig.patientId;

  @override
  Future<void> upload(LocationFix fix) async {
    // Discard inaccurate fixes before sending to server to avoid bogus alerts
    final accuracy = fix.accuracyMeters;
    if (accuracy != null && accuracy > maxAcceptableAccuracyMeters) {
      debugPrint('[ApiLocationUploader] Fix accuracy (${accuracy}m) exceeds max acceptable (${maxAcceptableAccuracyMeters}m). Skipping upload.');
      return;
    }

    try {
      final token = await tokenProvider();
      if (token == null || token.isEmpty) {
        debugPrint('[ApiLocationUploader] No token provided; skipping upload.');
        return;
      }

      final headers = {'Authorization': 'Bearer $token'};
      await apiClient.post(
        '/patients/$patientId/locations',
        fix.toApiJson(),
        headers: headers,
      );
    } catch (e) {
      // Network/server errors are logged and swallowed so UI state & tracking never crash
      debugPrint('[ApiLocationUploader] Failed to upload location: $e');
    }
  }
}
