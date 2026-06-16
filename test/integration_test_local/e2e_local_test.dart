import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/validator.dart';
import 'package:prograde_license_validator/src/config.dart';
import 'package:prograde_license_validator/src/storage.dart';
import 'package:prograde_license_validator/src/fingerprint.dart';
import 'package:prograde_license_validator/src/state_machine.dart';

/// Run against a locally-running portal:
///   E2E_PORTAL_URL=http://localhost:3000 E2E_INVITE_CODE=<code> E2E_PASSWORD=Passw0rd! \
///   flutter test test/integration_test_local/e2e_local_test.dart
void main() {
  final portal = Platform.environment['E2E_PORTAL_URL'];
  final inviteCode = Platform.environment['E2E_INVITE_CODE'];
  final password = Platform.environment['E2E_PASSWORD'];

  test('redeem invite -> activate -> status active (local portal)', () async {
    if (portal == null || inviteCode == null || password == null) {
      markTestSkipped('Set E2E_PORTAL_URL, E2E_INVITE_CODE, E2E_PASSWORD to run.');
      return;
    }
    final client = http.Client();

    // 1. redeem invite -> bearer token
    final redeem = await client.post(
      Uri.parse('$portal/api/auth/redeem-invite/mobile'),
      headers: {'content-type': 'application/json'},
      body: '{"code":"$inviteCode","password":"$password","displayName":"E2E Pilot"}',
    );
    expect(redeem.statusCode, 200, reason: redeem.body);
    final token = RegExp(r'"token":"([^"]+)"').firstMatch(redeem.body)!.group(1)!;

    // 2. activate
    final validator = LicenseValidator(
      config: ValidatorConfig(
        portalBaseUrl: Uri.parse(portal),
        expectedAudience: 'navmath',
        allowInsecureLocalhost: portal.startsWith('http://'),
      ),
      secureStore: InMemorySecureStore(),
      jwksStore: InMemoryKeyValueStore(),
      httpClient: client,
      readMdmConfig: () async => null,
    );
    final res = await validator.activateWithSession(
      token: token,
      fingerprint: DeviceFingerprint(
        platform: 'ios', platformVersion: '17.4', deviceModel: 'iPhone15,2',
        bundleId: 'aero.prograde.navmath', rawVendorId: 'e2e-device-1', displayName: 'E2E iPad'),
      clientVersion: '1.0.0',
    );
    expect(res.jwt.split('.').length, 3);

    // 3. bootstrap sees the cached JWT as ACTIVATED
    expect((await validator.bootstrap()).phase, ValidatorStatePhase.activated);

    // 4. status is active
    final status = await validator.refreshStatus();
    expect(status!.active, isTrue);
  });
}
