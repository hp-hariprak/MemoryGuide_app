import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/data/datasources/location_datasource.dart';
import 'package:patient_app/data/models/location_fix.dart';
import 'package:patient_app/features/safe_zones/safe_zone_host.dart';

void main() {
  testWidgets(
      'SafeZoneHost updates UI from "You are safe" to "Outside safe zone" as mock route progresses',
      (WidgetTester tester) async {
    const tick = Duration(milliseconds: 50);

    // Custom route with 1 initial inside fix followed by 2 consecutive outside fixes
    final route = [
      LocationFix(
        latitude: MockLocationSource.centerLat,
        longitude: MockLocationSource.centerLon,
        accuracyMeters: 5.0,
        timestamp: DateTime.now().toUtc(),
      ),
      LocationFix(
        latitude: MockLocationSource.centerLat + 0.003, // ~333m away (>150m)
        longitude: MockLocationSource.centerLon,
        accuracyMeters: 5.0,
        timestamp: DateTime.now().toUtc(),
      ),
      LocationFix(
        latitude: MockLocationSource.centerLat + 0.004, // ~444m away (>150m)
        longitude: MockLocationSource.centerLon,
        accuracyMeters: 5.0,
        timestamp: DateTime.now().toUtc(),
      ),
    ];

    final mockSource = MockLocationSource(
      tickDuration: tick,
      customRoute: route,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SafeZoneHost(
          locationSource: mockSource,
          isDevMode: false,
        ),
      ),
    );

    // Pump to process immediate initial fix (inside)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('You are safe'), findsOneWidget);
    expect(find.text('Inside Home (Maple Street)'), findsOneWidget);

    // Advance 1 tick -> outside fix #1 (debounced, still safe)
    await tester.pump(tick);
    expect(find.text('You are safe'), findsOneWidget);

    // Advance 2nd tick -> outside fix #2 (confirms exit)
    await tester.pump(tick);
    await tester.pump();

    expect(find.text('Outside safe zone'), findsOneWidget);
    expect(find.text('Your family knows where you are'), findsOneWidget);
    expect(find.text('You are safe'), findsNothing);

    // Unmount widget so SafeZoneHost disposes cleanly
    await tester.pumpWidget(const SizedBox());
    mockSource.dispose();
  });
}
