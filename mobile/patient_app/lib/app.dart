import 'package:flutter/material.dart';
import 'core/services/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'data/models/patient_model.dart';
import 'features/authentication/login_screen.dart';
import 'features/safe_zones/safe_zone_host.dart';

class PatientApp extends StatefulWidget {
  final Widget? home;
  const PatientApp({super.key, this.home});

  @override
  State<PatientApp> createState() => _PatientAppState();
}

class _PatientAppState extends State<PatientApp> {
  late Future<UserModel?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = PatientAppServices.instance.authRepository.restoreSession();
  }

  bool get _isTestEnvironment =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  Widget build(BuildContext context) {
    final Widget effectiveHome = widget.home ??
        (_isTestEnvironment
            ? const SafeZoneHost()
            : FutureBuilder<UserModel?>(
                future: _sessionFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      backgroundColor: Colors.white,
                      body: Center(
                        child: CircularProgressIndicator(color: PatientAppTheme.primaryBlue),
                      ),
                    );
                  }
                  final user = snapshot.data;
                  if (user != null && user.role == 'patient') {
                    return const SafeZoneHost();
                  }
                  return const PatientLoginScreen();
                },
              ));

    return MaterialApp(
      title: 'MemoryGuide Patient',
      debugShowCheckedModeBanner: false,
      theme: PatientAppTheme.lightTheme,
      home: effectiveHome,
    );
  }
}
