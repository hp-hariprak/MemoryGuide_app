import '../../core/utils/geo_utils.dart';
import '../../data/models/location_fix.dart';
import '../../data/models/safe_zone_config.dart';

/// The high-level determination made by the geofence evaluation logic.
enum GeofenceDecision {
  /// Confirmed within the safe zone with acceptable accuracy.
  inside,

  /// Confirmed outside the safe zone boundary with acceptable accuracy.
  outside,

  /// The fix accuracy circle straddles the geofence perimeter or accuracy is too low.
  uncertain,

  /// Safe zone is unconfigured, disabled, or has out-of-range parameters.
  noZone,

  /// Coordinate values in fix are invalid, infinite, or NaN.
  invalidFix,
}

/// The outcome of evaluating a [LocationFix] against a [SafeZoneConfig].
class GeofenceResult {
  final GeofenceDecision decision;
  final double? distanceMeters;
  final double? marginMeters;
  final double? accuracyMeters;
  final String reason;

  const GeofenceResult({
    required this.decision,
    this.distanceMeters,
    this.marginMeters,
    this.accuracyMeters,
    required this.reason,
  });

  @override
  String toString() {
    return 'GeofenceResult($decision, dist: ${distanceMeters?.toStringAsFixed(1)}m, '
        'margin: ${marginMeters?.toStringAsFixed(1)}m, acc: ${accuracyMeters?.toStringAsFixed(1)}m, reason: "$reason")';
  }
}

/// Pure Dart geofence evaluator implementing patient-safety boundary and uncertainty calculations.
class GeofenceEvaluator {
  /// Default maximum device GPS accuracy in meters beyond which fixes are considered too uncertain.
  static const double defaultMaxAcceptableAccuracyMeters = 100.0;

  /// The maximum device GPS accuracy in meters beyond which fixes are considered too uncertain.
  final double maxAcceptableAccuracyMeters;

  const GeofenceEvaluator({
    this.maxAcceptableAccuracyMeters = defaultMaxAcceptableAccuracyMeters,
  });

  /// Evaluates whether [fix] is safely inside, outside, or uncertain relative to [config].
  ///
  /// Boundary evaluation rules (in strict order of precedence):
  /// 1. If [config] is null or !config.isUsable -> [GeofenceDecision.noZone]
  /// 2. If [fix] coordinates are invalid/NaN/out-of-range -> [GeofenceDecision.invalidFix]
  /// 3. Calculate distance via Haversine and margin = radius - distance
  /// 4. Accuracy checks:
  ///    - accuracy > [maxAcceptableAccuracyMeters] -> [GeofenceDecision.uncertain] (GPS accuracy too low)
  ///    - distance + accuracy <= radius -> [GeofenceDecision.inside] (certainly inside)
  ///    - distance - accuracy > radius -> [GeofenceDecision.outside] (certainly outside)
  ///    - otherwise -> [GeofenceDecision.uncertain] (accuracy circle straddles boundary)
  GeofenceResult evaluateFix({
    required SafeZoneConfig? config,
    required LocationFix fix,
  }) {
    // 1. Config usability check
    if (config == null || !config.isUsable) {
      return const GeofenceResult(
        decision: GeofenceDecision.noZone,
        reason: 'Safe zone configuration is missing, disabled, or invalid',
      );
    }

    // 2. Coordinate validity check
    if (!isValidLatitude(fix.latitude) || !isValidLongitude(fix.longitude)) {
      return const GeofenceResult(
        decision: GeofenceDecision.invalidFix,
        reason: 'Location fix has invalid, infinite, or NaN coordinates',
      );
    }

    // 3. Compute distance and margin
    final distance = haversineMeters(
      fix.latitude,
      fix.longitude,
      config.latitude!,
      config.longitude!,
    );
    final radius = config.radiusMeters!.toDouble();
    final margin = radius - distance;
    final accuracy = fix.accuracyMeters;
    final a = accuracy ?? 0.0;

    // 4. Accuracy & boundary evaluation
    if (accuracy != null && accuracy > maxAcceptableAccuracyMeters) {
      return GeofenceResult(
        decision: GeofenceDecision.uncertain,
        distanceMeters: distance,
        marginMeters: margin,
        accuracyMeters: accuracy,
        reason: 'GPS accuracy too low',
      );
    }

    if (distance + a <= radius) {
      return GeofenceResult(
        decision: GeofenceDecision.inside,
        distanceMeters: distance,
        marginMeters: margin,
        accuracyMeters: accuracy,
        reason: 'Confirmed inside safe zone boundary',
      );
    }

    if (distance - a > radius) {
      return GeofenceResult(
        decision: GeofenceDecision.outside,
        distanceMeters: distance,
        marginMeters: margin,
        accuracyMeters: accuracy,
        reason: 'Confirmed outside safe zone boundary',
      );
    }

    return GeofenceResult(
      decision: GeofenceDecision.uncertain,
      distanceMeters: distance,
      marginMeters: margin,
      accuracyMeters: accuracy,
      reason: 'Accuracy circle straddles safe zone perimeter',
    );
  }

  /// Convenience static evaluation method matching the required functional contract.
  static GeofenceResult evaluate({
    required SafeZoneConfig? config,
    required LocationFix fix,
    double maxAcceptableAccuracyMeters = 100.0,
  }) {
    return GeofenceEvaluator(
      maxAcceptableAccuracyMeters: maxAcceptableAccuracyMeters,
    ).evaluateFix(config: config, fix: fix);
  }
}
