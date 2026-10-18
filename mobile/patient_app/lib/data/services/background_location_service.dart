import '../datasources/location_datasource.dart';
import '../models/location_fix.dart';

/// Service responsible for managing continuous location tracking sessions.
/// Delegates start/stop calls to the active [LocationSource].
class BackgroundLocationService {
  final LocationSource _locationSource;

  BackgroundLocationService([LocationSource? locationSource])
      : _locationSource = locationSource ??
            (useMockLocation ? MockLocationSource() : GeolocatorLocationSource());

  /// The active underlying location provider.
  LocationSource get source => _locationSource;

  /// Stream of location updates emitted while tracking is running.
  Stream<LocationFix> get fixes => _locationSource.fixes;

  /// Starts scheduled or streamed location tracking.
  Future<void> startTracking() async {
    await _locationSource.start();
  }

  /// Stops tracking and releases resources.
  Future<void> stopTracking() async {
    await _locationSource.stop();
  }
}
