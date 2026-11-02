/// Represents the patient's safe-zone status relative to their designated geofences.
enum SafeZoneStatus {
  /// The patient is confirmed to be inside an active safe zone (e.g. Home, Clinic).
  inside,

  /// The patient has left their active safe zones.
  outside,

  /// The GPS is currently searching for a satellite fix or acquiring location.
  locating,

  /// Location services are disabled or permissions are missing.
  unavailable,

  /// Location signal has not updated recently and cannot be verified in real time.
  stale,
}

/// Data container holding information about the current safe zone status.
class SafeZoneInfo {
  final SafeZoneStatus status;
  final String? zoneName;
  final DateTime? lastUpdated;

  /// Custom threshold after which location readings are considered stale.
  /// Defaults to [defaultStaleThreshold] (5 minutes) if null.
  final Duration? staleThreshold;

  /// Optional time provider for testing and custom clocks.
  final DateTime Function()? nowProvider;

  const SafeZoneInfo({
    required this.status,
    this.zoneName,
    this.lastUpdated,
    this.staleThreshold,
    this.nowProvider,
  });

  /// Default threshold after which a location fix is considered stale.
  static const Duration defaultStaleThreshold = Duration(minutes: 5);

  /// Whether the location update is older than the staleness threshold,
  /// or explicitly flagged as [SafeZoneStatus.stale].
  bool get isStale {
    if (status == SafeZoneStatus.stale) return true;
    if (lastUpdated == null) return false;
    final threshold = staleThreshold ?? defaultStaleThreshold;
    final current = nowProvider != null ? nowProvider!() : DateTime.now();
    return current.difference(lastUpdated!) > threshold;
  }

  /// Evaluated effective status taking staleness into account.
  ///
  /// Never reports [SafeZoneStatus.inside] when the reading is stale or unverified.
  SafeZoneStatus get effectiveStatus {
    if (status == SafeZoneStatus.inside && isStale) {
      return SafeZoneStatus.stale;
    }
    return status;
  }

  /// Convenience getter to easily check if the patient is safely inside.
  ///
  /// Never true if status is outside, locating, unavailable, or stale.
  bool get isSafe => effectiveStatus == SafeZoneStatus.inside;

  /// Default starter state: inside Home Zone with fresh timestamp.
  factory SafeZoneInfo.initial() {
    return SafeZoneInfo(
      status: SafeZoneStatus.inside,
      zoneName: 'Home Zone',
      lastUpdated: DateTime.now(),
    );
  }
}
