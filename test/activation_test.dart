import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/activation.dart';
import 'package:prograde_license_validator/src/fingerprint.dart';
import 'package:prograde_license_validator/src/errors.dart';

DeviceFingerprint fp() => DeviceFingerprint(
      platform: 'ios', platformVersion: '17.4', deviceModel: 'iPhone15,2',
      bundleId: 'aero.prograde.navmath', rawVendorId: 'idfv-123', displayName: 'iPad');

void main() {
  test('session activation posts Bearer + fingerprint, parses result', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({
          'jwt': 'eyJ.a.b',
          'expiresAt': '2026-06-01T00:00:00Z',
          'statusUrl': '/api/licenses/license-1/status',
          'refreshAfter': '2026-05-09T00:00:00Z',
          'slotNumber': 0,
          'minValidatorVersion': '0.1.0',
          'license': {'scope': 'app', 'appsIncluded': ['navmath']},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final c = ActivationClient(
        baseUrl: Uri.parse('https://portal.prograde.aero'), client: client);
    final res = await c.activate(
        auth: const AuthMode.session('tok-123'),
        fingerprint: fp(), appId: 'navmath', clientVersion: '1.0.0');
    expect(seen.headers['authorization'], 'Bearer tok-123');
    expect(jsonDecode(seen.body)['appId'], 'navmath');
    expect(res.jwt, 'eyJ.a.b');
    expect(res.scope, LicenseScope.app);
    expect(res.appsIncluded, ['navmath']);
  });

  test('license-key mode uses License header', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({
        'jwt': 'x', 'expiresAt': '2026-06-01T00:00:00Z',
        'statusUrl': '/s', 'refreshAfter': '2026-05-09T00:00:00Z',
        'slotNumber': 1, 'minValidatorVersion': '0.1.0',
        'license': {'scope': 'bundle', 'appsIncluded': ['navmath', 'hudsim']},
      }), 200);
    });
    final c = ActivationClient(baseUrl: Uri.parse('https://portal.prograde.aero'), client: client);
    await c.activate(
        auth: const AuthMode.licenseKey('lk_abc'),
        fingerprint: fp(), appId: 'navmath', clientVersion: '1.0.0');
    expect(seen.headers['authorization'], 'License lk_abc');
  });

  Future<ActivationErrorCode> codeFor(http.Response Function() resp) async {
    final c = ActivationClient(
        baseUrl: Uri.parse('https://portal.prograde.aero'),
        client: MockClient((_) async => resp()));
    try {
      await c.activate(auth: const AuthMode.session('t'), fingerprint: fp(), appId: 'navmath', clientVersion: '1');
      return ActivationErrorCode.unknown;
    } on LicenseException catch (e) {
      return e.error.code;
    }
  }

  test('409 cap_exceeded -> capExceeded with meta', () async {
    final c = ActivationClient(
        baseUrl: Uri.parse('https://portal.prograde.aero'),
        client: MockClient((_) async =>
            http.Response(jsonEncode({'code': 'cap_exceeded', 'cap': 5, 'used': 5}), 409)));
    try {
      await c.activate(auth: const AuthMode.session('t'), fingerprint: fp(), appId: 'navmath', clientVersion: '1');
      fail('expected');
    } on LicenseException catch (e) {
      expect(e.error.code, ActivationErrorCode.capExceeded);
      expect(e.error.meta?.cap, 5);
      expect(e.error.meta?.used, 5);
    }
  });

  test('401 invalid_session -> invalidSession', () async {
    expect(await codeFor(() => http.Response(jsonEncode({'code': 'invalid_session'}), 401)),
        ActivationErrorCode.invalidSession);
  });

  test('5xx -> networkUnreachable', () async {
    expect(await codeFor(() => http.Response('boom', 503)), ActivationErrorCode.networkUnreachable);
  });
}
