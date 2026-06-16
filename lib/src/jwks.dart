import 'dart:convert';
import 'package:http/http.dart' as http;
import 'codec.dart';
import 'errors.dart';
import 'storage.dart';

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

class JwksCache {
  JwksCache({
    required this.baseUrl,
    required this.client,
    required this.store,
    this.ttl = const Duration(hours: 1),
    this.offlineGrace = const Duration(days: 30),
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime.now().toUtc());

  final Uri baseUrl;
  final http.Client client;
  final KeyValueStore store;
  final Duration ttl;
  final Duration offlineGrace;
  final DateTime Function() now;

  static const _docKey = 'jwks.doc';
  static const _fetchedKey = 'jwks.fetchedAtMs';

  /// Returns a usable JWKS doc, fetching/caching per §2.3. Throws
  /// LicenseException(jwksUnreachable) only when offline beyond the grace window.
  Future<JwksDocument> current() async {
    final cachedRaw = await store.read(_docKey);
    final fetchedAtMs = int.tryParse(await store.read(_fetchedKey) ?? '');
    final nowMs = now().millisecondsSinceEpoch;
    final fresh = cachedRaw != null &&
        fetchedAtMs != null &&
        nowMs - fetchedAtMs < ttl.inMilliseconds;

    if (fresh) return JwksDocument.fromJson(jsonDecode(cachedRaw) as Map<String, dynamic>);

    try {
      final res = await client.get(baseUrl.resolve('/.well-known/jwks.json'));
      if (res.statusCode != 200) throw const _Down();
      await store.write(_docKey, res.body);
      await store.write(_fetchedKey, nowMs.toString());
      return JwksDocument.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      // Offline path: serve cache if within grace, else fail closed.
      if (cachedRaw != null &&
          fetchedAtMs != null &&
          nowMs - fetchedAtMs < offlineGrace.inMilliseconds) {
        return JwksDocument.fromJson(jsonDecode(cachedRaw) as Map<String, dynamic>);
      }
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.jwksUnreachable));
    }
  }
}

class _Down implements Exception {
  const _Down();
}
