import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:patient_app/core/errors/failures.dart';
import 'package:patient_app/core/network/api_client.dart';
import 'package:patient_app/core/services/push_notification_service.dart';

void main() {
  group('PatientApp PushNotificationService & SOS Error Handling Tests', () {
    test('init with failing messaging leaves isAvailable false gracefully', () async {
      final fakeMessaging = FailingMessagingGateway();
      final client = ApiClient(client: MockClient((_) async => http.Response('{}', 200)));
      final service = PushNotificationService(messaging: fakeMessaging, apiClient: client);

      await service.init();
      expect(service.isAvailable, isFalse);
    });

    test('registerToken dispatches PUT /devices/fcm-token', () async {
      String? recordedPath;
      Map<String, dynamic>? recordedBody;
      final mockHttpClient = MockClient((request) async {
        recordedPath = request.url.path;
        recordedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'success': true, 'data': {'registered': true}}), 200);
      });

      final fakeMessaging = FakeMessagingGateway(mockToken: 'patient-device-token');
      final client = ApiClient(client: mockHttpClient);
      final service = PushNotificationService(messaging: fakeMessaging, apiClient: client);

      await service.init();
      await service.registerToken();
      expect(recordedPath, contains('/devices/fcm-token'));
      expect(recordedBody?['token'], equals('patient-device-token'));
      expect(recordedBody?['platform'], equals('android'));
    });

    test('unregisterToken calls DELETE /devices/fcm-token on logout', () async {
      String? deleteBody;
      final mockHttpClient = MockClient((request) async {
        if (request.method == 'DELETE') {
          deleteBody = request.body;
          return http.Response('', 204);
        }
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });

      final fakeMessaging = FakeMessagingGateway(mockToken: 'patient-token-to-delete');
      final client = ApiClient(client: mockHttpClient);
      final service = PushNotificationService(messaging: fakeMessaging, apiClient: client);

      await service.init();
      await service.registerToken();
      expect(service.currentToken, equals('patient-token-to-delete'));

      await service.unregisterToken();
      expect(deleteBody, contains('patient-token-to-delete'));
      expect(service.currentToken, isNull);
    });

    test('DUPLICATE_HELP_REQUEST (409) is recognized as ApiException', () {
      final ex = ApiException(
        statusCode: 409,
        code: 'DUPLICATE_HELP_REQUEST',
        message: 'Open/recent help request still in cooldown',
      );
      expect(ex.code, equals('DUPLICATE_HELP_REQUEST'));
      expect(ex.statusCode, equals(409));
    });
  });
}

class FailingMessagingGateway implements MessagingGateway {
  @override
  Future<bool> init() async => false;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<PushEvent> get onMessage => const Stream.empty();

  @override
  Stream<PushEvent> get onMessageOpenedApp => const Stream.empty();

  @override
  Future<PushEvent?> getInitialMessage() async => null;
}
