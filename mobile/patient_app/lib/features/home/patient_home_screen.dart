import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/errors/failures.dart';
import '../../core/services/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/liquid_glass.dart';
import '../../core/utils/location_helper.dart';
import '../../data/models/safe_zone_state.dart';
import '../help/emergency_sos_button.dart';
import '../profile/patient_profile_screen.dart';
import '../safe_zones/safe_zone_banner.dart';
import 'caregiver_contact_card.dart';
import 'familiar_voice_card.dart';
import 'orientation_header.dart';

class PatientHomeScreen extends StatefulWidget {
  final SafeZoneInfo? safeZoneInfo;

  /// Controls visibility of developer preview controls.
  /// Defaults to [kDebugMode], hiding simulator tools in production builds.
  final bool isDevMode;

  const PatientHomeScreen({
    super.key,
    this.safeZoneInfo,
    this.isDevMode = kDebugMode,
  });

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  late SafeZoneInfo _currentSafeZoneInfo;
  bool _showSimulator = false;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _currentSafeZoneInfo = widget.safeZoneInfo ??
        const SafeZoneInfo(
          status: SafeZoneStatus.inside,
          zoneName: 'Home (Maple Street)',
        );

    _initPatientData();
  }

  void _initPatientData() {
    final auth = PatientAppServices.instance.authRepository;
    if (auth.isAuthenticated) {
      _loadStatus();
      _startPeriodicLocationReporting();
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await PatientAppServices.instance.patientRepository.fetchStatus();
      if (!mounted) return;

      SafeZoneStatus calculatedStatus = SafeZoneStatus.locating;
      if (status.insideSafeZone == true) {
        calculatedStatus = SafeZoneStatus.inside;
      } else if (status.insideSafeZone == false) {
        calculatedStatus = SafeZoneStatus.outside;
      }

      setState(() {
        _currentSafeZoneInfo = SafeZoneInfo(
          status: calculatedStatus,
          zoneName: 'Configured Safe Zone',
          lastUpdated: DateTime.now(),
        );
      });
    } catch (_) {
      // Keep existing status if server unreachable
    }
  }

  void _startPeriodicLocationReporting() {
    _locationTimer?.cancel();
    // Periodically post device GPS location every 60 seconds if authenticated
    _locationTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      final auth = PatientAppServices.instance.authRepository;
      if (!auth.isAuthenticated || !mounted) return;
      try {
        final position = await LocationHelper.getCurrentPosition();
        if (position != null) {
          await PatientAppServices.instance.patientRepository.recordLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            altitudeMeters: position.altitude,
            speedMps: position.speed,
            headingDegrees: position.heading,
          );
          _loadStatus();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PatientHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.safeZoneInfo != null &&
        widget.safeZoneInfo != oldWidget.safeZoneInfo) {
      _currentSafeZoneInfo = widget.safeZoneInfo!;
    }
  }

  void _setStatus(SafeZoneStatus status, [String? zoneName]) {
    setState(() {
      _currentSafeZoneInfo = SafeZoneInfo(
        status: status,
        zoneName: zoneName,
        lastUpdated: DateTime.now(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = PatientAppServices.instance.authRepository;
    final patientName = auth.currentUser?.fullName.isNotEmpty == true
        ? auth.currentUser!.fullName.split(' ').first
        : 'Arthur';
    final linkCode = auth.currentUser?.linkCode;

    return Scaffold(
      extendBodyBehindAppBar: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_rounded,
              color: PatientAppTheme.primaryBlue,
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              'MemoryGuide',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: PatientAppTheme.deepNavy,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.75),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            height: 1.0,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 1.2,
                ),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: PatientAppTheme.deepNavy,
                size: 20,
              ),
            ),
            tooltip: 'My Profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PatientProfileScreen(),
                ),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
          ),
          if (widget.isDevMode)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                tooltip: 'Toggle Demo Simulator',
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _showSimulator
                        ? const Color(0xFFEFF6FF)
                        : Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _showSimulator
                          ? const Color(0xFFBFDBFE)
                          : Colors.white.withValues(alpha: 0.9),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _showSimulator ? Icons.tune_rounded : Icons.tune_outlined,
                    size: 20,
                    color: _showSimulator
                        ? PatientAppTheme.primaryBlue
                        : PatientAppTheme.secondaryText,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _showSimulator = !_showSimulator;
                  });
                },
              ),
            ),
        ],
      ),
      body: GlassAtmosphere(
        isDark: false,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 18.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 580),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Time and Day orientation greeting (Open typography hero)
                          OrientationHeader(patientName: patientName),
                          const SizedBox(height: 14),

                          // Link Code banner if user is authenticated
                          if (linkCode != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2563EB).withValues(alpha: 0.06),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFFBFDBFE),
                                            width: 1,
                                          ),
                                        ),
                                        child: const Icon(Icons.link_rounded,
                                            color: PatientAppTheme.primaryBlue,
                                            size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'CAREGIVER LINK CODE',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.8,
                                                color: PatientAppTheme.primaryBlue,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              linkCode,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.5,
                                                color: PatientAppTheme.deepNavy,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const PatientProfileScreen(),
                                            ),
                                          );
                                        },
                                        child: const Text('View Code'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        // 2. Safe Zone primary status hero card
                        SafeZoneBanner(info: _currentSafeZoneInfo),
                        const SizedBox(height: 24),

                        // 3. Trusted Support section heading
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.people_outline_rounded,
                                size: 16,
                                color: PatientAppTheme.secondaryText,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'TRUSTED SUPPORT',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: PatientAppTheme.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Caregiver Quick Connect
                        const CaregiverContactCard(
                          caregiverName: 'Sarah',
                          relationship: 'Daughter',
                          phoneNumber: '(555) 234-5678',
                        ),
                        const SizedBox(height: 14),

                        // Familiar Voice reassuring message
                        const FamiliarVoiceCard(),
                        const SizedBox(height: 26),

                        // 4. Grounded Emergency Help Zone
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFFECACA),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFDC2626)
                                    .withValues(alpha: 0.05),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.emergency_outlined,
                                    color: PatientAppTheme.helpRed,
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'EMERGENCY ASSISTANCE',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                      color: PatientAppTheme.helpRed,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Press below at any time if you feel lost or need immediate help.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: PatientAppTheme.secondaryText,
                                ),
                              ),
                              const SizedBox(height: 18),
                              EmergencySosButton(
                                isDemoMode: !auth.isAuthenticated,
                                onTriggered: () async {
                                  if (auth.isAuthenticated) {
                                    dynamic position;
                                    try {
                                      position = await LocationHelper
                                          .getCurrentPosition();
                                    } catch (_) {}
                                    try {
                                      await PatientAppServices
                                          .instance.patientRepository
                                          .triggerHelp(
                                        latitude: position?.latitude,
                                        longitude: position?.longitude,
                                      );
                                    } on ApiException catch (e) {
                                      if (e.code == 'DUPLICATE_HELP_REQUEST') {
                                        // An alert is already open on the server; treat as dispatched
                                        return;
                                      }
                                      rethrow;
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Demo status simulator panel for previewing different safe zone states
            if (widget.isDevMode && _showSimulator) _buildSimulatorBar(),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildSimulatorBar() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF172033).withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🧪 Live Status Simulator',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: PatientAppTheme.primaryText,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showSimulator = false),
                        child: const Icon(Icons.close,
                            size: 18, color: PatientAppTheme.secondaryText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Inside Home', SafeZoneStatus.inside,
                            'Home (Maple Street)'),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'Outside Zone', SafeZoneStatus.outside, null),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'Locating GPS', SafeZoneStatus.locating, null),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'Location Paused', SafeZoneStatus.unavailable, null),
                        const SizedBox(width: 8),
                        _buildFilterChip('Signal Delayed', SafeZoneStatus.stale,
                            'Home (Maple Street)'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      String label, SafeZoneStatus status, String? zoneName) {
    final isSelected = _currentSafeZoneInfo.effectiveStatus == status;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? PatientAppTheme.primaryBlue
              : PatientAppTheme.primaryText,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFFEFF6FF),
      backgroundColor: Colors.white,
      side: BorderSide(
        color:
            isSelected ? PatientAppTheme.primaryBlue : PatientAppTheme.borders,
      ),
      onSelected: (_) => _setStatus(status, zoneName),
    );
  }
}
