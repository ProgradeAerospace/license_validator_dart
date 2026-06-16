import 'codec.dart';

class Jwk {
  Jwk({required this.kid, required this.x, required this.status});
  final String kid;
  final List<int> x; // decoded Ed25519 public key bytes
  final String status;

  factory Jwk.fromJson(Map<String, dynamic> j) => Jwk(
        kid: j['kid'] as String,
        x: base64UrlNoPadDecode(j['x'] as String),
        status: (j['status'] as String?) ?? 'current',
      );
}

class JwksDocument {
  JwksDocument(this.keys);
  final List<Jwk> keys;

  factory JwksDocument.fromJson(Map<String, dynamic> j) => JwksDocument(
        ((j['keys'] as List?) ?? const [])
            .map((e) => Jwk.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Jwk? keyForKid(String kid) {
    for (final k in keys) {
      if (k.kid == kid) return k;
    }
    return null;
  }
}
