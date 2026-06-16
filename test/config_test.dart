import 'package:flutter_test/flutter_test.dart';
import 'package:prograde_license_validator/src/config.dart';

void main() {
  test('https issuer derived from base url', () {
    final c = ValidatorConfig(
      portalBaseUrl: Uri.parse('https://portal.prograde.aero'),
      expectedAudience: 'navmath',
    );
    expect(c.expectedIssuer, 'https://portal.prograde.aero');
  });

  test('http base url rejected unless allowInsecureLocalhost', () {
    expect(
      () => ValidatorConfig(
        portalBaseUrl: Uri.parse('http://10.0.2.2:3000'),
        expectedAudience: 'navmath',
      ),
      throwsArgumentError,
    );
    // allowed in dev
    final c = ValidatorConfig(
      portalBaseUrl: Uri.parse('http://10.0.2.2:3000'),
      expectedAudience: 'navmath',
      allowInsecureLocalhost: true,
    );
    expect(c.expectedIssuer, 'http://10.0.2.2:3000');
  });
}
