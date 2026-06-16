import 'package:flutter_test/flutter_test.dart';
import 'package:prograde_license_validator/src/jwt.dart';
import 'package:prograde_license_validator/src/jwks.dart';
import 'package:prograde_license_validator/src/errors.dart';
import 'support/test_keys.dart';

void main() {
  late TestSigner signer;
  late JwksDocument jwks;
  const nowSec = 1714694400; // 2024-05-03

  setUp(() async {
    signer = await TestSigner.generate();
    jwks = JwksDocument.fromJson(signer.jwksDocument());
  });

  JwtVerifier verifierAt(int now) => JwtVerifier(
        expectedIssuer: 'https://portal.prograde.aero',
        expectedAudience: 'navmath',
        clockTolerance: const Duration(seconds: 60),
        now: () => DateTime.fromMillisecondsSinceEpoch(now * 1000, isUtc: true),
      );

  test('valid JWT returns claims', () async {
    final jwt = await signer.navmathJwt(iatSec: 1714608000, expSec: 1717200000);
    final claims = await verifierAt(nowSec).verify(jwt, jwks);
    expect(claims.aud, 'navmath');
    expect(claims.licenseId, 'license-uuid-abc');
    expect(claims.slotNumber, 0);
  });

  Future<ActivationErrorCode> codeFor(Future<void> Function() body) async {
    try { await body(); return ActivationErrorCode.unknown; }
    on LicenseException catch (e) { return e.error.code; }
  }

  test('expired JWT -> license_expired', () async {
    final jwt = await signer.navmathJwt(iatSec: 1, expSec: 1000);
    expect(await codeFor(() => verifierAt(nowSec).verify(jwt, jwks)),
        ActivationErrorCode.licenseExpired);
  });

  test('wrong audience -> invalid_audience', () async {
    final jwt = await signer.navmathJwt(iatSec: 1714608000, expSec: 1717200000, aud: 'hudsim');
    expect(await codeFor(() => verifierAt(nowSec).verify(jwt, jwks)),
        ActivationErrorCode.invalidAudience);
  });

  test('wrong issuer -> invalid_issuer', () async {
    final jwt = await signer.navmathJwt(iatSec: 1714608000, expSec: 1717200000, iss: 'https://evil.example');
    expect(await codeFor(() => verifierAt(nowSec).verify(jwt, jwks)),
        ActivationErrorCode.invalidIssuer);
  });

  test('unknown kid -> invalid_kid', () async {
    final jwt = await signer.navmathJwt(iatSec: 1714608000, expSec: 1717200000, kid: 'k-future');
    expect(await codeFor(() => verifierAt(nowSec).verify(jwt, jwks)),
        ActivationErrorCode.invalidKid);
  });

  test('far-future iat -> invalid_iat', () async {
    final jwt = await signer.navmathJwt(iatSec: nowSec + 120, expSec: nowSec + 9999999);
    expect(await codeFor(() => verifierAt(nowSec).verify(jwt, jwks)),
        ActivationErrorCode.invalidIat);
  });

  test('tampered signature -> invalid_signature', () async {
    final jwt = await signer.navmathJwt(iatSec: 1714608000, expSec: 1717200000);
    final parts = jwt.split('.');
    final tampered = '${parts[0]}.${parts[1]}.${parts[2].substring(0, parts[2].length - 2)}AA';
    expect(await codeFor(() => verifierAt(nowSec).verify(tampered, jwks)),
        ActivationErrorCode.invalidSignature);
  });

  test('bundle JWT exposes bundle_apps', () async {
    final jwt = await signer.navmathJwt(
        iatSec: 1714608000, expSec: 1717200000, bundleApps: ['navmath', 'hudsim']);
    final claims = await verifierAt(nowSec).verify(jwt, jwks);
    expect(claims.bundleApps, ['navmath', 'hudsim']);
  });

  test('skipExpCheck lets an expired JWT through (status use)', () async {
    final jwt = await signer.navmathJwt(iatSec: 1, expSec: 1000);
    final claims = await verifierAt(nowSec).verify(jwt, jwks, skipExpCheck: true);
    expect(claims.licenseId, 'license-uuid-abc');
  });
}
