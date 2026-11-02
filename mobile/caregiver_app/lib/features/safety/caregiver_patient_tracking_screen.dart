import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/services/caregiver_service_locator.dart';
import '../../data/models/caregiver_models.dart';
import 'interactive_map.dart';

const _forest = Color(0xFF174D43);
const _ink = Color(0xFF1D2C27);
const _muted = Color(0xFF78847E);
const _line = Color(0xFFE9EDE8);

/// Full-screen live patient tracking screen for caregivers.
class CaregiverPatientTrackingScreen extends StatefulWidget {
  final LinkedPatient patient;
  final PatientSettings? settings;
  final double? targetLatitude;
  final double? targetLongitude;

  const CaregiverPatientTrackingScreen({
    super.key,
    required this.patient,
    this.settings,
    this.targetLatitude,
    this.targetLongitude,
  });

  @override
  State<CaregiverPatientTrackingScreen> createState() =>
      _CaregiverPatientTrackingScreenState();
}

class _CaregiverPatientTrackingScreenState
    extends State<CaregiverPatientTrackingScreen> {
  PatientStatus? _status;
  PatientSettings? _settings;
  final List<MapCoordinate> _trail = [];
  Timer? _pollingTimer;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _loadData();
    // Poll patient location every 4 seconds while screen is open for real-time tracking
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _refreshStatus();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final repo = CaregiverServiceLocator.instance.caregiverRepository;
    try {
      final status = await repo.getPatientStatus(widget.patient.patientId);
      final settings = _settings ??
          await repo.getPatientSettings(widget.patient.patientId);

      if (mounted) {
        setState(() {
          _status = status;
          _settings = settings;
          _isLoading = false;

          if (status.latitude != null && status.longitude != null) {
            final coord = MapCoordinate(status.latitude!, status.longitude!);
            if (_trail.isEmpty || _trail.last != coord) {
              _trail.add(coord);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshStatus() async {
    final repo = CaregiverServiceLocator.instance.caregiverRepository;
    try {
      final status = await repo.getPatientStatus(widget.patient.patientId);
      final settings = await repo.getPatientSettings(widget.patient.patientId);
      if (mounted) {
        setState(() {
          _status = status;
          _settings = settings;
          if (status.latitude != null && status.longitude != null) {
            final coord = MapCoordinate(status.latitude!, status.longitude!);
            if (_trail.isEmpty || _trail.last != coord) {
              _trail.add(coord);
              if (_trail.length > 30) _trail.removeAt(0);
            }
          }
        });
      }
    } catch (_) {}
  }

  GeofenceVisualState _computeVisualState(double? distanceMeters) {
    if (_status == null || _status!.latitude == null) {
      return GeofenceVisualState.inactive;
    }
    if (_status!.insideSafeZone == true) {
      return GeofenceVisualState.inside;
    }
    if (_status!.insideSafeZone == false) {
      return GeofenceVisualState.outside;
    }
    if (distanceMeters != null) {
      final radius = _settings?.safeZoneRadiusMeters ?? 200.0;
      final acc = _status?.accuracyMeters ?? 0.0;
      if (distanceMeters + acc <= radius) {
        return GeofenceVisualState.inside;
      }
      if (distanceMeters - acc > radius) {
        return GeofenceVisualState.outside;
      }
    }
    return GeofenceVisualState.uncertain;
  }

  @override
  Widget build(BuildContext context) {
    final homeLat = _settings?.safeZoneLatitude ?? 11.03000;
    final homeLon = _settings?.safeZoneLongitude ?? 77.00600;
    final homeCoord = MapCoordinate(homeLat, homeLon);

    final patientCoord = (_status?.latitude != null && _status?.longitude != null)
        ? MapCoordinate(_status!.latitude!, _status!.longitude!)
        : (widget.targetLatitude != null && widget.targetLongitude != null)
            ? MapCoordinate(widget.targetLatitude!, widget.targetLongitude!)
            : null;

    final initialCenter = patientCoord ?? homeCoord;

    double? distanceMeters;
    if (patientCoord != null) {
      distanceMeters = Geolocator.distanceBetween(
        homeCoord.latitude,
        homeCoord.longitude,
        patientCoord.latitude,
        patientCoord.longitude,
      );
    }

    final String distanceDisplay;
    if (patientCoord == null) {
      distanceDisplay = 'Waiting for patient GPS';
    } else if (distanceMeters != null) {
      distanceDisplay = distanceMeters < 1000
          ? '${distanceMeters.toStringAsFixed(0)} m'
          : '${(distanceMeters / 1000).toStringAsFixed(2)} km';
    } else {
      distanceDisplay = 'Waiting for patient GPS';
    }

    final visualState = _computeVisualState(distanceMeters);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Live Tracking · ${widget.patient.patient.fullName}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _forest),
            tooltip: 'Refresh Location',
            onPressed: () {
              setState(() => _isLoading = true);
              _refreshStatus().whenComplete(() {
                if (mounted) setState(() => _isLoading = false);
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Full Map
          MemoryGuideInteractiveMap(
            initialCenter: initialCenter,
            initialZoom: 16.5,
            homeLocation: homeCoord,
            safeZoneRadiusMeters: _settings?.safeZoneRadiusMeters ?? 200.0,
            patientLocation: patientCoord,
            patientAccuracyMeters: _status?.accuracyMeters,
            movementTrail: _trail,
            visualState: visualState,
            isEditable: false,
          ),

          // 2. Loading / Error
          if (_isLoading)
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                          strokeWidth: 2, color: _forest),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Fetching latest GPS signal...',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else if (_errorMessage != null)
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE8E8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF05252)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFE02424), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9B1C1C)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3. Bottom Status Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
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
                border: Border.all(color: _line, width: 1.2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _status?.insideSafeZone == true
                              ? const Color(0xFFE8F5EC)
                              : _status?.insideSafeZone == false
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _status?.insideSafeZone == true
                                  ? Icons.check_circle_rounded
                                  : _status?.insideSafeZone == false
                                      ? Icons.warning_rounded
                                      : Icons.gps_not_fixed_rounded,
                              size: 16,
                              color: _status?.insideSafeZone == true
                                  ? const Color(0xFF15803D)
                                  : _status?.insideSafeZone == false
                                      ? const Color(0xFFDC2626)
                                      : _muted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _status?.insideSafeZone == true
                                  ? 'Inside Safe Zone'
                                  : _status?.insideSafeZone == false
                                      ? 'Outside Safe Zone'
                                      : 'Locating...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _status?.insideSafeZone == true
                                    ? const Color(0xFF15803D)
                                    : _status?.insideSafeZone == false
                                        ? const Color(0xFFDC2626)
                                        : _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _status?.recordedAt != null
                            ? 'Updated ${_status!.recordedAt!.toLocal().hour}:${_status!.recordedAt!.toLocal().minute.toString().padLeft(2, '0')}'
                            : 'Awaiting signal',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Distance & Accuracy Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.straighten_rounded,
                                    size: 14, color: _forest),
                                SizedBox(width: 4),
                                Text('Distance from Home',
                                    style: TextStyle(
                                        fontSize: 11, color: _muted)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              distanceDisplay,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _ink),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.gps_fixed_rounded,
                                    size: 14, color: _forest),
                                SizedBox(width: 4),
                                Text('GPS Accuracy',
                                    style: TextStyle(
                                        fontSize: 11, color: _muted)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _status?.accuracyMeters != null
                                  ? '±${_status!.accuracyMeters!.toStringAsFixed(1)} m'
                                  : 'Standard accuracy',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _ink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Coordinates Row
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAF7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Latest Coordinates',
                            style: TextStyle(fontSize: 11, color: _muted)),
                        Text(
                          _status?.latitude != null &&
                                  _status?.longitude != null
                              ? '${_status!.latitude!.toStringAsFixed(5)}, ${_status!.longitude!.toStringAsFixed(5)}'
                              : 'No GPS fix yet',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
