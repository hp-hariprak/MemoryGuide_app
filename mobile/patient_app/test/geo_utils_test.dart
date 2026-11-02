import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/core/utils/geo_utils.dart';
import 'package:patient_app/data/models/location_fix.dart';

void main() {
  group('LocationFix Validation & Staleness Tests', () {
    final now = DateTime.utc(2026, 11, 2, 12, 0, 0);

    test('Valid LocationFix passes isValid', () {
      final fix = LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 8.5,
        timestamp: now,
      );
      expect(fix.isValid, isTrue);
    });

    test('Invalid latitude is rejected by isValid', () {
      final fixOver = LocationFix(
        latitude: 91.0,
        longitude: 77.5946,
        timestamp: now,
      );
      final fixUnder = LocationFix(
        latitude: -90.5,
        longitude: 77.5946,
        timestamp: now,
      );
      final fixNan = LocationFix(
        latitude: double.nan,
        longitude: 77.5946,
        timestamp: now,
      );
      expect(fixOver.isValid, isFalse);
      expect(fixUnder.isValid, isFalse);
      expect(fixNan.isValid, isFalse);
    });

    test('Invalid longitude is rejected by isValid', () {
      final fixOver = LocationFix(
        latitude: 12.0,
        longitude: 180.1,
        timestamp: now,
      );
      final fixUnder = LocationFix(
        latitude: 12.0,
        longitude: -180.5,
        timestamp: now,
      );
      final fixNan = LocationFix(
        latitude: 12.0,
        longitude: double.nan,
        timestamp: now,
      );
      expect(fixOver.isValid, isFalse);
      expect(fixUnder.isValid, isFalse);
      expect(fixNan.isValid, isFalse);
    });

    test('Negative or NaN accuracy is rejected by isValid', () {
      final fixNeg = LocationFix(
        latitude: 12.0,
        longitude: 77.0,
        accuracyMeters: -5.0,
        timestamp: now,
      );
      final fixNan = LocationFix(
        latitude: 12.0,
        longitude: 77.0,
        accuracyMeters: double.nan,
        timestamp: now,
      );
      expect(fixNeg.isValid, isFalse);
      expect(fixNan.isValid, isFalse);
    });

    test('Stale detection marks old fixes as stale', () {
      final freshFix = LocationFix(
        latitude: 12.0,
        longitude: 77.0,
        timestamp: now.subtract(const Duration(seconds: 15)),
      );
      final staleFix = LocationFix(
        latitude: 12.0,
        longitude: 77.0,
        timestamp: now.subtract(const Duration(minutes: 5)),
      );

      expect(freshFix.isStale(const Duration(minutes: 2), now), isFalse);
      expect(staleFix.isStale(const Duration(minutes: 2), now), isTrue);
    });
  });
  group('GeoUtils haversineMeters Tests', () {
    const centerLat = 12.9716;
    const centerLon = 77.5946;

    test('Zone center to itself is 0', () {
      final distance = haversineMeters(centerLat, centerLon, centerLat, centerLon);
      expect(distance, closeTo(0.0, 0.001));
    });

    test('+0.001° latitude is ~111.195 m (within 0.5 m)', () {
      final distance = haversineMeters(centerLat, centerLon, centerLat + 0.001, centerLon);
      expect(distance, closeTo(111.195, 0.5));
    });

    test('+0.001° longitude is ~108.357 m (within 0.5 m)', () {
      final distance = haversineMeters(centerLat, centerLon, centerLat, centerLon + 0.001);
      expect(distance, closeTo(108.357, 0.5));
    });

    test('+0.0009° latitude is ~100.075 m (within 0.5 m)', () {
      final distance = haversineMeters(centerLat, centerLon, centerLat + 0.0009, centerLon);
      expect(distance, closeTo(100.075, 0.5));
    });

    test('+0.002° latitude is ~222.390 m (within 0.5 m)', () {
      final distance = haversineMeters(centerLat, centerLon, centerLat + 0.002, centerLon);
      expect(distance, closeTo(222.390, 0.5));
    });

    test('(0,0) to (0,1) is ~111194.927 m (within 0.5 m)', () {
      final distance = haversineMeters(0.0, 0.0, 0.0, 1.0);
      expect(distance, closeTo(111194.927, 0.5));
    });

    test('Antimeridian: (0, 179.9999) to (0, -179.9999) is ~22.239 m (within 0.5 m)', () {
      final distance = haversineMeters(0.0, 179.9999, 0.0, -179.9999);
      expect(distance, closeTo(22.239, 0.5));
    });

    test('London (51.5074, -0.1278) to Paris (48.8566, 2.3522) is within 50 m of 343556 m', () {
      final distance = haversineMeters(51.5074, -0.1278, 48.8566, 2.3522);
      expect(distance, closeTo(343556.0, 50.0));
    });

    test('Symmetry: dist(A, B) == dist(B, A)', () {
      final d1 = haversineMeters(centerLat, centerLon, 13.05, 77.70);
      final d2 = haversineMeters(13.05, 77.70, centerLat, centerLon);
      expect(d1, closeTo(d2, 0.00001));
    });
  });

  group('GeoUtils coordinate validation tests', () {
    test('isValidLatitude validates range and rejects NaN / Infinity', () {
      expect(isValidLatitude(0.0), isTrue);
      expect(isValidLatitude(-90.0), isTrue);
      expect(isValidLatitude(90.0), isTrue);
      expect(isValidLatitude(12.9716), isTrue);

      expect(isValidLatitude(90.0001), isFalse);
      expect(isValidLatitude(-90.0001), isFalse);
      expect(isValidLatitude(double.nan), isFalse);
      expect(isValidLatitude(double.infinity), isFalse);
      expect(isValidLatitude(double.negativeInfinity), isFalse);
    });

    test('isValidLongitude validates range and rejects NaN / Infinity', () {
      expect(isValidLongitude(0.0), isTrue);
      expect(isValidLongitude(-180.0), isTrue);
      expect(isValidLongitude(180.0), isTrue);
      expect(isValidLongitude(77.5946), isTrue);

      expect(isValidLongitude(180.0001), isFalse);
      expect(isValidLongitude(-180.0001), isFalse);
      expect(isValidLongitude(double.nan), isFalse);
      expect(isValidLongitude(double.infinity), isFalse);
      expect(isValidLongitude(double.negativeInfinity), isFalse);
    });
  });
}
