import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/auth.dart';
import 'package:prograde_license_validator/src/errors.dart';

void main() {
  test('signIn posts Origin + credentials and returns token', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({'token': 'tok-1', 'expiresAt': 'x'}), 200);
    });
    final c = AuthClient(baseUrl: Uri.parse('https://portal.prograde.aero'), client: client);
    final token = await c.signIn(email: 'a@b.com', password: 'pw');
    expect(token, 'tok-1');
    expect(seen.url.path, '/api/auth/sign-in/mobile');
    expect(seen.headers['origin'], 'https://portal.prograde.aero');
    expect(jsonDecode(seen.body)['email'], 'a@b.com');
  });

  test('redeemInvite posts Origin + fields and returns token', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({'token': 'tok-2', 'expiresAt': 'x'}), 200);
    });
    final c = AuthClient(baseUrl: Uri.parse('http://10.0.2.2:3000'), client: client);
    final token = await c.redeemInvite(code: 'inv-1', password: 'pw', displayName: 'Pilot');
    expect(token, 'tok-2');
    expect(seen.url.path, '/api/auth/redeem-invite/mobile');
    expect(seen.headers['origin'], 'http://10.0.2.2:3000');
    expect(jsonDecode(seen.body)['code'], 'inv-1');
  });

  Future<ActivationErrorCode> code(Future<void> Function() body) async {
    try { await body(); return ActivationErrorCode.unknown; }
    on LicenseException catch (e) { return e.error.code; }
  }

  test('signIn 401 -> invalidSession', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response('{}', 401)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.invalidSession);
  });

  test('signIn 5xx -> networkUnreachable', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response('x', 503)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.networkUnreachable);
  });

  test('redeemInvite 409 -> invalidSession (already redeemed/invalid)', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response(jsonEncode({'error': 'invite_already_redeemed'}), 409)));
    expect(await code(() => c.redeemInvite(code: 'x', password: 'p', displayName: 'd')), ActivationErrorCode.invalidSession);
  });

  test('missing token in 200 body -> networkUnreachable', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response('{}', 200)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.networkUnreachable);
  });
}
