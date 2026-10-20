import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../network/api_client.dart';

enum PushSource { foreground, opened, initial }

class PushEvent {
  final String type;
  final String alertId;
  final String patientId;
  final PushSource source;
  final String? title;
  final String? body;

  const PushEvent({
    required this.type,
    required this.alertId,
    required this.patientId,
    required this.source,
    this.title,
    this.body,
  });

  @override
  String toString() =>
      'PushEvent(type: $type, alertId: $alertId, patientId: $patientId, source: $source)';
}

abstract class MessagingGateway {
  Future<bool> init();
  Future<void> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Stream<PushEvent> get onMessage;
  Stream<PushEvent> get onMessageOpenedApp;
  Future<PushEvent?> getInitialMessage();
}

class FirebaseMessagingGateway implements MessagingGateway {
  bool _isInitialized = false;

  @override
  Future<bool> init() async {
    try {
      await Firebase.initializeApp();
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Firebase initialization skipped or failed: $e');
      _isInitialized = false;
      return false;
    }
  }

  @override
  Future<void> requestPermission() async {
    if (!_isInitialized) return;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('FCM requestPermission error: $e');
    }
  }

  @override
  Future<String?> getToken() async {
    if (!_isInitialized) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FCM getToken error: $e');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh {
    if (!_isInitialized) return const Stream.empty();
    return FirebaseMessaging.instance.onTokenRefresh;
  }

  @override
  Stream<PushEvent> get onMessage {
    if (!_isInitialized) return const Stream.empty();
    return FirebaseMessaging.onMessage.map((m) => _fromRemoteMessage(m, PushSource.foreground));
  }

  @override
  Stream<PushEvent> get onMessageOpenedApp {
    if (!_isInitialized) return const Stream.empty();
    return FirebaseMessaging.onMessageOpenedApp
        .map((m) => _fromRemoteMessage(m, PushSource.opened));
  }

  @override
  Future<PushEvent?> getInitialMessage() async {
    if (!_isInitialized) return null;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        return _fromRemoteMessage(initial, PushSource.initial);
      }
    } catch (e) {
      debugPrint('FCM getInitialMessage error: $e');
    }
    return null;
  }

  PushEvent _fromRemoteMessage(RemoteMessage message, PushSource source) {
    final data = message.data;
    return PushEvent(
      type: data['type']?.toString() ?? '',
      alertId: data['alert_id']?.toString() ?? '',
      patientId: data['patient_id']?.toString() ?? '',
      source: source,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }
}

class FakeMessagingGateway implements MessagingGateway {
  bool initialized = false;
  String? mockToken;
  final StreamController<String> _tokenRefreshController =
      StreamController<String>.broadcast();
  final StreamController<PushEvent> _messageController =
      StreamController<PushEvent>.broadcast();
  final StreamController<PushEvent> _openedController =
      StreamController<PushEvent>.broadcast();
  PushEvent? initialEvent;

  FakeMessagingGateway({this.mockToken = 'fake-token-123'});

  @override
  Future<bool> init() async {
    initialized = true;
    return true;
  }

  @override
  Future<void> requestPermission() async {}

  @override
  Future<String?> getToken() async => mockToken;

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Stream<PushEvent> get onMessage => _messageController.stream;

  @override
  Stream<PushEvent> get onMessageOpenedApp => _openedController.stream;

  @override
  Future<PushEvent?> getInitialMessage() async => initialEvent;

  void emitTokenRefresh(String token) => _tokenRefreshController.add(token);
  void emitForegroundMessage(PushEvent event) => _messageController.add(event);
  void emitOpenedMessage(PushEvent event) => _openedController.add(event);

  void dispose() {
    _tokenRefreshController.close();
    _messageController.close();
    _openedController.close();
  }
}

class PushNotificationService {
  final MessagingGateway messaging;
  final ApiClient apiClient;
  final String? deviceId;

  final StreamController<PushEvent> _eventController =
      StreamController<PushEvent>.broadcast();
  Stream<PushEvent> get events => _eventController.stream;

  bool isAvailable = false;
  String? _currentToken;
  StreamSubscription? _tokenSub;
  StreamSubscription? _msgSub;
  StreamSubscription? _openSub;

  PushNotificationService({
    required this.messaging,
    required this.apiClient,
    this.deviceId,
  });

  String? get currentToken => _currentToken;

  Future<void> init() async {
    isAvailable = await messaging.init();
    if (!isAvailable) {
      debugPrint('PushNotificationService: FCM not available. Graceful fallback active.');
      return;
    }

    await messaging.requestPermission();

    _msgSub = messaging.onMessage.listen((event) {
      _eventController.add(event);
    });

    _openSub = messaging.onMessageOpenedApp.listen((event) {
      _eventController.add(event);
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      _eventController.add(initial);
    }

    _tokenSub = messaging.onTokenRefresh.listen((newToken) {
      registerToken(newToken);
    });
  }

  Future<void> registerToken([String? tokenOverride]) async {
    String? token = tokenOverride;
    if (token == null && isAvailable) {
      token = await messaging.getToken();
    }
    if (token == null || token.isEmpty) return;
    _currentToken = token;

    try {
      await apiClient.put('/devices/fcm-token', {
        'token': token,
        if (deviceId != null) 'device_id': deviceId,
        'platform': 'android',
      });
      debugPrint('FCM device token registered with backend');
    } catch (e) {
      debugPrint('Failed to register FCM token with backend (swallowed): $e');
    }
  }

  Future<void> unregisterToken() async {
    final token = _currentToken;
    if (token == null || token.isEmpty) return;

    try {
      await apiClient.delete('/devices/fcm-token', {
        'token': token,
      });
      debugPrint('FCM device token unregistered from backend');
    } catch (e) {
      debugPrint('Failed to unregister FCM token from backend (swallowed): $e');
    } finally {
      _currentToken = null;
    }
  }

  void dispose() {
    _tokenSub?.cancel();
    _msgSub?.cancel();
    _openSub?.cancel();
    _eventController.close();
  }
}
