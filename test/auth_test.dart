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

  test('signIn 401 -> invalidCredentials (wrong email/password)', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response('{}', 401)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.invalidCredentials);
  });

  test('redeemInvite 401 -> invalidSession (not a credential field)', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response('{}', 401)));
    expect(await code(() => c.redeemInvite(code: 'x', password: 'p', displayName: 'd')), ActivationErrorCode.invalidSession);
  });

  test('signIn 5xx -> networkUnreachable', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response('x', 503)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.networkUnreachable);
  });

  test('signIn 401 account_inactive -> accountInactive', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response(jsonEncode({'error': 'account_inactive'}), 401)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.accountInactive);
  });

  test('signIn 401 org_inactive -> orgInactive', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response(jsonEncode({'error': 'org_inactive'}), 401)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.orgInactive);
  });

  test('signIn 503 auth_unavailable -> authUnavailable', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response(jsonEncode({'error': 'auth_unavailable'}), 503)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.authUnavailable);
  });

  test('signIn 429 -> rateLimited', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response(jsonEncode({'error': 'rate_limited'}), 429)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.rateLimited);
  });

  test('redeemInvite 409 -> invalidSession (already redeemed/invalid)', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response(jsonEncode({'error': 'invite_already_redeemed'}), 409)));
    expect(await code(() => c.redeemInvite(code: 'x', password: 'p', displayName: 'd')), ActivationErrorCode.invalidSession);
  });

  test('missing token in 200 body -> networkUnreachable', () async {
    final c = AuthClient(baseUrl: Uri.parse('https://p'), client: MockClient((_) async => http.Response('{}', 200)));
    expect(await code(() => c.signIn(email: 'a', password: 'b')), ActivationErrorCode.networkUnreachable);
  });

  test('signIn 400 generic -> unknown code with "check your details" message', () async {
    final c = AuthClient(
      baseUrl: Uri.parse('https://p'),
      client: MockClient((_) async => http.Response(jsonEncode({'error': 'invalid_body'}), 400)),
    );
    try {
      await c.signIn(email: 'a', password: 'b');
      fail('expected LicenseException');
    } on LicenseException catch (e) {
      expect(e.error.code, ActivationErrorCode.unknown);
      expect(e.error.userMessage, contains('check your details'));
    }
  });

  test('redeemInvite 400 weak_password -> unknown code with "stronger password" message', () async {
    final c = AuthClient(
      baseUrl: Uri.parse('https://p'),
      client: MockClient((_) async => http.Response(jsonEncode({'error': 'weak_password'}), 400)),
    );
    try {
      await c.redeemInvite(code: 'x', password: 'p', displayName: 'd');
      fail('expected LicenseException');
    } on LicenseException catch (e) {
      expect(e.error.code, ActivationErrorCode.unknown);
      expect(e.error.userMessage, contains('stronger password'));
    }
  });
}
