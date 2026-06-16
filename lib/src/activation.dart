import 'dart:convert';
import 'package:http/http.dart' as http;
import 'errors.dart';
import 'fingerprint.dart';

enum LicenseScope { app, bundle }

class AuthMode {
  const AuthMode._(this._header);
  const AuthMode.session(String token) : this._('Bearer $token');
  const AuthMode.licenseKey(String key) : this._('License $key');
  final String _header;
  String get authorizationHeader => _header;
}

class ActivationResult {
  ActivationResult({
    required this.jwt,
    required this.expiresAt,
    required this.statusUrl,
    required this.refreshAfter,
    required this.slotNumber,
    required this.minValidatorVersion,
    required this.scope,
    required this.appsIncluded,
  });
  final String jwt;
  final String expiresAt;
  final String statusUrl;
  final String refreshAfter;
  final int slotNumber;
  final String minValidatorVersion;
  final LicenseScope scope;
  final List<String> appsIncluded;

  factory ActivationResult.fromJson(Map<String, dynamic> j) {
    final jwtVal = j['jwt'];
    if (jwtVal == null) {
      throw const FormatException('missing jwt');
    }
    final lic = (j['license'] as Map<String, dynamic>?) ?? const {};
    return ActivationResult(
      jwt: jwtVal as String,
      expiresAt: j['expiresAt'] as String,
      statusUrl: j['statusUrl'] as String,
      refreshAfter: j['refreshAfter'] as String,
      slotNumber: (j['slotNumber'] as num).toInt(),
      minValidatorVersion: j['minValidatorVersion'] as String,
      scope: (lic['scope'] == 'bundle') ? LicenseScope.bundle : LicenseScope.app,
      appsIncluded: ((lic['appsIncluded'] as List?) ?? const []).map((e) => e as String).toList(),
    );
  }
}

class ActivationClient {
  ActivationClient({required this.baseUrl, required this.client});
  final Uri baseUrl;
  final http.Client client;

  Future<ActivationResult> activate({
    required AuthMode auth,
    required DeviceFingerprint fingerprint,
    required String appId,
    required String clientVersion,
  }) async {
    http.Response res;
    try {
      final fpJson = fingerprint.toActivationJson();
      (fpJson['fingerprint'] as Map<String, dynamic>)['clientVersion'] = clientVersion;
      res = await client.post(
        baseUrl.resolve('/api/licenses/activate'),
        headers: {
          'authorization': auth.authorizationHeader,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          ...fpJson,
          'appId': appId,
        }),
      );
    } catch (_) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
    }

    if (res.statusCode == 200) {
      try {
        return ActivationResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      } catch (_) {
        throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
      }
    }
    throw LicenseException(_mapError(res));
  }

  ActivationError _mapError(http.Response res) {
    if (res.statusCode >= 500) {
      return ActivationError.fromCode(ActivationErrorCode.networkUnreachable);
    }
    Map<String, dynamic> body = const {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {/* non-JSON error body */}
    final code = activationErrorCodeFromWire(body['code'] as String?);
    return ActivationError.fromCode(
      code,
      meta: ActivationErrorMeta(
        cap: body['cap'] as int?,
        used: body['used'] as int?,
        revokedAt: body['revokedAt'] as String?,
        expiredAt: body['expiredAt'] as String?,
      ),
    );
  }
}
