import 'dart:async';
import '../datasources/location_datasource.dart';
import '../models/location_fix.dart';

/// Service responsible for managing continuous location tracking sessions.
/// Delegates start/stop calls to the active [LocationSource].
class BackgroundLocationService {
  final LocationSource _locationSource;
  StreamSubscription<LocationFix>? _subscription;
  LocationFix? _lastFix;
  bool _isTracking = false;

  BackgroundLocationService([LocationSource? locationSource])
      : _locationSource = locationSource ??
            (useMockLocation ? MockLocationSource() : GeolocatorLocationSource());

  /// The active underlying location provider.
  LocationSource get source => _locationSource;

  /// Stream of location updates emitted while tracking is running.
  Stream<LocationFix> get fixes => _locationSource.fixes;

  /// The latest verified location fix received during tracking.
  LocationFix? get lastFix => _lastFix;

  /// Whether background tracking is actively running.
  bool get isTracking => _isTracking;

  /// Starts scheduled or streamed location tracking.
  Future<void> startTracking() async {
    if (_isTracking) return;
    _isTracking = true;

    _subscription?.cancel();
    _subscription = _locationSource.fixes.listen(
      (fix) {
        if (fix.isValid) {
          _lastFix = fix;
        }
      },
      onError: (_) {
        // Log or handle error without crashing
      },
    );

    await _locationSource.start();
  }

  /// Stops tracking and releases resources.
  Future<void> stopTracking() async {
    _isTracking = false;
    await _subscription?.cancel();
    _subscription = null;
    await _locationSource.stop();
  }

  void dispose() {
    stopTracking();
  }
}
