import 'package:flutter_test/flutter_test.dart';
import 'package:prograde_license_validator/src/mdm_config.dart';

void main() {
  test('valid v1 config parses', () {
    final c = parseMdmConfig({
      'schemaVersion': 1,
      'licenseKey': 'lk_a1b2c3d4e5f607182930415263748596',
      'portalEnvironment': 'production',
      'preActivate': true,
    });
    expect(c, isNotNull);
    expect(c!.licenseKey, 'lk_a1b2c3d4e5f607182930415263748596');
    expect(c.portalEnvironment, 'production');
    expect(c.preActivate, isTrue);
  });

  test('unknown schema version -> null', () {
    expect(parseMdmConfig({'schemaVersion': 99, 'licenseKey': 'lk_a1b2c3d4e5f607182930415263748596'}), isNull);
  });

  test('malformed key -> null', () {
    expect(parseMdmConfig({'schemaVersion': 1, 'licenseKey': 'not_a_valid_key'}), isNull);
  });

  test('unknown environment falls through to production', () {
    final c = parseMdmConfig({
      'schemaVersion': 1,
      'licenseKey': 'lk_a1b2c3d4e5f607182930415263748596',
      'portalEnvironment': 'narnia',
    });
    expect(c!.portalEnvironment, 'production');
  });

  test('preActivate defaults to false', () {
    final c = parseMdmConfig({'schemaVersion': 1, 'licenseKey': 'lk_a1b2c3d4e5f607182930415263748596'});
    expect(c!.preActivate, isFalse);
  });

  test('null/empty -> null', () {
    expect(parseMdmConfig(null), isNull);
    expect(parseMdmConfig({}), isNull);
  });
}
