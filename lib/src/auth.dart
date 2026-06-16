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
    // 400/401/409/410 from auth routes → treat as a session/credential problem the
    // user can correct by re-entering details or signing in again.
    throw LicenseException(ActivationError.fromCode(ActivationErrorCode.invalidSession));
  }
}
