import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/jwks.dart';
import 'package:prograde_license_validator/src/storage.dart';
import 'package:prograde_license_validator/src/errors.dart';
import 'support/test_keys.dart';

void main() {
  late TestSigner signer;
  setUp(() async => signer = await TestSigner.generate());

  test('JwksDocument.keyForKid finds and skips missing', () {
    final doc = JwksDocument.fromJson(signer.jwksDocument());
    expect(doc.keyForKid(kTestKid)!.x.length, 32);
    expect(doc.keyForKid('nope'), isNull);
  });

  test('keyForKid skips key with malformed x (length != 32) -> returns null', () {
    // Build a JWKS doc whose only key has a 10-byte x value (base64url-encoded)
    final shortX = base64Url.encode(List.filled(10, 0xFF)).replaceAll('=', '');
    final doc = JwksDocument.fromJson({
      'keys': [
        {'kid': kTestKid, 'kty': 'OKP', 'crv': 'Ed25519', 'x': shortX, 'alg': 'EdDSA', 'use': 'sig', 'status': 'current'},
      ],
    });
    expect(doc.keyForKid(kTestKid), isNull);
  });

  test('cache fetches once within TTL, refetches after expiry', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(jsonEncode(signer.jwksDocument()), 200,
          headers: {'content-type': 'application/json'});
    });
    var nowMs = 0;
    final cache = JwksCache(
      baseUrl: Uri.parse('https://portal.prograde.aero'),
      client: client,
      store: InMemoryKeyValueStore(),
      ttl: const Duration(hours: 1),
      offlineGrace: const Duration(days: 30),
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
    );
    await cache.current(); // miss -> fetch
    await cache.current(); // hit
    expect(calls, 1);
    nowMs += const Duration(hours: 2).inMilliseconds;
    await cache.current(); // TTL expired -> refetch
    expect(calls, 2);
  });

  test('offline within grace serves cached; beyond grace fails closed', () async {
    var fail = false;
    final client = MockClient((req) async {
      if (fail) return http.Response('boom', 503);
      return http.Response(jsonEncode(signer.jwksDocument()), 200);
    });
    var nowMs = 0;
    final cache = JwksCache(
      baseUrl: Uri.parse('https://portal.prograde.aero'),
      client: client,
      store: InMemoryKeyValueStore(),
      ttl: const Duration(hours: 1),
      offlineGrace: const Duration(days: 30),
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
    );
    await cache.current(); // seed cache
    fail = true;
    nowMs += const Duration(hours: 2).inMilliseconds; // TTL expired, endpoint down
    expect((await cache.current()).keyForKid(kTestKid), isNotNull); // within grace
    nowMs += const Duration(days: 31).inMilliseconds; // beyond grace
    expect(
      () => cache.current(),
      throwsA(isA<LicenseException>().having(
          (e) => e.error.code, 'code', ActivationErrorCode.jwksUnreachable)),
    );
  });
}
