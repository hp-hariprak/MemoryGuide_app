import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/services/caregiver_service_locator.dart';
import '../../data/models/caregiver_models.dart';
import 'interactive_map.dart';

const _forest = Color(0xFF174D43);
const _ink = Color(0xFF1D2C27);
const _muted = Color(0xFF78847E);
const _line = Color(0xFFE9EDE8);
const _red = Color(0xFFDC2626);

/// Complete Safe-Zone & Home Location Configuration Screen.
/// Provides interactive map, address search, map-tap/draggable pin,
/// "Use my current location" with explicit confirmation, radius slider,
/// numeric radius input in meters, immediate circle update, and backend synchronization.
class SafeZoneConfigScreen extends StatefulWidget {
  final LinkedPatient patient;
  final PatientSettings initialSettings;

  const SafeZoneConfigScreen({
    super.key,
    required this.patient,
    required this.initialSettings,
  });

  @override
  State<SafeZoneConfigScreen> createState() => _SafeZoneConfigScreenState();
}

class _SafeZoneConfigScreenState extends State<SafeZoneConfigScreen> {
  late double _homeLat;
  late double _homeLon;
  late double _radiusMeters;
  late bool _safeZoneEnabled;
  late bool _geofenceAlertsEnabled;

  final TextEditingController _radiusInputController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _homeLat = widget.initialSettings.safeZoneLatitude ?? 12.9716;
    _homeLon = widget.initialSettings.safeZoneLongitude ?? 77.5946;
    _radiusMeters = widget.initialSettings.safeZoneRadiusMeters.clamp(50.0, 5000.0);
    _safeZoneEnabled = widget.initialSettings.safeZoneEnabled;
    _geofenceAlertsEnabled = widget.initialSettings.geofenceAlertsEnabled;
    _radiusInputController.text = _radiusMeters.toInt().toString();
  }

  @override
  void dispose() {
    _radiusInputController.dispose();
    super.dispose();
  }

  void _onLocationSelected(MapCoordinate coord) {
    setState(() {
      _homeLat = coord.latitude;
      _homeLon = coord.longitude;
    });
  }

  void _onRadiusSliderChanged(double value) {
    setState(() {
      _radiusMeters = value;
      _radiusInputController.text = value.toInt().toString();
    });
  }

  void _onRadiusInputChanged(String text) {
    final parsed = double.tryParse(text.trim());
    if (parsed != null && parsed >= 50.0 && parsed <= 5000.0) {
      setState(() {
        _radiusMeters = parsed;
      });
    }
  }

  Future<void> _requestUseCurrentLocation() async {
    // Show explicit confirmation dialog as required by master prompt
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.my_location_rounded, color: _forest),
            SizedBox(width: 8),
            Text('Use Current Location?'),
          ],
        ),
        content: const Text(
          'Do you want to set your phone’s current GPS coordinates as the patient’s home location?\n\nPlease confirm only if you are currently at the patient’s home.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Location'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device location services are disabled. Please enable GPS in settings.'),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission permanently denied. Open app settings to enable.'),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _homeLat = position.latitude;
        _homeLon = position.longitude;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _forest,
            content: Text(
              'Home location updated to (${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not obtain current location: $e')),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final repo = CaregiverServiceLocator.instance.caregiverRepository;
      await repo.updatePatientSettings(widget.patient.patientId, {
        'safe_zone_enabled': _safeZoneEnabled,
        'geofence_alerts_enabled': _geofenceAlertsEnabled,
        'safe_zone_latitude': _homeLat,
        'safe_zone_longitude': _homeLon,
        'safe_zone_radius_meters': _radiusMeters.toInt(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF15803D),
          content: Text('Safe zone configuration saved successfully!'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeCoord = MapCoordinate(_homeLat, _homeLon);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Safe Zone · ${widget.patient.patient.fullName}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _forest),
                    )
                  : const Icon(Icons.check_circle_outline, color: _forest),
              label: const Text(
                'Save',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: _forest, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Interactive Map Area (Top 55% of screen)
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                MemoryGuideInteractiveMap(
                  initialCenter: homeCoord,
                  initialZoom: 16.0,
                  homeLocation: homeCoord,
                  safeZoneRadiusMeters: _radiusMeters,
                  visualState: GeofenceVisualState.inside,
                  isEditable: true,
                  onLocationSelected: _onLocationSelected,
                  onUseCurrentLocationRequested: _requestUseCurrentLocation,
                ),
                // Helper overlay pill
                Positioned(
                  top: 70,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_outlined,
                            size: 15, color: _forest),
                        SizedBox(width: 5),
                        Text(
                          'Tap map or search to place Home marker',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Control Panel (Bottom 45%)
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: _red, fontSize: 12),
                        ),
                      ),
                    ],

                    // Coordinates display row
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAF7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _line),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.home_outlined,
                              size: 20, color: _forest),
                          const SizedBox(width: 8),
                          const Text('Home Coordinates:',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(
                            '${_homeLat.toStringAsFixed(5)}, ${_homeLon.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _forest,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Radius control row with numeric input and slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Safe-Zone Radius:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 70,
                              height: 36,
                              child: TextField(
                                controller: _radiusInputController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                                decoration: InputDecoration(
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onChanged: _onRadiusInputChanged,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('metres',
                                style: TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                    Slider(
                      value: _radiusMeters,
                      min: 50.0,
                      max: 2000.0,
                      divisions: 39,
                      activeColor: _forest,
                      onChanged: _onRadiusSliderChanged,
                    ),

                    // Toggles: Enable Safe Zone & Geofence Alerts
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Safe Zone Active',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                            value: _safeZoneEnabled,
                            activeTrackColor: _forest,
                            onChanged: (val) =>
                                setState(() => _safeZoneEnabled = val),
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Exit Alerts',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                            value: _geofenceAlertsEnabled,
                            activeTrackColor: _forest,
                            onChanged: (val) =>
                                setState(() => _geofenceAlertsEnabled = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Primary Save Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _forest,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isSaving ? null : _saveSettings,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Safe Zone & Perimeter',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
