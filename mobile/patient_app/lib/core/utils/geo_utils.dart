import 'dart:math' as math;

/// Mean Earth radius in meters, identical to the backend definition in `app/utils/geo.py`.
const double earthRadiusMeters = 6371000.0;

/// Calculates the great-circle distance between two geographic coordinates
/// in meters using the Haversine formula.
///
/// The implementation mirrors the backend `haversine_meters` function in
/// `backend/app/utils/geo.py`.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * (math.pi / 180.0);
  final phi2 = lat2 * (math.pi / 180.0);
  final dPhi = (lat2 - lat1) * (math.pi / 180.0);
  final dLambda = (lon2 - lon1) * (math.pi / 180.0);

  final sinDPhi2 = math.sin(dPhi / 2.0);
  final sinDLambda2 = math.sin(dLambda / 2.0);

  final a = sinDPhi2 * sinDPhi2 +
      math.cos(phi1) * math.cos(phi2) * sinDLambda2 * sinDLambda2;

  final clampedA = a.clamp(0.0, 1.0);
  return 2.0 *
      earthRadiusMeters *
      math.atan2(math.sqrt(clampedA), math.sqrt(1.0 - clampedA));
}

/// Validates whether [latitude] is a real finite number within [-90.0, 90.0].
bool isValidLatitude(double latitude) {
  if (latitude.isNaN || latitude.isInfinite) return false;
  return latitude >= -90.0 && latitude <= 90.0;
}

/// Validates whether [longitude] is a real finite number within [-180.0, 180.0].
bool isValidLongitude(double longitude) {
  if (longitude.isNaN || longitude.isInfinite) return false;
  return longitude >= -180.0 && longitude <= 180.0;
}
