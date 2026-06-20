import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/validator.dart';
import 'package:prograde_license_validator/src/config.dart';
import 'package:prograde_license_validator/src/storage.dart';
import 'package:prograde_license_validator/src/fingerprint.dart';
import 'package:prograde_license_validator/src/state_machine.dart';
import 'package:prograde_license_validator/src/errors.dart';
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

  test('signInAndActivate: signs in (with Origin), activates, stores JWT, returns ACTIVATED', () async {
    final signer = await TestSigner.generate();
    const nowSec = 1714694400;
    final jwt = await signer.navmathJwt(iatSec: nowSec - 5, expSec: nowSec + 99999);
    final seenPaths = <String>[];
    String? authOrigin;
    final client = MockClient((req) async {
      seenPaths.add(req.url.path);
      if (req.url.path == '/api/auth/sign-in/mobile') {
        authOrigin = req.headers['origin'];
        return http.Response(jsonEncode({'token': 'tok'}), 200);
      }
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
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore();
    final validator = LicenseValidator(
      config: ValidatorConfig(
        portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
      readMdmConfig: () async => null,
    );
    final state = await validator.signInAndActivate(
      email: 'a@b.com', password: 'pw',
      fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.activated);
    expect(authOrigin, 'https://portal.prograde.aero');
    expect(await store.read(kJwtStorageKey), jwt);
    expect(seenPaths.contains('/api/auth/sign-in/mobile'), isTrue);
  });

  test('signInAndActivate throws (not silent bounce) when issued JWT fails verification', () async {
    // Regression for the silent "back to sign-in" bug: activation succeeds but the
    // issued JWT's issuer does not match the validator's expectedIssuer (== portal
    // base URL). signInAndActivate must throw a LicenseException, not quietly return
    // a non-activated state that the UI renders as onboarding.
    final signer = await TestSigner.generate();
    const nowSec = 1714694400;
    final jwt = await signer.navmathJwt(
        iatSec: nowSec - 5, expSec: nowSec + 99999, iss: 'http://localhost:3000');
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/sign-in/mobile') {
        return http.Response(jsonEncode({'token': 'tok'}), 200);
      }
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
      return http.Response('nf', 404);
    });
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: InMemorySecureStore(), jwksStore: InMemoryKeyValueStore(), httpClient: client,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
      readMdmConfig: () async => null,
    );
    await expectLater(
      validator.signInAndActivate(
          email: 'a@b.com', password: 'pw', fingerprint: fp(), clientVersion: '1.0.0'),
      throwsA(isA<LicenseException>()
          .having((e) => e.error.code, 'code', ActivationErrorCode.invalidIssuer)),
    );
  });

  test('releaseDevice posts to self-release with the JWT and clears storage', () async {
    final store = InMemorySecureStore()..write('license.jwt', 'header.payload.sig');
    String? seenPath;
    String? seenAuth;
    final client = MockClient((req) async {
      seenPath = req.url.path;
      seenAuth = req.headers['authorization'];
      return http.Response(jsonEncode({'released': true}), 200);
    });
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    await validator.releaseDevice();
    expect(seenPath, '/api/devices/self/release');
    expect(seenAuth, 'License header.payload.sig');
    expect(await store.read('license.jwt'), isNull);
  });

  test('releaseDevice clears local storage even if the server call fails', () async {
    final store = InMemorySecureStore()..write('license.jwt', 'header.payload.sig');
    final client = MockClient((_) async => http.Response('err', 500));
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    await validator.releaseDevice();
    expect(await store.read('license.jwt'), isNull);
  });

  test('signInAndActivate persists the auth session token', () async {
    final signer = await TestSigner.generate();
    const nowSec = 1714694400;
    final jwt = await signer.navmathJwt(iatSec: nowSec - 5, expSec: nowSec + 99999);
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/sign-in/mobile') {
        return http.Response(jsonEncode({'token': 'sess-tok'}), 200);
      }
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
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore();
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
      readMdmConfig: () async => null,
    );
    await validator.signInAndActivate(
        email: 'a@b.com', password: 'pw', fingerprint: fp(), clientVersion: '1.0.0');
    expect(await store.read(kSessionStorageKey), 'sess-tok');
  });

  test('releaseDevice keeps the auth session (so the next launch can re-activate)', () async {
    final store = InMemorySecureStore()
      ..write(kJwtStorageKey, 'header.payload.sig')
      ..write(kSessionStorageKey, 'sess-tok');
    final client = MockClient((_) async => http.Response(jsonEncode({'released': true}), 200));
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    await validator.releaseDevice();
    expect(await store.read(kJwtStorageKey), isNull);
    expect(await store.read(kSessionStorageKey), 'sess-tok'); // kept
  });

  test('signOut revokes the session server-side and clears all local credentials', () async {
    final store = InMemorySecureStore()
      ..write(kJwtStorageKey, 'header.payload.sig')
      ..write(kSessionStorageKey, 'sess-tok');
    final seenPaths = <String>[];
    final client = MockClient((req) async {
      seenPaths.add(req.url.path);
      if (req.url.path == '/api/auth/sign-out/mobile') {
        return http.Response('', 204);
      }
      return http.Response(jsonEncode({'released': true}), 200);
    });
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    await validator.signOut();
    expect(seenPaths.contains('/api/devices/self/release'), isTrue);
    expect(seenPaths.contains('/api/auth/sign-out/mobile'), isTrue);
    expect(await store.read(kJwtStorageKey), isNull);
    expect(await store.read(kSessionStorageKey), isNull);
  });

  test('bootstrapOrReactivate silently re-activates using the stored session', () async {
    final signer = await TestSigner.generate();
    const nowSec = 1714694400;
    final jwt = await signer.navmathJwt(iatSec: nowSec - 5, expSec: nowSec + 99999);
    final seenPaths = <String>[];
    final client = MockClient((req) async {
      seenPaths.add(req.url.path);
      if (req.url.path == '/api/auth/refresh/mobile') {
        return http.Response(jsonEncode({'token': 'fresh-tok', 'expiresAt': 'x'}), 200);
      }
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
      return http.Response('nf', 404);
    });
    // No license JWT, but a stored session — as after a release + portal re-assign.
    final store = InMemorySecureStore()..write(kSessionStorageKey, 'sess-tok');
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
      readMdmConfig: () async => null,
    );
    final state = await validator.bootstrapOrReactivate(
        fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.activated);
    expect(await store.read(kJwtStorageKey), jwt);
    expect(await store.read(kSessionStorageKey), 'fresh-tok'); // session slid forward
    expect(seenPaths.contains('/api/auth/refresh/mobile'), isTrue);
  });

  test('bootstrapOrReactivate clears a dead session (refresh 401) and stays onboarding', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/refresh/mobile') {
        return http.Response(jsonEncode({'error': 'invalid_session'}), 401);
      }
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore()..write(kSessionStorageKey, 'dead-tok');
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    final state = await validator.bootstrapOrReactivate(
        fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.awaitingUserOnboarding);
    expect(await store.read(kSessionStorageKey), isNull); // dead session dropped
  });

  test('bootstrapOrReactivate with no stored session just returns onboarding', () async {
    final client = MockClient((_) async => http.Response('nf', 404));
    final store = InMemorySecureStore();
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    final state = await validator.bootstrapOrReactivate(
        fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.awaitingUserOnboarding);
  });

  test('bootstrapOrReactivate → AWAITING_LICENCE when no seat is allocated (no auto-grab)', () async {
    final seenAllocate = <bool>[];
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/refresh/mobile') {
        return http.Response(jsonEncode({'token': 'fresh', 'expiresAt': 'x'}), 200);
      }
      if (req.url.path == '/api/licenses/activate') {
        seenAllocate.add((jsonDecode(req.body) as Map)['allocate'] as bool);
        return http.Response(
            jsonEncode({'code': 'no_licence_allocated', 'recoverable': true}), 409);
      }
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore()..write(kSessionStorageKey, 'sess-tok');
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    final state = await validator.bootstrapOrReactivate(
        fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.awaitingLicence);
    expect(seenAllocate, [false]); // existing-seat-only: never auto-allocates
    expect(await store.read(kSessionStorageKey), 'fresh'); // session kept
  });

  test('checkAllocation unlocks (ACTIVATED) once a seat is allocated', () async {
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
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore()..write(kSessionStorageKey, 'sess-tok');
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
      readMdmConfig: () async => null,
    );
    final state = await validator.checkAllocation(
        fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.activated);
    expect(await store.read(kJwtStorageKey), jwt);
  });

  test('checkAllocation stays AWAITING_LICENCE while still unallocated', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/licenses/activate') {
        return http.Response(
            jsonEncode({'code': 'no_licence_allocated', 'recoverable': true}), 409);
      }
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore()..write(kSessionStorageKey, 'sess-tok');
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    final state = await validator.checkAllocation(
        fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.awaitingLicence);
    expect(await store.read(kSessionStorageKey), 'sess-tok'); // kept
  });

  test('checkAllocation surfaces a terminal error (no_eligible_license) as error', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/licenses/activate') {
        return http.Response(
            jsonEncode({'code': 'no_eligible_license', 'recoverable': false}), 403);
      }
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore()..write(kSessionStorageKey, 'sess-tok');
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    final state = await validator.checkAllocation(
        fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.error);
    expect(state.error?.code, ActivationErrorCode.noEligibleLicense);
  });

  test('selfAllocate throws (capExceeded) when no seat is available', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/refresh/mobile') {
        return http.Response(jsonEncode({'token': 'fresh', 'expiresAt': 'x'}), 200);
      }
      if (req.url.path == '/api/licenses/activate') {
        return http.Response(
            jsonEncode({'code': 'cap_exceeded', 'cap': 5, 'used': 5}), 409);
      }
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore()..write(kSessionStorageKey, 'sess-tok');
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    await expectLater(
      validator.selfAllocate(fingerprint: fp(), clientVersion: '1.0.0'),
      throwsA(isA<LicenseException>()),
    );
  });

  test('selfAllocate grabs an available seat and ACTIVATES', () async {
    final signer = await TestSigner.generate();
    const nowSec = 1714694400;
    final jwt = await signer.navmathJwt(iatSec: nowSec - 5, expSec: nowSec + 99999);
    final seenAllocate = <bool>[];
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/refresh/mobile') {
        return http.Response(jsonEncode({'token': 'fresh', 'expiresAt': 'x'}), 200);
      }
      if (req.url.path == '/.well-known/jwks.json') {
        return http.Response(jsonEncode(signer.jwksDocument()), 200);
      }
      if (req.url.path == '/api/licenses/activate') {
        seenAllocate.add((jsonDecode(req.body) as Map)['allocate'] as bool);
        return http.Response(jsonEncode({
          'jwt': jwt, 'expiresAt': 'x', 'statusUrl': '/s', 'refreshAfter': 'x',
          'slotNumber': 0, 'minValidatorVersion': '0.1.0',
          'license': {'scope': 'app', 'appsIncluded': ['navmath']},
        }), 200);
      }
      return http.Response('nf', 404);
    });
    final store = InMemorySecureStore()..write(kSessionStorageKey, 'sess-tok');
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
      readMdmConfig: () async => null,
    );
    final state = await validator.selfAllocate(
        fingerprint: fp(), clientVersion: '1.0.0');
    expect(state.phase, ValidatorStatePhase.activated);
    expect(seenAllocate, [true]); // self-service DOES allocate
  });

  test('releaseDevice(removeFromOrg: true) posts removeFromOrg and clears JWT', () async {
    final store = InMemorySecureStore()..write(kJwtStorageKey, 'header.payload.sig');
    Map<String, dynamic>? seenBody;
    final client = MockClient((req) async {
      if (req.url.path == '/api/devices/self/release') {
        seenBody = jsonDecode(req.body) as Map<String, dynamic>;
      }
      return http.Response(jsonEncode({'released': true, 'removedFromOrg': true}), 200);
    });
    final validator = LicenseValidator(
      config: ValidatorConfig(
          portalBaseUrl: Uri.parse('https://portal.prograde.aero'), expectedAudience: 'navmath'),
      secureStore: store, jwksStore: InMemoryKeyValueStore(), httpClient: client,
      readMdmConfig: () async => null,
    );
    await validator.releaseDevice(removeFromOrg: true);
    expect(seenBody?['removeFromOrg'], true);
    expect(await store.read(kJwtStorageKey), isNull);
  });
}
