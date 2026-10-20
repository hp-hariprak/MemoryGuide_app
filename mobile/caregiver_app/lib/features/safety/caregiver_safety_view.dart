import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/caregiver_service_locator.dart';
import '../../core/services/push_notification_service.dart';
import '../../data/models/caregiver_models.dart';

const _forest = Color(0xFF174D43);
const _mint = Color(0xFFE7F3EC);
const _ink = Color(0xFF1D2C27);
const _muted = Color(0xFF78847E);
const _line = Color(0xFFE9EDE8);
const _red = Color(0xFFDC2626);
const _softRed = Color(0xFFFEF2F2);
const _green = Color(0xFF15803D);
const _softGreen = Color(0xFFE8F5EC);

class CaregiverSafetySection extends StatefulWidget {
  const CaregiverSafetySection({super.key});

  @override
  State<CaregiverSafetySection> createState() => _CaregiverSafetySectionState();
}

class _CaregiverSafetySectionState extends State<CaregiverSafetySection>
    with WidgetsBindingObserver {
  List<LinkedPatient> _patients = [];
  LinkedPatient? _selectedPatient;
  PatientStatus? _patientStatus;
  PatientSettings? _patientSettings;
  List<AlertItem> _alerts = [];

  bool _isLoading = true;
  String? _errorMessage;

  Timer? _pollingTimer;
  StreamSubscription<PushEvent>? _pushSub;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _startPolling();
    _subscribeToPushEvents();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _pushSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      refreshAlerts(silent: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollingTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _selectedPatient != null) {
        refreshAlerts(silent: true);
      }
    });
  }

  void _subscribeToPushEvents() {
    _pushSub = CaregiverServiceLocator.instance.pushNotificationService.events
        .listen((event) {
      if (!mounted) return;

      if (event.source == PushSource.foreground) {
        final patientName = _patients
            .firstWhere(
              (p) => p.patientId == event.patientId,
              orElse: () => _selectedPatient ?? _patients.first,
            )
            .patient
            .fullName;
        final actionText = event.type == 'geofence_exit'
            ? '$patientName left the safe zone!'
            : '$patientName needs help (SOS)!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    actionText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () {
                _selectPatientAndRefresh(event.patientId);
              },
            ),
          ),
        );
      } else {
        _selectPatientAndRefresh(event.patientId);
      }
    });
  }

  void _selectPatientAndRefresh(String patientId) {
    if (patientId.isNotEmpty && _patients.any((p) => p.patientId == patientId)) {
      setState(() {
        _selectedPatient =
            _patients.firstWhere((p) => p.patientId == patientId);
      });
      _loadSelectedPatientDetails(patientId);
    } else {
      refreshAlerts(silent: true);
    }
  }

  Future<void> refreshAlerts({bool silent = true}) async {
    if (_isRefreshing || _selectedPatient == null) return;
    _isRefreshing = true;
    try {
      final repo = CaregiverServiceLocator.instance.caregiverRepository;
      final alerts = await repo.getPatientAlerts(_selectedPatient!.patientId);
      final status = await repo.getPatientStatus(_selectedPatient!.patientId);
      if (mounted) {
        setState(() {
          _alerts = alerts;
          _patientStatus = status;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh alerts: $e')),
        );
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final repo = CaregiverServiceLocator.instance.caregiverRepository;
    try {
      final list = await repo.listLinkedPatients();
      if (!mounted) return;

      _patients = list;
      if (list.isNotEmpty) {
        _selectedPatient = _selectedPatient != null &&
                list.any((p) => p.patientId == _selectedPatient!.patientId)
            ? list.firstWhere((p) => p.patientId == _selectedPatient!.patientId)
            : list.first;

        await _loadSelectedPatientDetails(_selectedPatient!.patientId);
      } else {
        _selectedPatient = null;
        _patientStatus = null;
        _patientSettings = null;
        _alerts = [];
      }
    } catch (e) {
      if (mounted) {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSelectedPatientDetails(String patientId) async {
    final repo = CaregiverServiceLocator.instance.caregiverRepository;
    try {
      final status = await repo.getPatientStatus(patientId);
      final settings = await repo.getPatientSettings(patientId);
      final alerts = await repo.getPatientAlerts(patientId);

      if (mounted) {
        setState(() {
          _patientStatus = status;
          _patientSettings = settings;
          _alerts = alerts;
        });
      }
    } catch (e) {
      if (mounted) {
        _errorMessage = 'Error loading patient status: $e';
      }
    }
  }

  Future<void> _showLinkPatientDialog() async {
    final codeController = TextEditingController();
    String? dialogError;
    bool isLinking = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.link_rounded, color: _forest),
              SizedBox(width: 8),
              Text('Link Patient Account'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter the 8-character link code provided by your patient (visible in their Patient App profile).',
                style: TextStyle(fontSize: 13, color: _muted),
              ),
              const SizedBox(height: 16),
              if (dialogError != null) ...[
                Text(
                  dialogError!,
                  style: const TextStyle(color: _red, fontSize: 13),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Patient Link Code',
                  hintText: 'e.g. DEVLINK1',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLinking ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _forest,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: isLinking
                  ? null
                  : () async {
                      final code = codeController.text.trim();
                      if (code.isEmpty) {
                        setDialogState(() => dialogError = 'Please enter a link code');
                        return;
                      }
                      setDialogState(() {
                        isLinking = true;
                        dialogError = null;
                      });
                      try {
                        await CaregiverServiceLocator
                            .instance.caregiverRepository
                            .linkPatient(code);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _loadData();
                      } catch (e) {
                        setDialogState(() {
                          isLinking = false;
                          dialogError = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: isLinking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Link Patient'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acknowledgeAlert(String alertId) async {
    try {
      await CaregiverServiceLocator.instance.caregiverRepository
          .patchAlert(alertId, 'acknowledged');
      if (_selectedPatient != null) {
        _loadSelectedPatientDetails(_selectedPatient!.patientId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to acknowledge alert: $e')),
        );
      }
    }
  }

  Future<void> _resolveAlert(String alertId) async {
    try {
      await CaregiverServiceLocator.instance.caregiverRepository
          .patchAlert(alertId, 'resolved');
      if (_selectedPatient != null) {
        _loadSelectedPatientDetails(_selectedPatient!.patientId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve alert: $e')),
        );
      }
    }
  }

  Future<void> _openSafeZoneDialog() async {
    if (_selectedPatient == null || _patientSettings == null) return;

    final latController = TextEditingController(
      text: _patientSettings!.safeZoneLatitude?.toString() ?? '12.9716',
    );
    final lngController = TextEditingController(
      text: _patientSettings!.safeZoneLongitude?.toString() ?? '77.5946',
    );
    double radius = _patientSettings!.safeZoneRadiusMeters.clamp(50.0, 5000.0);
    bool safeZoneEnabled = _patientSettings!.safeZoneEnabled;
    bool geofenceAlertsEnabled = _patientSettings!.geofenceAlertsEnabled;
    bool isSaving = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: _forest),
              SizedBox(width: 8),
              Text('Safe Zone Configuration'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dialogError != null) ...[
                  Text(dialogError!, style: const TextStyle(color: _red)),
                  const SizedBox(height: 8),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Safe Zone',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Monitors whether patient stays in zone',
                      style: TextStyle(fontSize: 12)),
                  value: safeZoneEnabled,
                  activeTrackColor: _forest,
                  onChanged: (val) =>
                      setDialogState(() => safeZoneEnabled = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Geofence Exit Alerts',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Receive notifications on zone exit',
                      style: TextStyle(fontSize: 12)),
                  value: geofenceAlertsEnabled,
                  activeTrackColor: _forest,
                  onChanged: (val) =>
                      setDialogState(() => geofenceAlertsEnabled = val),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: latController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Safe Zone Center Latitude',
                    hintText: 'e.g. 12.9716',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lngController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Safe Zone Center Longitude',
                    hintText: 'e.g. 77.5946',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Safe Radius:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('${radius.toInt()} meters',
                        style: const TextStyle(
                            color: _forest, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: radius,
                  min: 50.0,
                  max: 2000.0,
                  divisions: 39,
                  activeColor: _forest,
                  onChanged: (val) => setDialogState(() => radius = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _forest,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      final lat = double.tryParse(latController.text.trim());
                      final lng = double.tryParse(lngController.text.trim());
                      if (lat == null || lng == null) {
                        setDialogState(() =>
                            dialogError = 'Please enter valid numerical coordinates');
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      try {
                        await CaregiverServiceLocator
                            .instance.caregiverRepository
                            .updatePatientSettings(_selectedPatient!.patientId, {
                          'safe_zone_enabled': safeZoneEnabled,
                          'geofence_alerts_enabled': geofenceAlertsEnabled,
                          'safe_zone_latitude': lat,
                          'safe_zone_longitude': lng,
                          'safe_zone_radius_meters': radius,
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _loadSelectedPatientDetails(
                            _selectedPatient!.patientId);
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError =
                              e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLandmarksDialog() async {
    if (_selectedPatient == null) return;
    final repo = CaregiverServiceLocator.instance.caregiverRepository;
    List<LandmarkItem> landmarks = [];
    bool isLoading = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoading) {
            repo.getLandmarks(_selectedPatient!.patientId).then((items) {
              setDialogState(() {
                landmarks = items;
                isLoading = false;
              });
            }).catchError((_) {
              setDialogState(() => isLoading = false);
            });
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.place_rounded, color: _forest),
                    SizedBox(width: 8),
                    Text('Patient Landmarks'),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: _forest),
                  tooltip: 'Add Landmark',
                  onPressed: () async {
                    final nameCtrl = TextEditingController();
                    final latCtrl = TextEditingController(
                        text: _patientStatus?.latitude?.toString() ?? '12.9716');
                    final lngCtrl = TextEditingController(
                        text: _patientStatus?.longitude?.toString() ?? '77.5946');
                    final descCtrl = TextEditingController();

                    final added = await showDialog<bool>(
                      context: ctx,
                      builder: (addCtx) => AlertDialog(
                        title: const Text('Add Landmark'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(labelText: 'Name (e.g. Home, Park)'),
                            ),
                            TextField(
                              controller: latCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Latitude'),
                            ),
                            TextField(
                              controller: lngCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Longitude'),
                            ),
                            TextField(
                              controller: descCtrl,
                              decoration: const InputDecoration(labelText: 'Description (optional)'),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(addCtx, false), child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: _forest, foregroundColor: Colors.white),
                            onPressed: () async {
                              final lat = double.tryParse(latCtrl.text);
                              final lng = double.tryParse(lngCtrl.text);
                              if (nameCtrl.text.trim().isNotEmpty && lat != null && lng != null) {
                                await repo.createLandmark(
                                  patientId: _selectedPatient!.patientId,
                                  name: nameCtrl.text.trim(),
                                  latitude: lat,
                                  longitude: lng,
                                  description: descCtrl.text.trim(),
                                );
                                if (addCtx.mounted) Navigator.pop(addCtx, true);
                              }
                            },
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    );
                    if (added == true) {
                      setDialogState(() => isLoading = true);
                    }
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              height: 300,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: _forest))
                  : landmarks.isEmpty
                      ? const Center(
                          child: Text('No landmarks registered for this patient.',
                              style: TextStyle(color: _muted)),
                        )
                      : ListView.separated(
                          itemCount: landmarks.length,
                          separatorBuilder: (context, index) => const Divider(color: _line),
                          itemBuilder: (context, index) {
                            final lm = landmarks[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _mint,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.location_on, color: _forest, size: 20),
                              ),
                              title: Text(lm.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(
                                '${lm.latitude.toStringAsFixed(4)}, ${lm.longitude.toStringAsFixed(4)}'
                                '${lm.description != null ? ' · ${lm.description}' : ''}',
                                style: const TextStyle(fontSize: 12, color: _muted),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: _red, size: 20),
                                tooltip: 'Delete landmark',
                                onPressed: () async {
                                  await repo.deleteLandmark(_selectedPatient!.patientId, lm.id);
                                  setDialogState(() => isLoading = true);
                                },
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: CircularProgressIndicator(color: _forest),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Linked Patient Selector Bar
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _line),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 360;
                final dropdown = _patients.isEmpty
                    ? const Text(
                        'No patients linked yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<LinkedPatient>(
                          value: _selectedPatient,
                          isExpanded: true,
                          items: _patients.map((p) {
                            return DropdownMenuItem<LinkedPatient>(
                              value: p,
                              child: Text(
                                '${p.patient.fullName} (${p.patient.email})',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: _ink,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (p) {
                            if (p != null) {
                              setState(() => _selectedPatient = p);
                              _loadSelectedPatientDetails(p.patientId);
                            }
                          },
                        ),
                      );

                final linkButton = TextButton.icon(
                  onPressed: _showLinkPatientDialog,
                  icon: const Icon(Icons.add_link, size: 18),
                  label: const Text('Link Patient'),
                  style: TextButton.styleFrom(
                    foregroundColor: _forest,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.supervised_user_circle_rounded,
                              color: _forest, size: 24),
                          const SizedBox(width: 8),
                          Expanded(child: dropdown),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: linkButton,
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    const Icon(Icons.supervised_user_circle_rounded,
                        color: _forest, size: 26),
                    const SizedBox(width: 12),
                    Expanded(child: dropdown),
                    linkButton,
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),

        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _softRed,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Text(_errorMessage!,
                style: const TextStyle(color: _red, fontSize: 13)),
          ),
          const SizedBox(height: 14),
        ],

        if (_selectedPatient == null)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: _line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  const Icon(Icons.link_off_rounded, size: 48, color: _muted),
                  const SizedBox(height: 12),
                  const Text(
                    'No Linked Patients',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _ink),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'To monitor safety and safe-zones, ask your patient for their Link Code and click Link Patient above.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _forest,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _showLinkPatientDialog,
                    icon: const Icon(Icons.add_link),
                    label: const Text('Link a Patient Now'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          // 2. Patient Live Location & Geofence Status Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: _line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _mint,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.location_on_rounded,
                                color: _forest, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_selectedPatient!.patient.fullName}’s Safety Status',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _ink,
                                ),
                              ),
                              Text(
                                _patientStatus?.recordedAt != null
                                    ? 'Updated ${_patientStatus!.recordedAt!.hour}:${_patientStatus!.recordedAt!.minute.toString().padLeft(2, '0')}'
                                    : 'Awaiting location signal',
                                style: const TextStyle(
                                    fontSize: 12, color: _muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Safe-Zone Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _patientStatus?.insideSafeZone == true
                              ? _softGreen
                              : _patientStatus?.insideSafeZone == false
                                  ? _softRed
                                  : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _patientStatus?.insideSafeZone == true
                                ? const Color(0xFFBBF7D0)
                                : _patientStatus?.insideSafeZone == false
                                    ? const Color(0xFFFECACA)
                                    : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _patientStatus?.insideSafeZone == true
                                  ? Icons.check_circle_rounded
                                  : _patientStatus?.insideSafeZone == false
                                      ? Icons.warning_rounded
                                      : Icons.gps_not_fixed_rounded,
                              size: 16,
                              color: _patientStatus?.insideSafeZone == true
                                  ? _green
                                  : _patientStatus?.insideSafeZone == false
                                      ? _red
                                      : _muted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _patientStatus?.insideSafeZone == true
                                  ? 'Inside Safe Zone'
                                  : _patientStatus?.insideSafeZone == false
                                      ? 'Outside Safe Zone'
                                      : 'Locating...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _patientStatus?.insideSafeZone == true
                                    ? _green
                                    : _patientStatus?.insideSafeZone == false
                                        ? _red
                                        : _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Location details & Geofence Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAF7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _line),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.my_location_rounded,
                                size: 18, color: _forest),
                            const SizedBox(width: 8),
                            const Text('Current Coordinates: ',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(
                              _patientStatus?.latitude != null &&
                                      _patientStatus?.longitude != null
                                  ? '${_patientStatus!.latitude!.toStringAsFixed(5)}, ${_patientStatus!.longitude!.toStringAsFixed(5)}'
                                  : 'No GPS fix yet',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _ink),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.radar_rounded,
                                size: 18, color: _forest),
                            const SizedBox(width: 8),
                            const Text('Safe Zone Boundary: ',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(
                              _patientSettings?.safeZoneEnabled == true
                                  ? 'Active · ${_patientSettings!.safeZoneRadiusMeters.toInt()}m radius'
                                  : 'Not Enabled',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _patientSettings?.safeZoneEnabled == true
                                    ? _green
                                    : _muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quick Action Buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _forest,
                          side: const BorderSide(color: _line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Configure Safe Zone'),
                        onPressed: _openSafeZoneDialog,
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _forest,
                          side: const BorderSide(color: _line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.place_outlined, size: 18),
                        label: const Text('Landmarks'),
                        onPressed: _openLandmarksDialog,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: _forest),
                        tooltip: 'Refresh Status',
                        onPressed: () => _loadSelectedPatientDetails(
                            _selectedPatient!.patientId),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Live Safety Alerts Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: _line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.notifications_active_rounded,
                              color: _forest, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Active Safety & Help Alerts',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                      if (_alerts.where((a) => a.status != 'resolved').isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _softRed,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_alerts.where((a) => a.status != 'resolved').length} Open',
                            style: const TextStyle(
                              color: _red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (_alerts.where((a) => a.status != 'resolved').isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _softGreen,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_rounded, color: _green, size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'All Clear · No active emergency help requests or geofence violations.',
                              style: TextStyle(
                                color: _green,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _alerts.where((a) => a.status != 'resolved').length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final alert = _alerts
                            .where((a) => a.status != 'resolved')
                            .toList()[index];
                        final isHelp = alert.alertType == 'help_request';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isHelp ? _softRed : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isHelp
                                  ? const Color(0xFFFECACA)
                                  : const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isHelp
                                        ? Icons.emergency_rounded
                                        : Icons.warning_amber_rounded,
                                    color: isHelp
                                        ? _red
                                        : const Color(0xFFD97706),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isHelp
                                        ? 'SOS Emergency Help Request'
                                        : 'Geofence Safe Zone Exit',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isHelp
                                          ? _red
                                          : const Color(0xFF92400E),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      alert.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: alert.status == 'acknowledged'
                                            ? _forest
                                            : _red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (alert.message != null &&
                                  alert.message!.isNotEmpty)
                                Text(
                                  'Message: "${alert.message}"',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic),
                                ),
                              Text(
                                'Time: ${alert.createdAt.hour}:${alert.createdAt.minute.toString().padLeft(2, '0')}'
                                '${alert.latitude != null ? ' · At (${alert.latitude!.toStringAsFixed(4)}, ${alert.longitude!.toStringAsFixed(4)})' : ''}',
                                style: const TextStyle(
                                    fontSize: 12, color: _muted),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (alert.status == 'open')
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _forest,
                                        side: const BorderSide(color: _forest),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      onPressed: () =>
                                          _acknowledgeAlert(alert.id),
                                      child: const Text('Acknowledge',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _forest,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () => _resolveAlert(alert.id),
                                    child: const Text('Resolve Alert',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
