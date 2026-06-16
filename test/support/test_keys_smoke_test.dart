import 'package:flutter_test/flutter_test.dart';
import 'test_keys.dart';

void main() {
  test('signer produces a 3-part JWT and a matching JWKS', () async {
    final s = await TestSigner.generate();
    final jwt = await s.navmathJwt(iatSec: 1714608000, expSec: 1717200000);
    expect(jwt.split('.').length, 3);
    expect(s.jwksDocument()['keys'][0]['x'], s.publicKeyX);
  });
}
