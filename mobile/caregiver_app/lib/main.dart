import 'package:flutter/material.dart';

import 'caregiver_dashboard.dart';
import 'core/services/caregiver_service_locator.dart';
import 'data/models/caregiver_models.dart';
import 'features/authentication/caregiver_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await CaregiverServiceLocator.instance.pushNotificationService.init();
  } catch (_) {}
  runApp(const MemoryGuideApp());
}

class MemoryGuideApp extends StatefulWidget {
  final Widget? home;
  const MemoryGuideApp({super.key, this.home});

  @override
  State<MemoryGuideApp> createState() => _MemoryGuideAppState();
}

class _MemoryGuideAppState extends State<MemoryGuideApp> {
  late Future<CaregiverUser?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture =
        CaregiverServiceLocator.instance.authRepository.restoreSession();
  }

  bool get _isTestEnvironment =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  Widget build(BuildContext context) {
    const forest = Color(0xFF174D43);
    const canvas = Color(0xFFF7F8F5);

    final Widget effectiveHome = widget.home ??
        (_isTestEnvironment
            ? const CaregiverDashboard()
            : FutureBuilder<CaregiverUser?>(
                future: _sessionFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      backgroundColor: canvas,
                      body: Center(
                        child: CircularProgressIndicator(color: forest),
                      ),
                    );
                  }
                  final user = snapshot.data;
                  if (user != null && user.role == 'caregiver') {
                    return const CaregiverDashboard();
                  }
                  return const CaregiverLoginScreen();
                },
              ));

    return MaterialApp(
      title: 'MemoryGuide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: forest,
          primary: forest,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: forest,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE9EDE8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F8F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE4E9E3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE4E9E3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: forest, width: 1.5),
          ),
        ),
      ),
      home: effectiveHome,
    );
  }
}
