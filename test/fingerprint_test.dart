import 'package:flutter_test/flutter_test.dart';
import 'package:prograde_license_validator/src/fingerprint.dart';

void main() {
  test('vendorIdHash is sha256 hex of the raw vendor id', () {
    const expected = 'd2b37f78ad483dc8f453020a056e3dff12d503c4953d74066a11458cfb5d8e70';
    final fp = DeviceFingerprint(
      platform: 'ios',
      platformVersion: '17.4',
      deviceModel: 'iPhone15,2',
      bundleId: 'aero.prograde.navmath',
      rawVendorId: 'idfv-123',
      displayName: "Marcus's iPad",
    );
    expect(fp.vendorIdHash.length, 64);
    expect(fp.vendorIdHash, expected);
  });

  test('displayName trimmed and capped at 120 chars', () {
    final fp = DeviceFingerprint(
      platform: 'android', platformVersion: '14', deviceModel: 'Pixel',
      bundleId: 'aero.prograde.navmath', rawVendorId: 'x',
      displayName: '  ${'a' * 200}  ',
    );
    expect(fp.displayName.length, 120);
    expect(fp.toActivationJson()['fingerprint']['vendorIdHash'], fp.vendorIdHash);
  });
}
