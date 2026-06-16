import 'package:http/http.dart' as http;
import 'activation.dart';
import 'auth.dart';
import 'config.dart';
import 'fingerprint.dart';
import 'jwks.dart';
import 'jwt.dart';
import 'state_machine.dart';
import 'status.dart';
import 'storage.dart';

/// Public facade tying together activation, verification, status, and the
/// first-launch state machine. App code uses this; everything else is internal.
class LicenseValidator {
  LicenseValidator({
    required this.config,
    required SecureStore secureStore,
    required KeyValueStore jwksStore,
    required http.Client httpClient,
    required Future<Map<String, dynamic>?> Function() readMdmConfig,
    DateTime Function()? now,
  })  : _secureStore = secureStore,
        _readMdmConfig = readMdmConfig,
        _verifier = JwtVerifier(
          expectedIssuer: config.expectedIssuer,
          expectedAudience: config.expectedAudience,
          clockTolerance: config.clockTolerance,
          now: now,
        ),
        _jwks = JwksCache(
          baseUrl: config.portalBaseUrl,
          client: httpClient,
          store: jwksStore,
          now: now,
        ),
        _activation = ActivationClient(baseUrl: config.portalBaseUrl, client: httpClient),
        _status = StatusClient(baseUrl: config.portalBaseUrl, client: httpClient),
        _auth = AuthClient(baseUrl: config.portalBaseUrl, client: httpClient);

  final ValidatorConfig config;
  final SecureStore _secureStore;
  final Future<Map<String, dynamic>?> Function() _readMdmConfig;
  final JwtVerifier _verifier;
  final JwksCache _jwks;
  final ActivationClient _activation;
  final StatusClient _status;
  final AuthClient _auth;

  Future<ValidatorState> bootstrap() => FirstLaunchStateMachine(
        secureStore: _secureStore,
        verifier: _verifier,
        loadJwks: _jwks.current,
        readMdmConfig: _readMdmConfig,
      ).bootstrap();

  Future<ActivationResult> activateWithSession({
    required String token,
    required DeviceFingerprint fingerprint,
    required String clientVersion,
  }) async {
    final res = await _activation.activate(
      auth: AuthMode.session(token),
      fingerprint: fingerprint,
      appId: config.expectedAudience,
      clientVersion: clientVersion,
    );
    await _secureStore.write(kJwtStorageKey, res.jwt);
    return res;
  }

  Future<ActivationResult> activateWithLicenseKey({
    required String licenseKey,
    required DeviceFingerprint fingerprint,
    required String clientVersion,
  }) async {
    final res = await _activation.activate(
      auth: AuthMode.licenseKey(licenseKey),
      fingerprint: fingerprint,
      appId: config.expectedAudience,
      clientVersion: clientVersion,
    );
    await _secureStore.write(kJwtStorageKey, res.jwt);
    return res;
  }

  /// Sign in with email+password, activate this device, store the JWT, and
  /// return the resulting ACTIVATED state. Throws [LicenseException] on failure.
  Future<ValidatorState> signInAndActivate({
    required String email,
    required String password,
    required DeviceFingerprint fingerprint,
    required String clientVersion,
  }) async {
    final token = await _auth.signIn(email: email, password: password);
    await activateWithSession(
        token: token, fingerprint: fingerprint, clientVersion: clientVersion);
    return bootstrap();
  }

  /// Redeem an invite (sets the account password), activate, store the JWT, and
  /// return the resulting ACTIVATED state. Throws [LicenseException] on failure.
  Future<ValidatorState> redeemInviteAndActivate({
    required String code,
    required String password,
    required String displayName,
    required DeviceFingerprint fingerprint,
    required String clientVersion,
  }) async {
    final token = await _auth.redeemInvite(
        code: code, password: password, displayName: displayName);
    await activateWithSession(
        token: token, fingerprint: fingerprint, clientVersion: clientVersion);
    return bootstrap();
  }

  /// Polls status for the currently-stored JWT. Returns null if no JWT stored.
  Future<LicenseStatus?> refreshStatus() async {
    final jwt = await _secureStore.read(kJwtStorageKey);
    if (jwt == null) return null;
    final jwks = await _jwks.current();
    final claims = await _verifier.verify(jwt, jwks, skipExpCheck: true);
    return _status.fetch(licenseId: claims.licenseId, jwt: jwt);
  }

  /// Clears stored credentials (sign-out / fail-closed).
  Future<void> clear() => _secureStore.delete(kJwtStorageKey);
}
