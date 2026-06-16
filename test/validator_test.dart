import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/validator.dart';
import 'package:prograde_license_validator/src/config.dart';
import 'package:prograde_license_validator/src/storage.dart';
import 'package:prograde_license_validator/src/fingerprint.dart';
import 'package:prograde_license_validator/src/state_machine.dart';
import 'support/test_keys.dart';

DeviceFingerprint fp() => DeviceFingerprint(
      platform: 'ios', platformVersion: '17.4', deviceModel: 'iPhone15,2',
      bundleId: 'aero.prograde.navmath', rawVendorId: 'idfv-1', displayName: 'iPad');

void main() {
  test('activateWithSession stores JWT and bootstrap then reports ACTIVATED', () async {
    final signer = await TestSigner.generate();
    const nowSec = 1714694400;
    final jwt = await signer.navmathJwt(iatSec: nowSec - 5, expSec: nowSec + 99999);

    final client = MockClient((req) async {
      if (req.url.path == '/.well-known/jwks.json') {
        return http.Response(jsonEncode(signer.jwksDocument()), 200);
      }
      if (req.url.path == '/api/licenses/activate') {
        return http.Response(jsonEncode({
          'jwt': jwt, 'expiresAt': 'x', 'statusUrl': '/s', 'refreshAfter': 'x',
          'slotNumber': 0, 'minValidatorVersion': '0.1.0',
          'license': {'scope': 'app', 'appsIncluded': ['navmath']},
        }), 200);
      }
      return http.Response('not found', 404);
    });

    final store = InMemorySecureStore();
    final validator = LicenseValidator(
      config: ValidatorConfig(
        portalBaseUrl: Uri.parse('https://portal.prograde.aero'),
        expectedAudience: 'navmath',
      ),
      secureStore: store,
      jwksStore: InMemoryKeyValueStore(),
      httpClient: client,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
      readMdmConfig: () async => null,
    );

    final result = await validator.activateWithSession(
        token: 'tok', fingerprint: fp(), clientVersion: '1.0.0');
    expect(result.jwt, jwt);
    expect(await store.read(kJwtStorageKey), jwt);

    final state = await validator.bootstrap();
    expect(state.phase, ValidatorStatePhase.activated);
  });
}
