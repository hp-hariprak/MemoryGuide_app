import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:caregiver_app/core/network/api_client.dart';
import 'package:caregiver_app/core/services/push_notification_service.dart';

void main() {
  group('PushNotificationService Tests', () {
    test('init with failing messaging leaves isAvailable false without crashing', () async {
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

      final fakeMessaging = FakeMessagingGateway(mockToken: 'sample-token-xyz');
      final client = ApiClient(client: mockHttpClient);
      final service = PushNotificationService(messaging: fakeMessaging, apiClient: client);

      await service.init();
      expect(service.isAvailable, isTrue);

      await service.registerToken();
      expect(recordedPath, contains('/devices/fcm-token'));
      expect(recordedBody?['token'], equals('sample-token-xyz'));
      expect(recordedBody?['platform'], equals('android'));
    });

    test('token refresh automatically calls registerToken', () async {
      final registeredTokens = <String>[];
      final mockHttpClient = MockClient((request) async {
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          registeredTokens.add(body['token'].toString());
        }
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });

      final fakeMessaging = FakeMessagingGateway(mockToken: 'initial-token');
      final client = ApiClient(client: mockHttpClient);
      final service = PushNotificationService(messaging: fakeMessaging, apiClient: client);

      await service.init();
      expect(service.isAvailable, isTrue);

      fakeMessaging.emitTokenRefresh('new-refreshed-token-999');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(registeredTokens, contains('new-refreshed-token-999'));
    });

    test('unregisterToken calls DELETE /devices/fcm-token and clears current token', () async {
      String? deleteBody;
      final mockHttpClient = MockClient((request) async {
        if (request.method == 'DELETE') {
          deleteBody = request.body;
          return http.Response('', 204);
        }
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });

      final fakeMessaging = FakeMessagingGateway(mockToken: 'token-to-delete');
      final client = ApiClient(client: mockHttpClient);
      final service = PushNotificationService(messaging: fakeMessaging, apiClient: client);

      await service.init();
      await service.registerToken();
      expect(service.currentToken, equals('token-to-delete'));

      await service.unregisterToken();
      expect(deleteBody, contains('token-to-delete'));
      expect(service.currentToken, isNull);
    });

    test('events stream emits foreground and opened messages', () async {
      final fakeMessaging = FakeMessagingGateway();
      final client = ApiClient(client: MockClient((_) async => http.Response('{}', 200)));
      final service = PushNotificationService(messaging: fakeMessaging, apiClient: client);

      await service.init();

      final received = <PushEvent>[];
      final sub = service.events.listen(received.add);

      final event1 = PushEvent(
        type: 'help_request',
        alertId: 'alert-1',
        patientId: 'patient-1',
        source: PushSource.foreground,
      );
      fakeMessaging.emitForegroundMessage(event1);

      final event2 = PushEvent(
        type: 'geofence_exit',
        alertId: 'alert-2',
        patientId: 'patient-1',
        source: PushSource.opened,
      );
      fakeMessaging.emitOpenedMessage(event2);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received.length, equals(2));
      expect(received[0].type, equals('help_request'));
      expect(received[1].type, equals('geofence_exit'));

      await sub.cancel();
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
