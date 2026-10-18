import 'package:geolocator/geolocator.dart';
import '../errors/failures.dart';

/// Status of location permissions and hardware services.
enum LocationAccess {
  /// Permission granted (either while-in-use or always).
  granted,

  /// Permission was denied by the user.
  denied,

  /// Permission was permanently denied; user must enable in settings.
  deniedForever,

  /// System location services (GPS) are disabled on the device.
  serviceDisabled,
}

/// Swappable interface wrapping Geolocator platform calls for unit testability.
abstract class GeolocatorPlatformWrapper {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
  Future<Position?> getCurrentPosition();
}

/// Default production implementation delegating to [Geolocator].
class DefaultGeolocatorPlatformWrapper implements GeolocatorPlatformWrapper {
  const DefaultGeolocatorPlatformWrapper();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<Position?> getCurrentPosition() => Geolocator.getCurrentPosition();
}

/// Helper facilitating device location retrieval and permission checks.
class LocationHelper {
  /// Injectable platform wrapper for testing without a physical device/plugin.
  static GeolocatorPlatformWrapper platform =
      const DefaultGeolocatorPlatformWrapper();

  /// Checks and requests location permissions and hardware GPS status.
  ///
  /// - If location service is disabled -> [LocationAccess.serviceDisabled]
  /// - If permission is [LocationPermission.deniedForever] -> [LocationAccess.deniedForever] (does NOT prompt requestPermission)
  /// - If [LocationPermission.denied] -> requests permission.
  ///   - If granted -> [LocationAccess.granted]
  ///   - If deniedForever -> [LocationAccess.deniedForever]
  ///   - Otherwise -> [LocationAccess.denied]
  /// - If already [LocationPermission.whileInUse] or [LocationPermission.always] -> [LocationAccess.granted]
  static Future<LocationAccess> ensureAccess({
    GeolocatorPlatformWrapper? customPlatform,
  }) async {
    final p = customPlatform ?? platform;

    final serviceEnabled = await p.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationAccess.serviceDisabled;
    }

    LocationPermission permission = await p.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      return LocationAccess.deniedForever;
    }

    if (permission == LocationPermission.denied) {
      permission = await p.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        return LocationAccess.deniedForever;
      }
      if (permission == LocationPermission.denied) {
        return LocationAccess.denied;
      }
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return LocationAccess.granted;
    }

    return LocationAccess.denied;
  }

  /// Opens the system location settings (GPS toggle).
  static Future<void> openLocationSettings({
    GeolocatorPlatformWrapper? customPlatform,
  }) async {
    final p = customPlatform ?? platform;
    await p.openLocationSettings();
  }

  /// Opens the app settings page for permissions.
  static Future<void> openAppSettings({
    GeolocatorPlatformWrapper? customPlatform,
  }) async {
    final p = customPlatform ?? platform;
    await p.openAppSettings();
  }

  /// Preserved signature: returns current [Position?] if access is granted,
  /// otherwise returns null.
  static Future<Position?> getCurrentPosition({
    GeolocatorPlatformWrapper? customPlatform,
  }) async {
    final access = await ensureAccess(customPlatform: customPlatform);
    if (access != LocationAccess.granted) return null;
    final p = customPlatform ?? platform;
    return await p.getCurrentPosition();
  }

  /// Maps a non-granted [LocationAccess] to an appropriate [LocationPermissionFailure].
  static LocationPermissionFailure? toFailure(LocationAccess access) {
    switch (access) {
      case LocationAccess.granted:
        return null;
      case LocationAccess.serviceDisabled:
        return const LocationPermissionFailure(
            'Location services are disabled on device');
      case LocationAccess.denied:
        return const LocationPermissionFailure(
            'Location permission was denied');
      case LocationAccess.deniedForever:
        return const LocationPermissionFailure(
            'Location permission is permanently denied in settings');
    }
  }
}
