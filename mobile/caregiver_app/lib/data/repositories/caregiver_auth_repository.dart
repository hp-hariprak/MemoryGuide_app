import '../../core/errors/failures.dart';
import '../../core/network/api_client.dart';
import '../../core/services/caregiver_service_locator.dart';
import '../datasources/caregiver_local_datasource.dart';
import '../models/caregiver_models.dart';

class CaregiverAuthRepository {
  final ApiClient apiClient;
  final CaregiverLocalDataSource localDataSource;

  String? _cachedToken;
  CaregiverUser? _currentUser;

  CaregiverAuthRepository({
    required this.apiClient,
    required this.localDataSource,
  });

  String? get token => _cachedToken;
  CaregiverUser? get currentUser => _currentUser;
  bool get isAuthenticated => _cachedToken != null && _currentUser != null;

  Future<CaregiverUser> login({
    required String email,
    required String password,
  }) async {
    final response = await apiClient.post('/auth/login', {
      'email': email.trim(),
      'password': password,
    });

    if (response is! Map<String, dynamic>) {
      throw const AuthFailure('Invalid response from server');
    }

    final token = response['access_token']?.toString();
    final userData = response['user'] as Map<String, dynamic>?;

    if (token == null || userData == null) {
      throw const AuthFailure('Missing token or user profile in server response');
    }

    final user = CaregiverUser.fromJson(userData);
    if (user.role != 'caregiver') {
      throw const AuthFailure('This account is registered as a patient. Please use the Patient App.');
    }

    _cachedToken = token;
    _currentUser = user;
    await localDataSource.saveSession(token: token, user: user);
    try {
      CaregiverServiceLocator.instance.pushNotificationService.registerToken();
    } catch (_) {}
    return user;
  }

  Future<CaregiverUser> register({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    final response = await apiClient.post('/auth/register', {
      'email': email.trim(),
      'password': password,
      'full_name': fullName.trim(),
      'role': 'caregiver',
      'phone': phone?.trim().isNotEmpty == true ? phone!.trim() : null,
    });

    if (response is! Map<String, dynamic>) {
      throw const AuthFailure('Invalid response from server');
    }

    final token = response['access_token']?.toString();
    final userData = response['user'] as Map<String, dynamic>?;

    if (token == null || userData == null) {
      throw const AuthFailure('Missing token or user profile');
    }

    final user = CaregiverUser.fromJson(userData);
    _cachedToken = token;
    _currentUser = user;
    await localDataSource.saveSession(token: token, user: user);
    try {
      CaregiverServiceLocator.instance.pushNotificationService.registerToken();
    } catch (_) {}
    return user;
  }

  Future<CaregiverUser?> getMe() async {
    if (_cachedToken == null) return null;
    try {
      final response = await apiClient.get('/auth/me');
      if (response is Map<String, dynamic>) {
        final user = CaregiverUser.fromJson(response);
        _currentUser = user;
        await localDataSource.saveSession(token: _cachedToken!, user: user);
        return user;
      }
    } catch (_) {
      // Return cached user if offline
    }
    return _currentUser;
  }

  Future<CaregiverUser?> restoreSession() async {
    final savedToken = await localDataSource.getToken();
    final savedUser = await localDataSource.getUser();

    if (savedToken != null && savedUser != null && savedUser.role == 'caregiver') {
      _cachedToken = savedToken;
      _currentUser = savedUser;
      try {
        CaregiverServiceLocator.instance.pushNotificationService.registerToken();
      } catch (_) {}
      try {
        final fresh = await apiClient.get('/auth/me');
        if (fresh is Map<String, dynamic>) {
          final refreshed = CaregiverUser.fromJson(fresh);
          _currentUser = refreshed;
          await localDataSource.saveSession(token: savedToken, user: refreshed);
          return refreshed;
        }
      } catch (_) {
        // Return cached session if server is momentarily unreachable
      }
      return savedUser;
    }
    return null;
  }

  Future<void> logout() async {
    try {
      await CaregiverServiceLocator.instance.pushNotificationService.unregisterToken();
    } catch (_) {}
    _cachedToken = null;
    _currentUser = null;
    await localDataSource.clearSession();
  }
}
