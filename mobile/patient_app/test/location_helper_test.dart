import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:patient_app/core/utils/location_helper.dart';

class FakeGeolocatorPlatformWrapper implements GeolocatorPlatformWrapper {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestPermissionResult = LocationPermission.whileInUse;
  bool requestPermissionCalled = false;
  bool openLocationSettingsCalled = false;
  bool openAppSettingsCalled = false;
  Position? positionToReturn;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalled = true;
    permission = requestPermissionResult;
    return requestPermissionResult;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalled = true;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalled = true;
    return true;
  }

  @override
  Future<Position?> getCurrentPosition() async => positionToReturn;
}

void main() {
  group('LocationHelper Tests', () {
    late FakeGeolocatorPlatformWrapper fakePlatform;

    setUp(() {
      fakePlatform = FakeGeolocatorPlatformWrapper();
    });

    test('service off -> serviceDisabled without requesting permission', () async {
      fakePlatform.serviceEnabled = false;

      final result = await LocationHelper.ensureAccess(customPlatform: fakePlatform);

      expect(result, equals(LocationAccess.serviceDisabled));
      expect(fakePlatform.requestPermissionCalled, isFalse);
    });

    test('already granted (whileInUse) -> granted', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.whileInUse;

      final result = await LocationHelper.ensureAccess(customPlatform: fakePlatform);

      expect(result, equals(LocationAccess.granted));
      expect(fakePlatform.requestPermissionCalled, isFalse);
    });

    test('already granted (always) -> granted', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.always;

      final result = await LocationHelper.ensureAccess(customPlatform: fakePlatform);

      expect(result, equals(LocationAccess.granted));
      expect(fakePlatform.requestPermissionCalled, isFalse);
    });

    test('denied then granted after request -> granted', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.denied;
      fakePlatform.requestPermissionResult = LocationPermission.whileInUse;

      final result = await LocationHelper.ensureAccess(customPlatform: fakePlatform);

      expect(result, equals(LocationAccess.granted));
      expect(fakePlatform.requestPermissionCalled, isTrue);
    });

    test('denied then denied after request -> denied', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.denied;
      fakePlatform.requestPermissionResult = LocationPermission.denied;

      final result = await LocationHelper.ensureAccess(customPlatform: fakePlatform);

      expect(result, equals(LocationAccess.denied));
      expect(fakePlatform.requestPermissionCalled, isTrue);
    });

    test('deniedForever -> deniedForever without calling requestPermission', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.deniedForever;

      final result = await LocationHelper.ensureAccess(customPlatform: fakePlatform);

      expect(result, equals(LocationAccess.deniedForever));
      expect(fakePlatform.requestPermissionCalled, isFalse);
    });

    test('denied then deniedForever after request -> deniedForever', () async {
      fakePlatform.serviceEnabled = true;
      fakePlatform.permission = LocationPermission.denied;
      fakePlatform.requestPermissionResult = LocationPermission.deniedForever;

      final result = await LocationHelper.ensureAccess(customPlatform: fakePlatform);

      expect(result, equals(LocationAccess.deniedForever));
      expect(fakePlatform.requestPermissionCalled, isTrue);
    });

    test('openLocationSettings and openAppSettings delegate to platform', () async {
      await LocationHelper.openLocationSettings(customPlatform: fakePlatform);
      expect(fakePlatform.openLocationSettingsCalled, isTrue);

      await LocationHelper.openAppSettings(customPlatform: fakePlatform);
      expect(fakePlatform.openAppSettingsCalled, isTrue);
    });

    test('toFailure maps non-granted states', () {
      expect(LocationHelper.toFailure(LocationAccess.granted), isNull);
      expect(LocationHelper.toFailure(LocationAccess.serviceDisabled)?.message,
          contains('disabled'));
      expect(LocationHelper.toFailure(LocationAccess.denied)?.message,
          contains('denied'));
      expect(LocationHelper.toFailure(LocationAccess.deniedForever)?.message,
          contains('permanently denied'));
    });
  });
}
