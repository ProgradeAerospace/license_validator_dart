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
    return _postForToken(
      '/api/auth/sign-in/mobile',
      {'email': email, 'password': password},
      on401: ActivationErrorCode.invalidCredentials,
    );
  }

  Future<String> redeemInvite({
    required String code,
    required String password,
    required String displayName,
  }) {
    return _postForToken(
      '/api/auth/redeem-invite/mobile',
      {'code': code, 'password': password, 'displayName': displayName},
      on401: ActivationErrorCode.invalidSession,
    );
  }

  /// Refreshes (slides) the mobile session, returning a fresh token. The current
  /// session token authenticates the call (Bearer). Throws [LicenseException]
  /// with `invalidSession` when the session is expired/revoked, or
  /// `networkUnreachable` on transport/5xx.
  Future<String> refresh(String sessionToken) async {
    http.Response res;
    try {
      res = await client.post(
        baseUrl.resolve('/api/auth/refresh/mobile'),
        headers: {'authorization': 'Bearer $sessionToken'},
      );
    } catch (_) {
      throw LicenseException(
          ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
    }
    if (res.statusCode == 200) {
      String? token;
      try {
        token =
            (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String?;
      } catch (_) {/* fallthrough */}
      if (token == null || token.isEmpty) {
        throw LicenseException(
            ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
      }
      return token;
    }
    if (res.statusCode == 401) {
      throw LicenseException(
          ActivationError.fromCode(ActivationErrorCode.invalidSession));
    }
    // Any other status (e.g. a 403/404 from a WAF or CDN edge that never
    // reached the portal) is not a session verdict — treat as unreachable so
    // callers don't clear a still-valid stored session.
    throw LicenseException(
        ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
  }

  /// Revokes the mobile session server-side (full sign-out). Best-effort: a 401
  /// (already-invalid session) counts as success; only a transport/5xx error
  /// throws, so the caller can still clear local state regardless.
  Future<void> signOut(String sessionToken) async {
    http.Response res;
    try {
      res = await client.post(
        baseUrl.resolve('/api/auth/sign-out/mobile'),
        headers: {'authorization': 'Bearer $sessionToken'},
      );
    } catch (_) {
      throw LicenseException(
          ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    if (res.statusCode == 401) return;
    throw LicenseException(
        ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
  }

  Future<String> _postForToken(
    String path,
    Map<String, dynamic> body, {
    required ActivationErrorCode on401,
  }) async {
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
      // 503 auth_unavailable (provider down / upstream rejected) vs a generic 5xx.
      throw LicenseException(ActivationError.fromCode(
        _bodyErrorCode(res.body) == 'auth_unavailable'
            ? ActivationErrorCode.authUnavailable
            : ActivationErrorCode.networkUnreachable,
      ));
    }
    if (res.statusCode == 401) {
      // The portal distinguishes a credential failure from a proven-password but
      // inactive account/org. Map each to an accurate message; otherwise fall back
      // to the caller's default (bad credentials on sign-in, invalid session elsewhere).
      switch (_bodyErrorCode(res.body)) {
        case 'account_inactive':
          throw LicenseException(
              ActivationError.fromCode(ActivationErrorCode.accountInactive));
        case 'org_inactive':
          throw LicenseException(
              ActivationError.fromCode(ActivationErrorCode.orgInactive));
        default:
          throw LicenseException(ActivationError.fromCode(on401));
      }
    }
    if (res.statusCode == 429) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.rateLimited));
    }
    if (res.statusCode == 409 || res.statusCode == 410) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.invalidSession));
    }
    if (res.statusCode == 400) {
      final errorCode = _bodyErrorCode(res.body);
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
    // Any other non-200 (e.g. a 403/404 served by a WAF or CDN edge, or a
    // deployment missing this route) never proved anything about the session
    // or credentials — surface as unreachable, not "session expired".
    throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
  }

  /// Extracts the portal's machine error code from a JSON body (`error` or
  /// `code`), or null if absent/unparseable.
  String? _bodyErrorCode(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['error'] ?? json['code']) as String?;
    } catch (_) {
      return null;
    }
  }
}
