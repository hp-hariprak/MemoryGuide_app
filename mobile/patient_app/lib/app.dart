import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/safe_zones/safe_zone_host.dart';

class PatientApp extends StatelessWidget {
  final Widget? home;
  const PatientApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MemoryGuide Patient',
      debugShowCheckedModeBanner: false,
      theme: PatientAppTheme.lightTheme,
      home: home ?? const SafeZoneHost(),
    );
  }
}
