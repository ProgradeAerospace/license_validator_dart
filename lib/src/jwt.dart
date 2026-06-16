import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'codec.dart';
import 'errors.dart';
import 'jwks.dart';

class JwtClaims {
  JwtClaims(this.raw);
  final Map<String, dynamic> raw;

  String get iss => raw['iss'] as String;
  String get aud => raw['aud'] as String;
  String get sub => raw['sub'] as String;
  int get iat => raw['iat'] as int;
  int get exp => raw['exp'] as int;
  String get licenseId => raw['license_id'] as String;
  String get orgId => raw['org_id'] as String;
  int get slotNumber => raw['slot_number'] as int;
  String get authMethod => raw['auth_method'] as String;
  String? get userId => raw['user_id'] as String?;
  List<String>? get bundleApps =>
      (raw['bundle_apps'] as List?)?.map((e) => e as String).toList();
}

Never _fail(ActivationErrorCode code) =>
    throw LicenseException(ActivationError.fromCode(code));

class JwtVerifier {
  JwtVerifier({
    required this.expectedIssuer,
    required this.expectedAudience,
    this.clockTolerance = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime.now().toUtc());

  final String expectedIssuer;
  final String expectedAudience;
  final Duration clockTolerance;
  final DateTime Function() now;

  /// Verifies per contract §1.3. Returns claims, or throws [LicenseException].
  Future<JwtClaims> verify(String jwt, JwksDocument jwks,
      {bool skipExpCheck = false}) async {
    final parts = jwt.split('.');
    if (parts.length != 3) _fail(ActivationErrorCode.invalidSignature);

    late final Map<String, dynamic> header;
    late final Map<String, dynamic> payload;
    try {
      header = jsonDecode(utf8.decode(base64UrlNoPadDecode(parts[0])))
          as Map<String, dynamic>;
      payload = jsonDecode(utf8.decode(base64UrlNoPadDecode(parts[1])))
          as Map<String, dynamic>;
    } catch (_) {
      throw LicenseException(
          ActivationError.fromCode(ActivationErrorCode.invalidSignature));
    }

    // 2. resolve kid
    final kid = header['kid'] as String?;
    final jwk = kid == null ? null : jwks.keyForKid(kid);
    if (jwk == null) _fail(ActivationErrorCode.invalidKid);

    // 3. verify Ed25519 signature over "header.payload"
    final ok = await _verifySignature(parts, jwk);
    if (!ok) _fail(ActivationErrorCode.invalidSignature);

    final claims = JwtClaims(payload);
    final tol = clockTolerance.inSeconds;
    final nowSec = now().millisecondsSinceEpoch ~/ 1000;

    // 4. issuer
    if (claims.iss != expectedIssuer) { _fail(ActivationErrorCode.invalidIssuer); }
    // 5. audience
    if (claims.aud != expectedAudience) { _fail(ActivationErrorCode.invalidAudience); }
    // 6. exp (skippable for status endpoint)
    if (!skipExpCheck && claims.exp <= nowSec - tol) { _fail(ActivationErrorCode.licenseExpired); }
    // 7. iat not far-future (anti-replay)
    if (claims.iat > nowSec + tol) { _fail(ActivationErrorCode.invalidIat); }

    return claims;
  }

  Future<bool> _verifySignature(List<String> parts, Jwk jwk) async {
    final algo = Ed25519();
    final publicKey = SimplePublicKey(jwk.x, type: KeyPairType.ed25519);
    final signingInput = utf8.encode('${parts[0]}.${parts[1]}');
    final signature =
        Signature(base64UrlNoPadDecode(parts[2]), publicKey: publicKey);
    return algo.verify(signingInput, signature: signature);
  }
}
