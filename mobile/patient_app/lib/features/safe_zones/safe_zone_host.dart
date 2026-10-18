import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/datasources/location_datasource.dart';
import '../../data/models/safe_zone_config.dart';
import '../../data/models/safe_zone_state.dart';
import '../../data/repositories/safe_zone_config_repository.dart';
import '../../data/services/location_uploader.dart';
import '../home/patient_home_screen.dart';
import 'geofence_evaluator.dart';
import 'safe_zone_monitor.dart';

/// Integration host widget for Member 1's [PatientHomeScreen].
///
/// Owns and manages the lifecycle of [SafeZoneMonitor], automatically streaming
/// evaluated [SafeZoneInfo] into the home screen via [ValueListenableBuilder].
class SafeZoneHost extends StatefulWidget {
  final LocationSource? locationSource;
  final SafeZoneConfigRepository? configRepository;
  final GeofenceEvaluator? evaluator;
  final LocationUploader? uploader;
  final bool isDevMode;

  const SafeZoneHost({
    super.key,
    this.locationSource,
    this.configRepository,
    this.evaluator,
    this.uploader,
    this.isDevMode = kDebugMode,
  });

  @override
  State<SafeZoneHost> createState() => _SafeZoneHostState();
}

class _SafeZoneHostState extends State<SafeZoneHost> {
  late final LocationSource _source;
  late final SafeZoneConfigRepository _configRepo;
  late final SafeZoneMonitor _monitor;
  SafeZoneConfig? _config;

  @override
  void initState() {
    super.initState();
    _source = widget.locationSource ?? LocationDataSource().activeSource;
    _configRepo = widget.configRepository ?? MockSafeZoneConfigRepository();

    // Default demo zone if repo is loading or async
    _config = const SafeZoneConfig(
      enabled: true,
      latitude: 12.9716,
      longitude: 77.5946,
      radiusMeters: 150,
      name: 'Home (Maple Street)',
      locationIntervalSeconds: 30,
      trackingEnabled: true,
      geofenceAlertsEnabled: true,
    );

    _configRepo.load().then((loadedConfig) {
      if (mounted) {
        setState(() {
          _config = loadedConfig;
        });
      }
    }).catchError((_) {
      // Retain fallback demo zone if fetch fails
    });

    _monitor = SafeZoneMonitor(
      locationSource: _source,
      configProvider: () => _config,
      evaluator: widget.evaluator ?? const GeofenceEvaluator(),
      uploader: widget.uploader ?? const NoopLocationUploader(),
    );

    _monitor.start();
  }

  @override
  void dispose() {
    _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SafeZoneInfo>(
      valueListenable: _monitor,
      builder: (context, info, _) {
        return PatientHomeScreen(
          safeZoneInfo: info,
          isDevMode: widget.isDevMode,
        );
      },
    );
  }
}
