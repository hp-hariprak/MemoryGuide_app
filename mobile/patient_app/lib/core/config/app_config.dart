import 'package:flutter/foundation.dart';

class AppConfig {
  static const String appName = 'MemoryGuide';

  /// Resolves the API base URL based on compile-time environment or runtime platform.
  /// Web/Chrome -> http://127.0.0.1:8000/api/v1
  /// Android Emulator -> http://10.0.2.2:8000/api/v1
  /// Can be overridden at build/run time:
  ///   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (kIsWeb) {
      return 'http://127.0.0.1:8000/api/v1';
    }
    return 'http://10.0.2.2:8000/api/v1';
  }

  /// Default patient ID used for location reporting and settings retrieval.
  static String get patientId {
    const fromEnv = String.fromEnvironment('PATIENT_ID');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return '22222222-2222-2222-2222-222222222222';
  }
}
