import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:prograde_license_validator/src/codec.dart';

const kTestKid = 'k-2026-05-01';

class TestSigner {
  TestSigner(this._keyPair, this._publicKey);
  final SimpleKeyPair _keyPair;
  final SimplePublicKey _publicKey;
  final _algo = Ed25519();

  static Future<TestSigner> generate() async {
    final algo = Ed25519();
    final kp = await algo.newKeyPair();
    final pub = await kp.extractPublicKey();
    return TestSigner(kp, pub);
  }

  /// The JWKS `x` value (base64url, no pad) for this key.
  String get publicKeyX => base64UrlNoPadEncode(_publicKey.bytes);

  /// A JWKS document map containing this key as `current`.
  Map<String, dynamic> jwksDocument({String kid = kTestKid, String status = 'current'}) => {
        'keys': [
          {'kid': kid, 'kty': 'OKP', 'crv': 'Ed25519', 'x': publicKeyX, 'alg': 'EdDSA', 'use': 'sig', 'status': status},
        ],
      };

  /// Signs `{header}.{payload}` and returns a compact JWT string.
  Future<String> signJwt(Map<String, dynamic> header, Map<String, dynamic> payload) async {
    final h = base64UrlNoPadEncode(utf8.encode(jsonEncode(header)));
    final p = base64UrlNoPadEncode(utf8.encode(jsonEncode(payload)));
    final signingInput = utf8.encode('$h.$p');
    final sig = await _algo.sign(signingInput, keyPair: _keyPair);
    return '$h.$p.${base64UrlNoPadEncode(sig.bytes)}';
  }

  /// Convenience: a valid navmath JWT for the given clock.
  Future<String> navmathJwt({
    required int iatSec,
    required int expSec,
    String iss = 'https://portal.prograde.aero',
    String aud = 'navmath',
    String kid = kTestKid,
    List<String>? bundleApps,
  }) {
    return signJwt(
      {'alg': 'EdDSA', 'typ': 'JWT', 'kid': kid},
      {
        'iss': iss, 'aud': aud, 'sub': 'device-uuid-xyz',
        'iat': iatSec, 'exp': expSec,
        'license_id': 'license-uuid-abc', 'org_id': 'org-uuid',
        'slot_number': 0, 'auth_method': 'session', 'user_id': 'user-uuid',
        'bundle_apps': bundleApps,
      },
    );
  }
}
