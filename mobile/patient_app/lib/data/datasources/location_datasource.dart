import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/location_helper.dart';
import '../models/location_fix.dart';

/// Abstract contract for streaming location fixes from mock or hardware GPS sources.
abstract class LocationSource {
  /// Stream of location updates emitted while tracking is active.
  Stream<LocationFix> get fixes;

  /// Starts listening to or generating location fixes.
  Future<void> start();

  /// Stops tracking and releases subscriptions/timers.
  Future<void> stop();
}

/// Scripted mock location source that simulates a patient moving inside, outside,
/// and back into their designated safe zone.
class MockLocationSource implements LocationSource {
  final Duration tickDuration;
  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  Timer? _timer;
  int _currentIndex = 0;

  static const double centerLat = 12.9716;
  static const double centerLon = 77.5946;

  /// Predefined scripted route simulating a realistic journey:
  /// 1. At center (0m away) -> inside
  /// 2. 60m away -> inside
  /// 3. Just inside radius (133m <= 150m) -> inside
  /// 4. Just outside boundary (167m > 150m) -> outside
  /// 5. Far outside (500m > 150m) -> outside
  /// 6. Poor-accuracy fix (accuracy 150m exceeds max 100m) -> uncertain
  /// 7. Back inside safe zone -> inside
  static final List<LocationFix> defaultScript = [
    LocationFix(
      latitude: centerLat,
      longitude: centerLon,
      accuracyMeters: 5.0,
      timestamp: DateTime.now().toUtc(),
    ),
    LocationFix(
      latitude: centerLat + 0.00054,
      longitude: centerLon,
      accuracyMeters: 10.0,
      timestamp: DateTime.now().toUtc(),
    ),
    LocationFix(
      latitude: centerLat + 0.0012,
      longitude: centerLon,
      accuracyMeters: 10.0,
      timestamp: DateTime.now().toUtc(),
    ),
    LocationFix(
      latitude: centerLat + 0.0015,
      longitude: centerLon,
      accuracyMeters: 10.0,
      timestamp: DateTime.now().toUtc(),
    ),
    LocationFix(
      latitude: centerLat + 0.0045,
      longitude: centerLon,
      accuracyMeters: 15.0,
      timestamp: DateTime.now().toUtc(),
    ),
    LocationFix(
      latitude: centerLat + 0.001,
      longitude: centerLon,
      accuracyMeters: 150.0,
      timestamp: DateTime.now().toUtc(),
    ),
    LocationFix(
      latitude: centerLat,
      longitude: centerLon,
      accuracyMeters: 8.0,
      timestamp: DateTime.now().toUtc(),
    ),
  ];

  final List<LocationFix> route;

  MockLocationSource({
    this.tickDuration = const Duration(seconds: 3),
    List<LocationFix>? customRoute,
  }) : route = customRoute ?? defaultScript;

  @override
  Stream<LocationFix> get fixes => _controller.stream;

  @override
  Future<void> start() async {
    _timer?.cancel();
    if (route.isEmpty) return;

    // Emit initial fix immediately
    _emitNextFix();

    _timer = Timer.periodic(tickDuration, (_) {
      _emitNextFix();
    });
  }

  void _emitNextFix() {
    if (_controller.isClosed) return;
    final template = route[_currentIndex];
    final fix = LocationFix(
      latitude: template.latitude,
      longitude: template.longitude,
      accuracyMeters: template.accuracyMeters,
      timestamp: DateTime.now().toUtc(),
      altitudeMeters: template.altitudeMeters,
      speedMps: template.speedMps,
      headingDegrees: template.headingDegrees,
    );
    _controller.add(fix);
    _currentIndex = (_currentIndex + 1) % route.length;
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Real GPS location source streaming device positions via [Geolocator].
class GeolocatorLocationSource implements LocationSource {
  final int locationIntervalSeconds;
  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _periodicFallbackTimer;
  bool _isRunning = false;

  GeolocatorLocationSource({
    int intervalSeconds = AppConstants.locationPingIntervalSeconds,
  }) : locationIntervalSeconds =
            intervalSeconds < 15 ? 15 : intervalSeconds;

  @override
  Stream<LocationFix> get fixes => _controller.stream;

  @override
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    final access = await LocationHelper.ensureAccess();
    if (access != LocationAccess.granted) {
      if (!_controller.isClosed) {
        _controller.addError(
          LocationHelper.toFailure(access) ??
              const LocationPermissionFailure('Location access unavailable'),
        );
      }
      return;
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) {
        if (!_controller.isClosed) {
          _controller.add(LocationFix.fromPosition(position));
        }
      },
      onError: (error) {
        if (!_controller.isClosed) {
          _controller.addError(error);
        }
      },
    );

    // Guarantee a fix at least every locationIntervalSeconds
    _periodicFallbackTimer?.cancel();
    _periodicFallbackTimer = Timer.periodic(
      Duration(seconds: locationIntervalSeconds),
      (_) async {
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          if (!_controller.isClosed) {
            _controller.add(LocationFix.fromPosition(pos));
          }
        } catch (e) {
          if (!_controller.isClosed) {
            _controller.addError(e);
          }
        }
      },
    );
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _periodicFallbackTimer?.cancel();
    _periodicFallbackTimer = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Compile-time flag controlling default location provider (true by default).
const bool useMockLocation =
    bool.fromEnvironment('USE_MOCK_LOCATION', defaultValue: true);

/// Data source managing the active [LocationSource].
class LocationDataSource {
  final LocationSource activeSource;

  LocationDataSource([LocationSource? source])
      : activeSource = source ??
            (useMockLocation
                ? MockLocationSource()
                : GeolocatorLocationSource());

  Stream<LocationFix> get fixes => activeSource.fixes;
  Future<void> start() => activeSource.start();
  Future<void> stop() => activeSource.stop();
}
