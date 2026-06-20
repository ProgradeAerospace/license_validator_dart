import 'package:flutter_test/flutter_test.dart';
import 'package:prograde_license_validator/src/state_machine.dart';
import 'package:prograde_license_validator/src/jwt.dart';
import 'package:prograde_license_validator/src/jwks.dart';
import 'package:prograde_license_validator/src/storage.dart';
import 'package:prograde_license_validator/src/errors.dart';
import 'support/test_keys.dart';

void main() {
  late TestSigner signer;
  late JwksDocument jwks;
  const nowSec = 1714694400;
  JwtVerifier verifier() => JwtVerifier(
        expectedIssuer: 'https://portal.prograde.aero',
        expectedAudience: 'navmath',
        now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
      );

  setUp(() async {
    signer = await TestSigner.generate();
    jwks = JwksDocument.fromJson(signer.jwksDocument());
  });

  test('valid cached JWT -> ACTIVATED', () async {
    final jwt = await signer.navmathJwt(iatSec: nowSec - 10, expSec: nowSec + 99999);
    final store = InMemorySecureStore()..write('license.jwt', jwt);
    final sm = FirstLaunchStateMachine(
      secureStore: store,
      verifier: verifier(),
      loadJwks: () async => jwks,
      readMdmConfig: () async => null,
    );
    final state = await sm.bootstrap();
    expect(state.phase, ValidatorStatePhase.activated);
    expect(state.claims!.licenseId, 'license-uuid-abc');
  });

  test('no cached JWT, no MDM -> AWAITING_USER_ONBOARDING', () async {
    final sm = FirstLaunchStateMachine(
      secureStore: InMemorySecureStore(),
      verifier: verifier(),
      loadJwks: () async => jwks,
      readMdmConfig: () async => null,
    );
    expect((await sm.bootstrap()).phase, ValidatorStatePhase.awaitingUserOnboarding);
  });

  test('expired cached JWT, no MDM -> AWAITING_USER_ONBOARDING', () async {
    final jwt = await signer.navmathJwt(iatSec: 1, expSec: 1000);
    final store = InMemorySecureStore()..write('license.jwt', jwt);
    final sm = FirstLaunchStateMachine(
      secureStore: store,
      verifier: verifier(),
      loadJwks: () async => jwks,
      readMdmConfig: () async => null,
    );
    expect((await sm.bootstrap()).phase, ValidatorStatePhase.awaitingUserOnboarding);
  });

  test('cached JWT with wrong issuer -> ERROR (not silent onboarding)', () async {
    // Regression: a verification failure (here issuer mismatch) must surface as an
    // error, not masquerade as a clean first launch routed to onboarding.
    final jwt = await signer.navmathJwt(
        iatSec: nowSec - 10, expSec: nowSec + 99999, iss: 'http://192.168.2.52:3000');
    final store = InMemorySecureStore()..write('license.jwt', jwt);
    final sm = FirstLaunchStateMachine(
      secureStore: store,
      verifier: verifier(),
      loadJwks: () async => jwks,
      readMdmConfig: () async => null,
    );
    final state = await sm.bootstrap();
    expect(state.phase, ValidatorStatePhase.error);
    expect(state.error!.code, ActivationErrorCode.invalidIssuer);
  });

  test('MDM config preActivate=false -> AWAITING_USER_ACTIVATION', () async {
    final sm = FirstLaunchStateMachine(
      secureStore: InMemorySecureStore(),
      verifier: verifier(),
      loadJwks: () async => jwks,
      readMdmConfig: () async => ({'schemaVersion': 1, 'licenseKey': 'lk_${'a' * 32}', 'preActivate': false}),
    );
    expect((await sm.bootstrap()).phase, ValidatorStatePhase.awaitingUserActivation);
  });
}
