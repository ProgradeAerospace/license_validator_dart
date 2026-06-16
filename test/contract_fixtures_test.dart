import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/mdm_config.dart';
import 'package:prograde_license_validator/src/activation.dart';
import 'package:prograde_license_validator/src/fingerprint.dart';
import 'package:prograde_license_validator/src/errors.dart';

DeviceFingerprint fp() => DeviceFingerprint(
      platform: 'ios', platformVersion: '17', deviceModel: 'm',
      bundleId: 'aero.prograde.navmath', rawVendorId: 'v', displayName: 'd');

void main() {
  final data = jsonDecode(File('test/fixtures/contract_fixtures.json').readAsStringSync())
      as Map<String, dynamic>;

  group('MDM fixtures', () {
    for (final f in (data['mdm'] as List).cast<Map<String, dynamic>>()) {
      test(f['name'], () {
        final c = parseMdmConfig((f['raw'] as Map).cast<String, dynamic>());
        final expect_ = f['expect'];
        if (expect_ == null) {
          expect(c, isNull);
        } else {
          final e = (expect_ as Map).cast<String, dynamic>();
          if (e.containsKey('licenseKey')) expect(c!.licenseKey, e['licenseKey']);
          if (e.containsKey('portalEnvironment')) expect(c!.portalEnvironment, e['portalEnvironment']);
          if (e.containsKey('preActivate')) expect(c!.preActivate, e['preActivate']);
        }
      });
    }
  });

  group('Activation-error fixtures', () {
    for (final f in (data['activationErrors'] as List).cast<Map<String, dynamic>>()) {
      test(f['name'], () async {
        final client = MockClient((_) async => http.Response(
            f['body'] == null ? 'x' : jsonEncode(f['body']), f['status'] as int));
        final c = ActivationClient(
            baseUrl: Uri.parse('https://portal.prograde.aero'), client: client);
        try {
          await c.activate(auth: const AuthMode.session('t'), fingerprint: fp(), appId: 'navmath', clientVersion: '1');
          fail('expected LicenseException');
        } on LicenseException catch (ex) {
          final e = (f['expect'] as Map).cast<String, dynamic>();
          expect(ex.error.code.wire, e['code']);
          expect(ex.error.recoverable, e['recoverable']);
          expect(ex.error.suggestedAction.name, e['suggestedAction']);
          if (e.containsKey('cap')) expect(ex.error.meta?.cap, e['cap']);
          if (e.containsKey('used')) expect(ex.error.meta?.used, e['used']);
        }
      });
    }
  });
}
