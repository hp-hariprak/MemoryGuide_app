import '../../core/errors/failures.dart';
import '../../core/network/api_client.dart';
import '../../core/services/service_locator.dart';
import '../datasources/auth_local_datasource.dart';
import '../models/patient_model.dart';

class AuthRepository {
  final ApiClient apiClient;
  final AuthLocalDataSource localDataSource;

  String? _cachedToken;
  UserModel? _currentUser;

  AuthRepository({
    required this.apiClient,
    required this.localDataSource,
  });

  String? get token => _cachedToken;
  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _cachedToken != null && _currentUser != null;

  Future<UserModel> login({
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

    final user = UserModel.fromJson(userData);
    if (user.role != 'patient') {
      throw const AuthFailure('This account is registered as a caregiver. Please use the Caregiver App.');
    }

    _cachedToken = token;
    _currentUser = user;
    await localDataSource.saveSession(token: token, user: user);
    try {
      PatientAppServices.instance.pushNotificationService.registerToken();
    } catch (_) {}
    return user;
  }

  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    final response = await apiClient.post('/auth/register', {
      'email': email.trim(),
      'password': password,
      'full_name': fullName.trim(),
      'role': 'patient',
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

    final user = UserModel.fromJson(userData);
    _cachedToken = token;
    _currentUser = user;
    await localDataSource.saveSession(token: token, user: user);
    try {
      PatientAppServices.instance.pushNotificationService.registerToken();
    } catch (_) {}
    return user;
  }

  Future<UserModel?> getMe() async {
    if (_cachedToken == null) return null;
    try {
      final response = await apiClient.get('/auth/me');
      if (response is Map<String, dynamic>) {
        final user = UserModel.fromJson(response);
        _currentUser = user;
        await localDataSource.saveSession(token: _cachedToken!, user: user);
        return user;
      }
    } catch (_) {
      // Return cached user if network fails
    }
    return _currentUser;
  }

  Future<UserModel?> restoreSession() async {
    final savedToken = await localDataSource.getToken();
    final savedUser = await localDataSource.getUser();

    if (savedToken != null && savedUser != null && savedUser.role == 'patient') {
      _cachedToken = savedToken;
      _currentUser = savedUser;
      try {
        PatientAppServices.instance.pushNotificationService.registerToken();
      } catch (_) {}
      // Refresh user profile in background
      try {
        final fresh = await apiClient.get('/auth/me');
        if (fresh is Map<String, dynamic>) {
          final refreshedUser = UserModel.fromJson(fresh);
          _currentUser = refreshedUser;
          await localDataSource.saveSession(token: savedToken, user: refreshedUser);
          return refreshedUser;
        }
      } catch (_) {
        // Use cached session if server is offline
      }
      return savedUser;
    }
    return null;
  }

  Future<void> logout() async {
    try {
      await PatientAppServices.instance.pushNotificationService.unregisterToken();
    } catch (_) {}
    _cachedToken = null;
    _currentUser = null;
    await localDataSource.clearSession();
  }
}
