import '../network/api_client.dart';
import '../../data/datasources/auth_local_datasource.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/patient_repository.dart';
import 'push_notification_service.dart';

class PatientAppServices {
  static final PatientAppServices instance = PatientAppServices._();
  PatientAppServices._();

  late final AuthLocalDataSource authLocalDataSource = AuthLocalDataSource();
  late final ApiClient apiClient = ApiClient(
    tokenProvider: () => authRepository.token,
  );
  late final AuthRepository authRepository = AuthRepository(
    apiClient: apiClient,
    localDataSource: authLocalDataSource,
  );
  late final PatientRepository patientRepository = PatientRepository(
    apiClient: apiClient,
    authRepository: authRepository,
  );
  late final PushNotificationService pushNotificationService = PushNotificationService(
    messaging: FirebaseMessagingGateway(),
    apiClient: apiClient,
  );
}
