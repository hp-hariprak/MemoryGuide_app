import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/core/errors/failures.dart';
import 'package:patient_app/data/datasources/location_datasource.dart';
import 'package:patient_app/data/models/location_fix.dart';
import 'package:patient_app/data/models/safe_zone_config.dart';
import 'package:patient_app/data/models/safe_zone_state.dart';
import 'package:patient_app/features/safe_zones/safe_zone_monitor.dart';

class FakeLocationSource implements LocationSource {
  final StreamController<LocationFix> controller =
      StreamController<LocationFix>.broadcast();
  int startCallCount = 0;
  int stopCallCount = 0;

  @override
  Stream<LocationFix> get fixes => controller.stream;

  @override
  Future<void> start() async {
    startCallCount++;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  void emitFix(LocationFix fix) {
    controller.add(fix);
  }

  void emitError(dynamic error) {
    controller.addError(error);
  }

  void dispose() {
    controller.close();
  }
}

void main() {
  group('SafeZoneMonitor', () {
    late FakeLocationSource fakeSource;
    late SafeZoneConfig testConfig;
    late DateTime currentTime;

    setUp(() {
      fakeSource = FakeLocationSource();
      currentTime = DateTime.utc(2026, 10, 16, 12, 0, 0);
      testConfig = const SafeZoneConfig(
        enabled: true,
        latitude: 12.9716,
        longitude: 77.5946,
        radiusMeters: 150,
        name: 'Home (Maple Street)',
        locationIntervalSeconds: 30,
        trackingEnabled: true,
        geofenceAlertsEnabled: true,
      );
    });

    tearDown(() {
      fakeSource.dispose();
    });

    test('starts at SafeZoneStatus.locating with null zoneName', () {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => currentTime,
      );

      expect(monitor.value.status, SafeZoneStatus.locating);
      expect(monitor.value.zoneName, isNull);
      expect(monitor.value.lastUpdated, isNull);
      monitor.dispose();
    });

    test('first inside fix transitions status immediately to inside', () async {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => currentTime,
      );

      await monitor.start();

      final insideFix = LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: currentTime,
      );

      fakeSource.emitFix(insideFix);
      await pumpEventQueue();

      expect(monitor.value.status, SafeZoneStatus.inside);
      expect(monitor.value.effectiveStatus, SafeZoneStatus.inside);
      expect(monitor.value.isSafe, isTrue);
      expect(monitor.value.zoneName, 'Home (Maple Street)');
      expect(monitor.value.lastUpdated, currentTime);

      monitor.dispose();
    });

    test(
        'single outside fix does not flip to outside; second consecutive outside fix does (outsideConfirmations = 2); following inside fix flips back immediately',
        () async {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => currentTime,
        outsideConfirmations: 2,
      );

      await monitor.start();

      // 1. Initial inside fix
      fakeSource.emitFix(LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: currentTime,
      ));
      await pumpEventQueue();
      expect(monitor.value.status, SafeZoneStatus.inside);

      // 2. First outside fix (debouncing)
      final outsideTime1 = currentTime.add(const Duration(seconds: 15));
      fakeSource.emitFix(LocationFix(
        latitude: 12.9716 + 0.003, // ~333m away (>150m)
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: outsideTime1,
      ));
      await pumpEventQueue();

      // Still inside because outsideConfirmations = 2
      expect(monitor.value.status, SafeZoneStatus.inside);

      // 3. Second consecutive outside fix -> confirms outside
      final outsideTime2 = currentTime.add(const Duration(seconds: 30));
      fakeSource.emitFix(LocationFix(
        latitude: 12.9716 + 0.003,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: outsideTime2,
      ));
      await pumpEventQueue();

      expect(monitor.value.status, SafeZoneStatus.outside);
      expect(monitor.value.effectiveStatus, SafeZoneStatus.outside);
      expect(monitor.value.isSafe, isFalse);
      expect(monitor.value.lastUpdated, outsideTime2);

      // 4. A single inside fix immediately restores inside status
      final insideTime2 = currentTime.add(const Duration(seconds: 45));
      fakeSource.emitFix(LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: insideTime2,
      ));
      await pumpEventQueue();

      expect(monitor.value.status, SafeZoneStatus.inside);
      expect(monitor.value.isSafe, isTrue);
      expect(monitor.value.lastUpdated, insideTime2);

      monitor.dispose();
    });

    test(
        'uncertain fix keeps previous confirmed status and does not refresh lastUpdated',
        () async {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => currentTime,
      );

      await monitor.start();

      // Confirmed inside fix
      fakeSource.emitFix(LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: currentTime,
      ));
      await pumpEventQueue();
      expect(monitor.value.status, SafeZoneStatus.inside);
      expect(monitor.value.lastUpdated, currentTime);

      // Inaccurate fix (accuracy 150m > 100m maxAcceptable)
      final laterTime = currentTime.add(const Duration(seconds: 30));
      fakeSource.emitFix(LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 150.0,
        timestamp: laterTime,
      ));
      await pumpEventQueue();

      // Status remains inside, but lastUpdated is NOT bumped
      expect(monitor.value.status, SafeZoneStatus.inside);
      expect(monitor.value.lastUpdated, currentTime);

      monitor.dispose();
    });

    test('no new fix for more than staleAfter degrades to stale and isSafe false',
        () async {
      var clockTime = currentTime;
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => clockTime,
        staleAfter: const Duration(minutes: 5),
        stalenessCheckInterval: const Duration(milliseconds: 100),
      );

      await monitor.start();

      // Initial inside fix
      fakeSource.emitFix(LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: clockTime,
      ));
      await pumpEventQueue();
      expect(monitor.value.status, SafeZoneStatus.inside);
      expect(monitor.value.isSafe, isTrue);

      // Advance time beyond 5-minute stale threshold
      clockTime = clockTime.add(const Duration(minutes: 5, seconds: 1));

      // Allow staleness check interval to trigger
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();

      expect(monitor.value.status, SafeZoneStatus.stale);
      expect(monitor.value.effectiveStatus, SafeZoneStatus.stale);
      expect(monitor.value.isSafe, isFalse);

      monitor.dispose();
    });

    test('permission denied or service disabled reports unavailable', () async {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => currentTime,
      );

      await monitor.start();

      fakeSource.emitError(const LocationPermissionFailure('Location permission denied'));
      await pumpEventQueue();

      expect(monitor.value.status, SafeZoneStatus.unavailable);
      expect(monitor.value.zoneName, isNull);
      expect(monitor.value.isSafe, isFalse);

      monitor.dispose();
    });

    test('noZone reports unavailable with null zoneName', () async {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => null, // No config available
        now: () => currentTime,
      );

      await monitor.start();

      fakeSource.emitFix(LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: currentTime,
      ));
      await pumpEventQueue();

      expect(monitor.value.status, SafeZoneStatus.unavailable);
      expect(monitor.value.zoneName, isNull);
      expect(monitor.value.isSafe, isFalse);

      monitor.dispose();
    });

    test('invalid fix is ignored', () async {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => currentTime,
      );

      await monitor.start();

      // Emit NaN coordinate
      fakeSource.emitFix(LocationFix(
        latitude: double.nan,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: currentTime,
      ));
      await pumpEventQueue();

      // Still in initial locating state
      expect(monitor.value.status, SafeZoneStatus.locating);

      monitor.dispose();
    });

    test('start() called twice does not duplicate subscriptions', () async {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => currentTime,
      );

      await monitor.start();
      await monitor.start();

      expect(fakeSource.startCallCount, 1);

      monitor.dispose();
      expect(fakeSource.stopCallCount, 1);
    });

    test('dispose() stops monitor and cancels active timer and subscription',
        () async {
      final monitor = SafeZoneMonitor(
        locationSource: fakeSource,
        configProvider: () => testConfig,
        now: () => currentTime,
      );

      await monitor.start();
      monitor.dispose();

      expect(fakeSource.stopCallCount, 1);

      // Emitting after dispose should not throw
      fakeSource.emitFix(LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: currentTime,
      ));
      await pumpEventQueue();
    });
  });
}
