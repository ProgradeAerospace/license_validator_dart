import 'dart:convert';
import 'package:http/http.dart' as http;
import 'errors.dart';

/// Calls the portal's mobile auth routes. These proxy Neon Auth (Better Auth),
/// whose CSRF guard rejects calls without an `Origin` header (contract §10a #2),
/// so every request sends `Origin: <portal origin>`.
class AuthClient {
  AuthClient({required this.baseUrl, required this.client});
  final Uri baseUrl;
  final http.Client client;

  // Use scheme://authority to get an exact origin with no trailing slash or '?'.
  String get _origin => '${baseUrl.scheme}://${baseUrl.authority}';

  Future<String> signIn({required String email, required String password}) {
    return _postForToken('/api/auth/sign-in/mobile', {'email': email, 'password': password});
  }

  Future<String> redeemInvite({
    required String code,
    required String password,
    required String displayName,
  }) {
    return _postForToken('/api/auth/redeem-invite/mobile',
        {'code': code, 'password': password, 'displayName': displayName});
  }

  Future<String> _postForToken(String path, Map<String, dynamic> body) async {
    http.Response res;
    try {
      res = await client.post(
        baseUrl.resolve(path),
        headers: {'content-type': 'application/json', 'origin': _origin},
        body: jsonEncode(body),
      );
    } catch (_) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
    }
    if (res.statusCode == 200) {
      String? token;
      try {
        token = (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String?;
      } catch (_) {/* fallthrough */}
      if (token == null || token.isEmpty) {
        throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
      }
      return token;
    }
    if (res.statusCode >= 500) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
    }
    if (res.statusCode == 401 || res.statusCode == 409 || res.statusCode == 410) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.invalidSession));
    }
    if (res.statusCode == 400) {
      String? errorCode;
      try {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        errorCode = (json['error'] ?? json['code']) as String?;
      } catch (_) {/* ignore parse errors */}
      if (errorCode == 'weak_password') {
        throw LicenseException(ActivationError.fromCode(
          ActivationErrorCode.unknown,
          userMessage: 'Password is too weak. Please choose a stronger password.',
        ));
      }
      throw LicenseException(ActivationError.fromCode(
        ActivationErrorCode.unknown,
        userMessage: 'Please check your details and try again.',
      ));
    }
    // any other non-200 status → treat as session/credential problem
    throw LicenseException(ActivationError.fromCode(ActivationErrorCode.invalidSession));
  }
}
