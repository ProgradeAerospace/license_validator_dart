import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/status.dart';

void main() {
  test('active status parsed', () async {
    final client = MockClient((req) async {
      expect(req.headers['authorization'], 'License jwt-xyz');
      return http.Response(jsonEncode({'active': true, 'expiresAt': '2026-06-01T00:00:00Z'}), 200);
    });
    final c = StatusClient(baseUrl: Uri.parse('https://portal.prograde.aero'), client: client);
    final s = await c.fetch(licenseId: 'license-1', jwt: 'jwt-xyz');
    expect(s.active, isTrue);
    expect(s.reason, isNull);
  });

  test('revoked status parsed', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({'active': false, 'reason': 'revoked', 'revokedAt': '2026-05-15T14:32:11Z', 'expiresAt': '2026-06-01T00:00:00Z'}),
        200));
    final c = StatusClient(baseUrl: Uri.parse('https://portal.prograde.aero'), client: client);
    final s = await c.fetch(licenseId: 'license-1', jwt: 'jwt-xyz');
    expect(s.active, isFalse);
    expect(s.reason, LicenseStatusReason.revoked);
    expect(s.revokedAt, '2026-05-15T14:32:11Z');
  });

  test('uses /api/licenses/{id}/status path', () async {
    late Uri url;
    final client = MockClient((req) async {
      url = req.url;
      return http.Response(jsonEncode({'active': true, 'expiresAt': 'x'}), 200);
    });
    final c = StatusClient(baseUrl: Uri.parse('https://portal.prograde.aero'), client: client);
    await c.fetch(licenseId: 'lic-42', jwt: 'j');
    expect(url.path, '/api/licenses/lic-42/status');
  });
}
