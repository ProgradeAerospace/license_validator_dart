import 'package:http/http.dart' as http;
import 'activation.dart';
import 'auth.dart';
import 'config.dart';
import 'errors.dart';
import 'fingerprint.dart';
import 'jwks.dart';
import 'jwt.dart';
import 'release.dart';
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
        _release = ReleaseClient(baseUrl: config.portalBaseUrl, client: httpClient),
        _auth = AuthClient(baseUrl: config.portalBaseUrl, client: httpClient);

  final ValidatorConfig config;
  final SecureStore _secureStore;
  final Future<Map<String, dynamic>?> Function() _readMdmConfig;
  final JwtVerifier _verifier;
  final JwksCache _jwks;
  final ActivationClient _activation;
  final StatusClient _status;
  final ReleaseClient _release;
  final AuthClient _auth;

  Future<ValidatorState> bootstrap() => FirstLaunchStateMachine(
        secureStore: _secureStore,
        verifier: _verifier,
        loadJwks: _jwks.current,
        readMdmConfig: _readMdmConfig,
      ).bootstrap();

  /// Cold-launch bootstrap. If there's a usable cached JWT, returns ACTIVATED.
  /// Otherwise, when a stored auth session remains, it slides the session and
  /// attempts an EXISTING-SEAT-ONLY activation (never auto-allocates): if a seat
  /// has been allocated to this device it activates; if not it returns
  /// AWAITING_LICENCE (signed in, waiting for an admin to allocate). Returns the
  /// normal onboarding/MDM state only when there is no session at all (or it
  /// proved invalid).
  ///
  /// Call this ONLY on app launch — never right after an in-app release.
  Future<ValidatorState> bootstrapOrReactivate({
    required DeviceFingerprint fingerprint,
    required String clientVersion,
  }) async {
    final state = await bootstrap();
    if (state.phase != ValidatorStatePhase.awaitingUserOnboarding) return state;

    final session = await _secureStore.read(kSessionStorageKey);
    if (session == null || session.isEmpty) return state;

    // Slide + validate the session. A proven-dead session (401) is cleared and
    // routes to onboarding; transient/offline errors keep the session and show
    // AWAITING_LICENCE so the screen can retry.
    String token;
    try {
      token = await _auth.refresh(session);
      await _secureStore.write(kSessionStorageKey, token);
    } on LicenseException catch (e) {
      if (e.error.code == ActivationErrorCode.invalidSession) {
        await _secureStore.delete(kSessionStorageKey);
        return state;
      }
      return ValidatorState.awaitingLicence();
    }

    return _activateExistingSeat(
        token: token, fingerprint: fingerprint, clientVersion: clientVersion);
  }

  /// Poll helper for the AWAITING_LICENCE screen: re-checks (existing-seat-only)
  /// whether a licence has been allocated to this device yet, unlocking the
  /// moment an admin allocates. Uses the stored session token directly (cheap to
  /// call repeatedly); a lapsed session surfaces as onboarding (the device must
  /// sign in again) — mobile sessions are long-lived, so a short wait won't
  /// expire one.
  Future<ValidatorState> checkAllocation({
    required DeviceFingerprint fingerprint,
    required String clientVersion,
  }) async {
    final session = await _secureStore.read(kSessionStorageKey);
    if (session == null || session.isEmpty) {
      return ValidatorState.awaitingUserOnboarding();
    }
    return _activateExistingSeat(
        token: session, fingerprint: fingerprint, clientVersion: clientVersion);
  }

  /// Self-service "Get a licence now": uses the stored session to allocate an
  /// available seat (allocate=true) and activate. Returns ACTIVATED on success;
  /// throws [LicenseException] (e.g. capExceeded) for the UI to surface, or
  /// returns onboarding if the session is gone.
  Future<ValidatorState> selfAllocate({
    required DeviceFingerprint fingerprint,
    required String clientVersion,
  }) async {
    final session = await _secureStore.read(kSessionStorageKey);
    if (session == null || session.isEmpty) {
      return ValidatorState.awaitingUserOnboarding();
    }
    String token = session;
    try {
      token = await _auth.refresh(session);
      await _secureStore.write(kSessionStorageKey, token);
    } on LicenseException catch (e) {
      if (e.error.code == ActivationErrorCode.invalidSession) {
        await _secureStore.delete(kSessionStorageKey);
        return ValidatorState.awaitingUserOnboarding();
      }
      // Transient refresh failure — fall through and try with the existing token.
    }
    await activateWithSession(
        token: token,
        fingerprint: fingerprint,
        clientVersion: clientVersion,
        allocate: true);
    return _bootstrapAfterActivate();
  }

  /// Existing-seat-only activation: activates if a seat is already allocated to
  /// this device. Error mapping:
  ///   noLicenceAllocated            → AWAITING_LICENCE (wait for an admin)
  ///   invalidSession                → onboarding (clear the dead session)
  ///   network/jwks unreachable      → AWAITING_LICENCE (transient; keep waiting)
  ///   any other terminal code       → error state, so the UI shows the real
  ///     reason (e.g. no_eligible_license / org_inactive / license_revoked)
  ///     instead of an endless "waiting for allocation" screen.
  Future<ValidatorState> _activateExistingSeat({
    required String token,
    required DeviceFingerprint fingerprint,
    required String clientVersion,
  }) async {
    try {
      await activateWithSession(
          token: token,
          fingerprint: fingerprint,
          clientVersion: clientVersion,
          allocate: false);
    } on LicenseException catch (e) {
      switch (e.error.code) {
        case ActivationErrorCode.noLicenceAllocated:
          return ValidatorState.awaitingLicence();
        case ActivationErrorCode.invalidSession:
          await _secureStore.delete(kSessionStorageKey);
          return ValidatorState.awaitingUserOnboarding();
        case ActivationErrorCode.networkUnreachable:
        case ActivationErrorCode.jwksUnreachable:
          return ValidatorState.awaitingLicence();
        default:
          return ValidatorState.error(e.error);
      }
    }
    return bootstrap();
  }

  Future<ActivationResult> activateWithSession({
    required String token,
    required DeviceFingerprint fingerprint,
    required String clientVersion,
    bool allocate = true,
  }) async {
    final res = await _activation.activate(
      auth: AuthMode.session(token),
      fingerprint: fingerprint,
      appId: config.expectedAudience,
      clientVersion: clientVersion,
      allocate: allocate,
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
    // Persist the session so a later launch can silently re-activate (e.g. after
    // releasing the device or once a licence is re-assigned in the portal).
    await _secureStore.write(kSessionStorageKey, token);
    await activateWithSession(
        token: token, fingerprint: fingerprint, clientVersion: clientVersion);
    return _bootstrapAfterActivate();
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
    await _secureStore.write(kSessionStorageKey, token);
    await activateWithSession(
        token: token, fingerprint: fingerprint, clientVersion: clientVersion);
    return _bootstrapAfterActivate();
  }

  /// Runs [bootstrap] immediately after a successful activate. The device was
  /// just activated and a JWT stored, so a non-activated result means that JWT
  /// failed local verification — e.g. an issuer/audience/signature mismatch
  /// between the portal and this validator's config. Surface it as a
  /// [LicenseException] instead of silently returning an onboarding state (which
  /// the UI renders as "back to sign-in" with no explanation).
  Future<ValidatorState> _bootstrapAfterActivate() async {
    final state = await bootstrap();
    if (state.phase != ValidatorStatePhase.activated) {
      throw LicenseException(state.error ??
          ActivationError.fromCode(ActivationErrorCode.invalidSignature));
    }
    return state;
  }

  /// Polls status for the currently-stored JWT. Returns null if no JWT stored.
  Future<LicenseStatus?> refreshStatus() async {
    final jwt = await _secureStore.read(kJwtStorageKey);
    if (jwt == null) return null;
    final jwks = await _jwks.current();
    final claims = await _verifier.verify(jwt, jwks, skipExpCheck: true);
    return _status.fetch(licenseId: claims.licenseId, jwt: jwt);
  }

  /// Releases this device's seat server-side (best-effort) and clears the local
  /// license JWT, but KEEPS the auth session. Backs the in-app "release this
  /// device" action: the seat is freed now, and the next app launch can silently
  /// re-activate (via [bootstrapOrReactivate]) once a licence is assigned —
  /// without asking the user to sign in again. The user always ends up released
  /// locally even if the server call fails (offline); an admin can reclaim the
  /// seat. For a full logout that also forgets the session, use [signOut].
  Future<void> releaseDevice({bool removeFromOrg = false}) async {
    final jwt = await _secureStore.read(kJwtStorageKey);
    if (jwt != null) {
      try {
        await _release.releaseSelf(jwt, removeFromOrg: removeFromOrg);
      } on LicenseException {
        // Best-effort; fall through to the local clear below.
      }
    }
    await _secureStore.delete(kJwtStorageKey);
  }

  /// Full sign-out: frees this device's seat (best-effort), revokes the auth
  /// session server-side, and clears ALL local credentials (license JWT +
  /// session). After this the user must sign in again. Contrast [releaseDevice],
  /// which keeps the session so the next launch can silently re-activate.
  Future<void> signOut() async {
    final session = await _secureStore.read(kSessionStorageKey);
    await releaseDevice();
    if (session != null && session.isNotEmpty) {
      try {
        await _auth.signOut(session);
      } on LicenseException {
        // Best-effort; clear locally regardless.
      }
    }
    await _secureStore.delete(kSessionStorageKey);
  }

  /// Clears the local license JWT only (fail-closed, e.g. on revoke/expiry).
  /// Deliberately KEEPS the auth session so that if the licence is later
  /// re-granted, the next launch can silently re-activate. Does NOT free the seat
  /// server-side (use [releaseDevice]); for a full logout use [signOut].
  Future<void> clear() => _secureStore.delete(kJwtStorageKey);
}
