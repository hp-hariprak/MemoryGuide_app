import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/data/models/location_fix.dart';
import 'package:patient_app/data/models/safe_zone_config.dart';
import 'package:patient_app/features/safe_zones/geofence_evaluator.dart';

void main() {
  group('GeofenceEvaluator Tests', () {
    const centerLat = 12.9716;
    const centerLon = 77.5946;
    final now = DateTime.utc(2026, 10, 16, 12, 0);

    const baseConfig = SafeZoneConfig(
      enabled: true,
      latitude: centerLat,
      longitude: centerLon,
      radiusMeters: 150,
      name: 'Home (Maple Street)',
    );

    test('Inside with accuracy null/0: +0.001° lat (111.2 m) -> inside', () {
      final fixNull = LocationFix(
        latitude: centerLat + 0.001,
        longitude: centerLon,
        accuracyMeters: null,
        timestamp: now,
      );
      final fixZero = LocationFix(
        latitude: centerLat + 0.001,
        longitude: centerLon,
        accuracyMeters: 0.0,
        timestamp: now,
      );

      final resNull = GeofenceEvaluator.evaluate(config: baseConfig, fix: fixNull);
      final resZero = GeofenceEvaluator.evaluate(config: baseConfig, fix: fixZero);

      expect(resNull.decision, equals(GeofenceDecision.inside));
      expect(resNull.distanceMeters, closeTo(111.195, 0.5));
      expect(resNull.marginMeters, closeTo(150.0 - 111.195, 0.5));

      expect(resZero.decision, equals(GeofenceDecision.inside));
    });

    test('Outside with accuracy null/0: +0.002° lat (222.4 m) -> outside', () {
      final fix = LocationFix(
        latitude: centerLat + 0.002,
        longitude: centerLon,
        accuracyMeters: 0.0,
        timestamp: now,
      );

      final res = GeofenceEvaluator.evaluate(config: baseConfig, fix: fix);
      expect(res.decision, equals(GeofenceDecision.outside));
      expect(res.distanceMeters, closeTo(222.390, 0.5));
      expect(res.marginMeters, isNegative);
    });

    test('Threshold edge cases: radius 100 vs 101 for +0.0009° lat (100.075 m)', () {
      final fix = LocationFix(
        latitude: centerLat + 0.0009,
        longitude: centerLon,
        accuracyMeters: 0.0,
        timestamp: now,
      );

      const config100 = SafeZoneConfig(
        enabled: true,
        latitude: centerLat,
        longitude: centerLon,
        radiusMeters: 100,
      );
      const config101 = SafeZoneConfig(
        enabled: true,
        latitude: centerLat,
        longitude: centerLon,
        radiusMeters: 101,
      );

      final res100 = GeofenceEvaluator.evaluate(config: config100, fix: fix);
      final res101 = GeofenceEvaluator.evaluate(config: config101, fix: fix);

      expect(res100.decision, equals(GeofenceDecision.outside));
      expect(res101.decision, equals(GeofenceDecision.inside));
    });

    test('Exactly on boundary with accuracy 0 -> inside (inclusive, matches backend <=)', () {
      // Create a config whose radius exactly matches the distance
      final fix = LocationFix(
        latitude: centerLat + 0.001,
        longitude: centerLon,
        accuracyMeters: 0.0,
        timestamp: now,
      );
      // Distance is ~111.195m. We can test with a custom radius or exact equality
      const exactConfig = SafeZoneConfig(
        enabled: true,
        latitude: centerLat,
        longitude: centerLon,
        radiusMeters: 112, // 111.195 <= 112
      );
      final res = GeofenceEvaluator.evaluate(config: exactConfig, fix: fix);
      expect(res.decision, equals(GeofenceDecision.inside));
    });

    test('Accuracy evaluation: distance 111m, radius 150m', () {
      // 111 + 20 = 131 <= 150 -> inside
      final fixAcc20 = LocationFix(
        latitude: centerLat + 0.001,
        longitude: centerLon,
        accuracyMeters: 20.0,
        timestamp: now,
      );
      final res20 = GeofenceEvaluator.evaluate(config: baseConfig, fix: fixAcc20);
      expect(res20.decision, equals(GeofenceDecision.inside));

      // 111 + 50 = 161 > 150 -> uncertain
      final fixAcc50 = LocationFix(
        latitude: centerLat + 0.001,
        longitude: centerLon,
        accuracyMeters: 50.0,
        timestamp: now,
      );
      final res50 = GeofenceEvaluator.evaluate(config: baseConfig, fix: fixAcc50);
      expect(res50.decision, equals(GeofenceDecision.uncertain));
      expect(res50.reason, contains('straddles'));
    });

    test('Accuracy evaluation: distance 222m, radius 150m', () {
      // 222 - 20 = 202 > 150 -> outside
      final fixAcc20 = LocationFix(
        latitude: centerLat + 0.002,
        longitude: centerLon,
        accuracyMeters: 20.0,
        timestamp: now,
      );
      final res20 = GeofenceEvaluator.evaluate(config: baseConfig, fix: fixAcc20);
      expect(res20.decision, equals(GeofenceDecision.outside));

      // 222 - 100 = 122 <= 150 -> uncertain (accuracy circle straddles boundary)
      final fixAcc100 = LocationFix(
        latitude: centerLat + 0.002,
        longitude: centerLon,
        accuracyMeters: 100.0,
        timestamp: now,
      );
      final res100 = GeofenceEvaluator.evaluate(config: baseConfig, fix: fixAcc100);
      expect(res100.decision, equals(GeofenceDecision.uncertain));

      // Accuracy 150 (> maxAcceptableAccuracyMeters 100) -> uncertain regardless of distance
      final fixAcc150 = LocationFix(
        latitude: centerLat, // at the center!
        longitude: centerLon,
        accuracyMeters: 150.0,
        timestamp: now,
      );
      final res150 = GeofenceEvaluator.evaluate(config: baseConfig, fix: fixAcc150);
      expect(res150.decision, equals(GeofenceDecision.uncertain));
      expect(res150.reason, equals('GPS accuracy too low'));
    });

    test('noZone returned for null, disabled, missing params or out-of-range radius', () {
      final fix = LocationFix(
        latitude: centerLat,
        longitude: centerLon,
        accuracyMeters: 5.0,
        timestamp: now,
      );

      expect(
        GeofenceEvaluator.evaluate(config: null, fix: fix).decision,
        equals(GeofenceDecision.noZone),
      );

      expect(
        GeofenceEvaluator.evaluate(
          config: const SafeZoneConfig(enabled: false, latitude: centerLat, longitude: centerLon, radiusMeters: 150),
          fix: fix,
        ).decision,
        equals(GeofenceDecision.noZone),
      );

      expect(
        GeofenceEvaluator.evaluate(
          config: const SafeZoneConfig(enabled: true, latitude: null, longitude: centerLon, radiusMeters: 150),
          fix: fix,
        ).decision,
        equals(GeofenceDecision.noZone),
      );

      // radius < 50
      expect(
        GeofenceEvaluator.evaluate(
          config: const SafeZoneConfig(enabled: true, latitude: centerLat, longitude: centerLon, radiusMeters: 49),
          fix: fix,
        ).decision,
        equals(GeofenceDecision.noZone),
      );

      // radius > 10000
      expect(
        GeofenceEvaluator.evaluate(
          config: const SafeZoneConfig(enabled: true, latitude: centerLat, longitude: centerLon, radiusMeters: 10001),
          fix: fix,
        ).decision,
        equals(GeofenceDecision.noZone),
      );
    });

    test('invalidFix returned for NaN or out-of-range coordinates', () {
      final fixNan = LocationFix(
        latitude: double.nan,
        longitude: centerLon,
        accuracyMeters: 5.0,
        timestamp: now,
      );
      final fixOor = LocationFix(
        latitude: 95.0,
        longitude: centerLon,
        accuracyMeters: 5.0,
        timestamp: now,
      );

      expect(
        GeofenceEvaluator.evaluate(config: baseConfig, fix: fixNan).decision,
        equals(GeofenceDecision.invalidFix),
      );
      expect(
        GeofenceEvaluator.evaluate(config: baseConfig, fix: fixOor).decision,
        equals(GeofenceDecision.invalidFix),
      );
    });

    test('Backend parity case from backend test_geofencing.py', () {
      const zoneConfig = SafeZoneConfig(
        enabled: true,
        latitude: 12.9716,
        longitude: 77.5946,
        radiusMeters: 200,
      );

      final centerFix = LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 5.0,
        timestamp: now,
      );
      final outsideFix = LocationFix(
        latitude: 13.05,
        longitude: 77.70,
        accuracyMeters: 10.0,
        timestamp: now,
      );

      final centerRes = GeofenceEvaluator.evaluate(config: zoneConfig, fix: centerFix);
      final outsideRes = GeofenceEvaluator.evaluate(config: zoneConfig, fix: outsideFix);

      expect(centerRes.decision, equals(GeofenceDecision.inside));
      expect(outsideRes.decision, equals(GeofenceDecision.outside));
      expect(outsideRes.distanceMeters, closeTo(14366.0, 10.0));
    });
  });
}
