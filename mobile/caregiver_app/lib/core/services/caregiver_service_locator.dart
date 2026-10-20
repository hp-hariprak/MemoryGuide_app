import '../network/api_client.dart';
import '../../data/datasources/caregiver_local_datasource.dart';
import '../../data/repositories/caregiver_auth_repository.dart';
import '../../data/repositories/caregiver_repository.dart';
import 'push_notification_service.dart';

class CaregiverServiceLocator {
  static final CaregiverServiceLocator instance = CaregiverServiceLocator._();
  CaregiverServiceLocator._();

  late final CaregiverLocalDataSource localDataSource = CaregiverLocalDataSource();
  late final ApiClient apiClient = ApiClient(
    tokenProvider: () => authRepository.token,
  );
  late final CaregiverAuthRepository authRepository = CaregiverAuthRepository(
    apiClient: apiClient,
    localDataSource: localDataSource,
  );
  late final CaregiverRepository caregiverRepository = CaregiverRepository(apiClient);
  late final PushNotificationService pushNotificationService = PushNotificationService(
    messaging: FirebaseMessagingGateway(),
    apiClient: apiClient,
  );
}
