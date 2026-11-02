import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/services/service_locator.dart';
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
  Timer? _configRefreshTimer;
  SafeZoneConfig? _config;

  @override
  void initState() {
    super.initState();
    _source = widget.locationSource ?? LocationDataSource().activeSource;
    _configRepo = widget.configRepository ??
        (PatientAppServices.instance.authRepository.isAuthenticated
            ? PatientAppServices.instance.safeZoneConfigRepository
            : MockSafeZoneConfigRepository());

    // Default zone fallback while repo is loading
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

    _reloadConfig();

    _monitor = SafeZoneMonitor(
      locationSource: _source,
      configProvider: () => _config,
      evaluator: widget.evaluator ?? const GeofenceEvaluator(),
      uploader: widget.uploader ??
          (PatientAppServices.instance.authRepository.isAuthenticated
              ? PatientAppServices.instance.locationUploader
              : const NoopLocationUploader()),
    );

    _monitor.start();

    // Periodically re-sync settings from backend so doctor's safe zone changes take effect live
    _configRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _reloadConfig();
    });
  }

  Future<void> _reloadConfig() async {
    try {
      final loadedConfig = await _configRepo.load();
      if (mounted) {
        setState(() {
          _config = loadedConfig;
        });
      }
    } catch (_) {
      // Retain fallback zone if fetch fails
    }
  }

  @override
  void dispose() {
    _configRefreshTimer?.cancel();
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
