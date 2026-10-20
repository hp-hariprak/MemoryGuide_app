import 'package:flutter/material.dart';
import 'app.dart';
import 'core/services/service_locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await PatientAppServices.instance.pushNotificationService.init();
  } catch (_) {}
  runApp(const PatientApp());
}
