import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/services/service_locator.dart';
import '../../data/datasources/location_datasource.dart';
import '../../data/models/location_fix.dart';
import '../../data/models/safe_zone_config.dart';
import '../../data/repositories/safe_zone_config_repository.dart';
import 'interactive_map.dart';

/// Full interactive real-time patient location tracking view.
/// Shows live patient position, home safe-zone perimeter, distance from home,
/// GPS accuracy halo, movement history breadcrumbs, and live status indicator.
class LiveTrackingView extends StatefulWidget {
  final LocationSource? locationSource;
  final SafeZoneConfigRepository? configRepository;

  const LiveTrackingView({
    super.key,
    this.locationSource,
    this.configRepository,
  });

  @override
  State<LiveTrackingView> createState() => _LiveTrackingViewState();
}

class _LiveTrackingViewState extends State<LiveTrackingView> {
  late final LocationSource _source;
  late final SafeZoneConfigRepository _configRepo;

  StreamSubscription<LocationFix>? _fixSub;
  Timer? _staleCheckTimer;

  SafeZoneConfig? _config;
  LocationFix? _currentFix;
  final List<MapCoordinate> _trail = [];

  bool _isLoading = true;
  String? _errorMessage;
  bool _isStale = false;

  @override
  void initState() {
    super.initState();
    _source = widget.locationSource ??
        (useMockLocation ? MockLocationSource() : GeolocatorLocationSource());
    _configRepo = widget.configRepository ??
        PatientAppServices.instance.safeZoneConfigRepository;

    _initializeTracking();
  }

  Future<void> _initializeTracking() async {
    // 1. Fetch safe-zone configuration
    try {
      final config = await _configRepo.load();
      if (mounted) {
        setState(() {
          _config = config;
        });
      }
    } catch (e) {
      // Retain fallback / null
    }

    // 2. Subscribe to location stream
    _fixSub = _source.fixes.listen(
      _handleLocationFix,
      onError: _handleLocationError,
    );

    // 3. Periodic timer to check staleness (every 10 seconds)
    _staleCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkStaleness();
    });

    try {
      await _source.start();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      _handleLocationError(e);
    }
  }

  void _handleLocationFix(LocationFix fix) {
    if (!fix.isValid) return;

    // Send live fix to backend
    if (PatientAppServices.instance.authRepository.isAuthenticated) {
      PatientAppServices.instance.locationUploader.upload(fix);
    }

    if (mounted) {
      setState(() {
        _currentFix = fix;
        _isStale = false;
        _errorMessage = null;
        _isLoading = false;

        // Append to trail, keeping last 30 breadcrumbs
        final coord = MapCoordinate(fix.latitude, fix.longitude);
        if (_trail.isEmpty || _trail.last != coord) {
          _trail.add(coord);
          if (_trail.length > 30) {
            _trail.removeAt(0);
          }
        }
      });
    }
  }

  void _handleLocationError(dynamic error) {
    if (mounted) {
      setState(() {
        _errorMessage = 'Location error: $error';
        _isLoading = false;
      });
    }
  }

  void _checkStaleness() {
    if (_currentFix == null) return;
    final age = DateTime.now().toUtc().difference(_currentFix!.timestamp);
    final isStale = age > const Duration(seconds: 45);
    if (isStale != _isStale && mounted) {
      setState(() {
        _isStale = isStale;
      });
    }
  }

  @override
  void dispose() {
    _staleCheckTimer?.cancel();
    _fixSub?.cancel();
    _source.stop();
    super.dispose();
  }

  SafeZoneConfig get _effectiveConfig {
    if (_config != null && _config!.isUsable) {
      return _config!;
    }
    return const SafeZoneConfig(
      enabled: true,
      latitude: 11.03000,
      longitude: 77.00600,
      radiusMeters: 200,
      name: 'Home Safe Zone',
    );
  }

  Future<void> _setHomeLocation(double lat, double lon) async {
    final updated = SafeZoneConfig(
      enabled: true,
      latitude: lat,
      longitude: lon,
      radiusMeters: _config?.radiusMeters ?? 200,
      name: 'Home Safe Zone',
    );
    setState(() {
      _config = updated;
    });
    try {
      await _configRepo.save(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Home destination set to (${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)})',
            ),
            backgroundColor: const Color(0xFF174D43),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {}
  }

  GeofenceVisualState _computeVisualState(double? distanceMeters) {
    if (_currentFix == null) {
      return GeofenceVisualState.inactive;
    }
    if (_isStale) {
      return GeofenceVisualState.uncertain;
    }
    final accuracy = _currentFix!.accuracyMeters ?? 0.0;
    if (accuracy > 100.0) {
      return GeofenceVisualState.uncertain;
    }

    final effectiveConfig = _effectiveConfig;
    if (!effectiveConfig.isUsable) {
      return GeofenceVisualState.inactive;
    }

    final radius = effectiveConfig.radiusMeters!.toDouble();
    if (distanceMeters != null) {
      if (distanceMeters + accuracy <= radius) {
        return GeofenceVisualState.inside;
      }
      if (distanceMeters - accuracy > radius) {
        return GeofenceVisualState.outside;
      }
      return GeofenceVisualState.uncertain;
    }
    return GeofenceVisualState.inactive;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveConfig = _effectiveConfig;
    final homeCoord = (effectiveConfig.latitude != null && effectiveConfig.longitude != null)
        ? MapCoordinate(effectiveConfig.latitude!, effectiveConfig.longitude!)
        : null;

    final patientCoord = _currentFix != null
        ? MapCoordinate(_currentFix!.latitude, _currentFix!.longitude)
        : null;

    // Calculate distance from home
    double? distanceMeters;
    if (homeCoord != null && patientCoord != null) {
      distanceMeters = Geolocator.distanceBetween(
        homeCoord.latitude,
        homeCoord.longitude,
        patientCoord.latitude,
        patientCoord.longitude,
      );
    }

    final visualState = _computeVisualState(distanceMeters);
    final initialCenter = patientCoord ?? homeCoord ?? const MapCoordinate(11.0305, 77.0064);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Live Patient Location',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1D2C27),
        elevation: 0,
        actions: [
          if (_currentFix != null)
            IconButton(
              icon: const Icon(Icons.add_location_alt_rounded),
              tooltip: 'Set Current GPS as Home',
              onPressed: () {
                _setHomeLocation(_currentFix!.latitude, _currentFix!.longitude);
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Location',
            onPressed: () {
              setState(() => _isLoading = true);
              _source.start().whenComplete(() {
                if (mounted) setState(() => _isLoading = false);
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Full Interactive Map
          MemoryGuideInteractiveMap(
            initialCenter: initialCenter,
            initialZoom: 16.5,
            homeLocation: homeCoord,
            safeZoneRadiusMeters: effectiveConfig.radiusMeters?.toDouble(),
            patientLocation: patientCoord,
            patientAccuracyMeters: _currentFix?.accuracyMeters,
            movementTrail: _trail,
            visualState: visualState,
            isEditable: true,
            onLocationSelected: (coord) {
              _setHomeLocation(coord.latitude, coord.longitude);
            },
          ),

          // 2. Loading overlay
          if (_isLoading)
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF174D43),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Acquiring live GPS satellite fix...',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

          // 3. Error Banner
          if (_errorMessage != null)
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                            color: Color(0xFFDC2626), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 4. Floating Real-time Metrics Bottom Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _TrackingStatusCard(
              fix: _currentFix,
              distanceMeters: distanceMeters,
              homeConfigured: homeCoord != null,
              patientGpsAvailable: patientCoord != null,
              safeZoneRadiusMeters: effectiveConfig.radiusMeters?.toDouble(),
              visualState: visualState,
              isStale: _isStale,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingStatusCard extends StatelessWidget {
  final LocationFix? fix;
  final double? distanceMeters;
  final bool homeConfigured;
  final bool patientGpsAvailable;
  final double? safeZoneRadiusMeters;
  final GeofenceVisualState visualState;
  final bool isStale;

  const _TrackingStatusCard({
    required this.fix,
    required this.distanceMeters,
    required this.homeConfigured,
    required this.patientGpsAvailable,
    required this.safeZoneRadiusMeters,
    required this.visualState,
    required this.isStale,
  });

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    Color badgeTextColor;
    String badgeText;
    IconData badgeIcon;

    switch (visualState) {
      case GeofenceVisualState.inside:
        badgeColor = const Color(0xFFE8F5EC);
        badgeTextColor = const Color(0xFF15803D);
        badgeText = isStale ? 'Inside (Stale Signal)' : 'Inside Safe Zone';
        badgeIcon = Icons.check_circle_rounded;
        break;
      case GeofenceVisualState.outside:
        badgeColor = const Color(0xFFFEF2F2);
        badgeTextColor = const Color(0xFFDC2626);
        badgeText = isStale ? 'Outside (Stale Signal)' : 'Outside Safe Zone';
        badgeIcon = Icons.warning_rounded;
        break;
      case GeofenceVisualState.uncertain:
        badgeColor = const Color(0xFFFFFBEB);
        badgeTextColor = const Color(0xFFD97706);
        badgeText = isStale ? 'Signal Stale' : 'Location Uncertain';
        badgeIcon = Icons.help_outline_rounded;
        break;
      case GeofenceVisualState.inactive:
        badgeColor = const Color(0xFFF1F5F9);
        badgeTextColor = const Color(0xFF64748B);
        badgeText = 'Awaiting GPS Fix';
        badgeIcon = Icons.gps_not_fixed_rounded;
        break;
    }

    final String distanceText;
    if (!homeConfigured) {
      distanceText = 'Home location not configured';
    } else if (!patientGpsAvailable) {
      distanceText = 'Waiting for patient GPS';
    } else if (distanceMeters != null) {
      distanceText = distanceMeters! < 1000
          ? '${distanceMeters!.toStringAsFixed(0)} m from home'
          : '${(distanceMeters! / 1000).toStringAsFixed(2)} km from home';
    } else {
      distanceText = 'Waiting for patient GPS';
    }

    final String accuracyText = fix?.accuracyMeters != null
        ? '±${fix!.accuracyMeters!.toStringAsFixed(1)} m'
        : 'Unknown accuracy';

    final String timeText = fix != null
        ? '${fix!.timestamp.toLocal().hour}:${fix!.timestamp.toLocal().minute.toString().padLeft(2, '0')}:${fix!.timestamp.toLocal().second.toString().padLeft(2, '0')}'
        : '--:--';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE9EDE8), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with Safe-Zone status badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, color: badgeTextColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: isStale ? const Color(0xFFD97706) : const Color(0xFF78847E),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isStale ? const Color(0xFFD97706) : const Color(0xFF78847E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Metric columns
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.straighten_rounded,
                  label: 'Distance from Home',
                  value: distanceText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  icon: Icons.gps_fixed_rounded,
                  label: 'GPS Accuracy',
                  value: accuracyText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Coordinates
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAF7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current Coordinates',
                  style: TextStyle(fontSize: 11, color: Color(0xFF78847E)),
                ),
                Text(
                  fix != null
                      ? '${fix!.latitude.toStringAsFixed(5)}, ${fix!.longitude.toStringAsFixed(5)}'
                      : 'Searching for GPS...',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1D2C27),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF174D43)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF78847E)),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1D2C27),
          ),
        ),
      ],
    );
  }
}
