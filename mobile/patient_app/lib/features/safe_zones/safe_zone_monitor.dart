import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/failures.dart';
import '../../data/datasources/location_datasource.dart';
import '../../data/models/location_fix.dart';
import '../../data/models/safe_zone_config.dart';
import '../../data/models/safe_zone_state.dart';
import '../../data/services/location_uploader.dart';
import 'geofence_evaluator.dart';

/// Monitors live or mock location updates, evaluates geofence boundaries,
/// debounces exit transitions, and manages staleness to report accurate
/// [SafeZoneInfo] to the UI.
class SafeZoneMonitor extends ChangeNotifier
    implements ValueListenable<SafeZoneInfo> {
  final LocationSource locationSource;
  final SafeZoneConfig? Function() configProvider;
  final GeofenceEvaluator evaluator;
  final DateTime Function() now;
  final int outsideConfirmations;
  final Duration staleAfter;
  final Duration stalenessCheckInterval;
  final LocationUploader? uploader;

  SafeZoneInfo _value;
  StreamSubscription<LocationFix>? _fixSubscription;
  Timer? _stalenessTimer;
  bool _isRunning = false;

  SafeZoneStatus? _lastConfirmedStatus;
  int _consecutiveOutsideCount = 0;

  SafeZoneMonitor({
    required this.locationSource,
    required this.configProvider,
    this.evaluator = const GeofenceEvaluator(),
    DateTime Function()? now,
    this.outsideConfirmations = 2,
    this.staleAfter = SafeZoneInfo.defaultStaleThreshold,
    this.stalenessCheckInterval = const Duration(seconds: 15),
    this.uploader,
  })  : now = now ?? DateTime.now,
        _value = SafeZoneInfo(
          status: SafeZoneStatus.locating,
          zoneName: null,
          lastUpdated: null,
          staleThreshold: staleAfter,
          nowProvider: now ?? DateTime.now,
        );

  @override
  SafeZoneInfo get value => _value;

  /// Whether active monitoring is in progress.
  bool get isRunning => _isRunning;

  /// Starts listening to the location source and running periodic staleness checks.
  /// Safe to call multiple times without duplicating timers or subscriptions.
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    // Listen to incoming location fixes
    _fixSubscription = locationSource.fixes.listen(
      _handleLocationFix,
      onError: _handleLocationError,
    );

    // Periodic timer to detect when no new fixes arrive and downgrade to stale
    _stalenessTimer?.cancel();
    _stalenessTimer = Timer.periodic(stalenessCheckInterval, (_) {
      _checkStaleness();
    });

    try {
      await locationSource.start();
    } catch (e) {
      _handleLocationError(e);
    }
  }

  /// Stops tracking and cancels active subscriptions and staleness timers.
  Future<void> stop() async {
    _isRunning = false;
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    final sub = _fixSubscription;
    _fixSubscription = null;
    final stopFuture = locationSource.stop();
    await sub?.cancel();
    await stopFuture;
  }

  void _handleLocationFix(LocationFix fix) {
    if (!fix.isValid) return;

    final config = configProvider();
    final result = evaluator.evaluateFix(config: config, fix: fix);

    if (result.decision != GeofenceDecision.invalidFix) {
      uploader?.upload(fix);
    }

    switch (result.decision) {
      case GeofenceDecision.noZone:
        _consecutiveOutsideCount = 0;
        _lastConfirmedStatus = null;
        // SafeZoneStatus maps to unavailable with null zoneName when no zone configured
        _updateValue(SafeZoneInfo(
          status: SafeZoneStatus.unavailable,
          zoneName: null,
          lastUpdated: now(),
          staleThreshold: staleAfter,
          nowProvider: now,
        ));
        break;

      case GeofenceDecision.invalidFix:
        // Ignore invalid fixes (e.g. NaN, out of range coordinates)
        break;

      case GeofenceDecision.inside:
        _consecutiveOutsideCount = 0;
        _lastConfirmedStatus = SafeZoneStatus.inside;
        _updateValue(SafeZoneInfo(
          status: SafeZoneStatus.inside,
          zoneName: config?.name,
          lastUpdated: fix.timestamp,
          staleThreshold: staleAfter,
          nowProvider: now,
        ));
        break;

      case GeofenceDecision.outside:
        _consecutiveOutsideCount++;
        if (_consecutiveOutsideCount >= outsideConfirmations) {
          _lastConfirmedStatus = SafeZoneStatus.outside;
          _updateValue(SafeZoneInfo(
            status: SafeZoneStatus.outside,
            zoneName: config?.name,
            lastUpdated: fix.timestamp,
            staleThreshold: staleAfter,
            nowProvider: now,
          ));
        }
        break;

      case GeofenceDecision.uncertain:
        _consecutiveOutsideCount = 0;
        if (_lastConfirmedStatus == null) {
          _updateValue(SafeZoneInfo(
            status: SafeZoneStatus.locating,
            zoneName: config?.name,
            lastUpdated: _value.lastUpdated,
            staleThreshold: staleAfter,
            nowProvider: now,
          ));
        } else {
          // Keep last confirmed status without updating lastUpdated timestamp
          _updateValue(SafeZoneInfo(
            status: _lastConfirmedStatus!,
            zoneName: config?.name,
            lastUpdated: _value.lastUpdated,
            staleThreshold: staleAfter,
            nowProvider: now,
          ));
        }
        break;
    }
  }

  void _handleLocationError(dynamic error) {
    _consecutiveOutsideCount = 0;
    _lastConfirmedStatus = null;

    if (error is LocationPermissionFailure) {
      _updateValue(SafeZoneInfo(
        status: SafeZoneStatus.unavailable,
        zoneName: null,
        lastUpdated: now(),
        staleThreshold: staleAfter,
        nowProvider: now,
      ));
    } else {
      _updateValue(SafeZoneInfo(
        status: SafeZoneStatus.unavailable,
        zoneName: null,
        lastUpdated: now(),
        staleThreshold: staleAfter,
        nowProvider: now,
      ));
    }
  }

  void _checkStaleness() {
    if (_value.status == SafeZoneStatus.inside) {
      final last = _value.lastUpdated;
      if (last != null) {
        final age = now().difference(last);
        if (age > staleAfter) {
          _updateValue(SafeZoneInfo(
            status: SafeZoneStatus.stale,
            zoneName: _value.zoneName,
            lastUpdated: _value.lastUpdated,
            staleThreshold: staleAfter,
            nowProvider: now,
          ));
        }
      }
    }
  }

  void _updateValue(SafeZoneInfo newValue) {
    if (_value.status != newValue.status ||
        _value.zoneName != newValue.zoneName ||
        _value.lastUpdated != newValue.lastUpdated) {
      _value = newValue;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isRunning = false;
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    _fixSubscription?.cancel();
    _fixSubscription = null;
    locationSource.stop();
    super.dispose();
  }
}
