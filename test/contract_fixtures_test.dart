// Cross-package contract fixtures (license-validator-contract.md §7, Pattern #12).
//
// `test/fixtures/fixtures.json` is a VENDORED COPY of the canonical file
// generated in the portal repo (`npm run generate-validator-fixtures` →
// `portal/docs/specs/fixtures.json`). Regenerate there and re-copy here —
// never edit the vendored file by hand. The Swift package
// (ProgradeLicenseValidator/Tests/.../Resources/fixtures.json) runs the
// identical file, so both validators are pinned to the same decisions.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/activation.dart';
import 'package:prograde_license_validator/src/errors.dart';
import 'package:prograde_license_validator/src/fingerprint.dart';
import 'package:prograde_license_validator/src/jwks.dart';
import 'package:prograde_license_validator/src/jwt.dart';
import 'package:prograde_license_validator/src/mdm_config.dart';

/// Canonical portal issuer baked into every JWT fixture (contract §1.2).
const kFixtureIssuer = 'https://portal.progradeaerospace.com.au';

DeviceFingerprint fp() => DeviceFingerprint(
    platform: 'ios', platformVersion: '17', deviceModel: 'm',
    bundleId: 'aero.prograde.navmath', rawVendorId: 'v', displayName: 'd');

/// SuggestedAction enum name → contract wire string (releaseDevice → release_device).
String suggestedActionWire(SuggestedAction a) => a.name
    .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

void main() {
  final data = jsonDecode(File('test/fixtures/fixtures.json').readAsStringSync())
      as Map<String, dynamic>;
  final fixtures = (data['fixtures'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> withInputKey(String key) => fixtures
      .where((f) => (f['input'] as Map<String, dynamic>).containsKey(key))
      .toList();

  test('fixture file covers the full contract §7.1 set', () {
    expect(fixtures, hasLength(16));
    expect(withInputKey('jwt'), hasLength(9));
    expect(withInputKey('mdmRaw'), hasLength(4));
    expect(withInputKey('httpResponse'), hasLength(3));
  });

  group('JWT fixtures — JwtVerifier', () {
    for (final f in withInputKey('jwt')) {
      test(f['name'], () async {
        final input = (f['input'] as Map).cast<String, dynamic>();
        final expected = (f['expectedOutput'] as Map).cast<String, dynamic>();

        final nowSec = input['now'] as int;
        final verifier = JwtVerifier(
          expectedIssuer: kFixtureIssuer,
          expectedAudience: input['expectedAudience'] as String,
          clockTolerance:
              Duration(seconds: (input['clockToleranceSec'] as int?) ?? 60),
          now: () =>
              DateTime.fromMillisecondsSinceEpoch(nowSec * 1000, isUtc: true),
        );
        final jwks = JwksDocument.fromJson(
            (input['jwksDocument'] as Map).cast<String, dynamic>());

        if (expected['type'] == 'claim') {
          final claims = await verifier.verify(input['jwt'] as String, jwks);
          final expectedClaim = (expected['claim'] as Map).cast<String, dynamic>();
          for (final entry in expectedClaim.entries) {
            expect(claims.raw[entry.key], entry.value,
                reason: "claim '${entry.key}'");
          }
        } else {
          try {
            await verifier.verify(input['jwt'] as String, jwks);
            fail('expected LicenseException(${expected['code']})');
          } on LicenseException catch (ex) {
            expect(ex.error.code.wire, expected['code']);
          }
        }
      });
    }
  });

  group('MDM fixtures — parseMdmConfig', () {
    for (final f in withInputKey('mdmRaw')) {
      test(f['name'], () {
        final raw = ((f['input'] as Map)['mdmRaw'] as Map).cast<String, dynamic>();
        final expected = (f['expectedOutput'] as Map).cast<String, dynamic>();

        final config = parseMdmConfig(raw);

        if (expected['result'] == 'null') {
          expect(config, isNull);
          return;
        }
        expect(config, isNotNull);
        if (expected.containsKey('schemaVersion')) {
          expect(config!.schemaVersion, expected['schemaVersion']);
        }
        if (expected.containsKey('licenseKey')) {
          expect(config!.licenseKey, expected['licenseKey']);
        }
        if (expected.containsKey('portalEnvironment')) {
          expect(config!.portalEnvironment, expected['portalEnvironment']);
        }
        if (expected.containsKey('preActivate')) {
          expect(config!.preActivate, expected['preActivate']);
        }
      });
    }
  });

  group('Activation-error fixtures — ActivationClient HTTP mapping', () {
    for (final f in withInputKey('httpResponse')) {
      test(f['name'], () async {
        final res = ((f['input'] as Map)['httpResponse'] as Map)
            .cast<String, dynamic>();
        final expected = (f['expectedOutput'] as Map).cast<String, dynamic>();

        final body = res['body'];
        final client = MockClient((_) async => http.Response(
            body is Map ? jsonEncode(body) : (body as String? ?? ''),
            res['status'] as int));
        final activation = ActivationClient(
            baseUrl: Uri.parse('https://portal.progradeaerospace.com.au'),
            client: client);

        try {
          await activation.activate(
              auth: const AuthMode.session('t'),
              fingerprint: fp(),
              appId: 'navmath',
              clientVersion: '1');
          fail('expected LicenseException');
        } on LicenseException catch (ex) {
          expect(ex.error.code.wire, expected['code']);
          expect(ex.error.recoverable, expected['recoverable']);
          expect(suggestedActionWire(ex.error.suggestedAction),
              expected['suggestedAction']);
          final meta = expected['meta'] as Map?;
          if (meta != null) {
            if (meta.containsKey('cap')) expect(ex.error.meta?.cap, meta['cap']);
            if (meta.containsKey('used')) {
              expect(ex.error.meta?.used, meta['used']);
            }
          }
        }
      });
    }
  });
}
