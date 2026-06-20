import 'errors.dart';
import 'jwks.dart';
import 'jwt.dart';
import 'mdm_config.dart';
import 'storage.dart';

enum ValidatorStatePhase { activated, awaitingUserActivation, awaitingUserOnboarding, error }

class ValidatorState {
  ValidatorState._(this.phase, {this.claims, this.mdmConfig, this.error});
  final ValidatorStatePhase phase;
  final JwtClaims? claims;
  final MdmConfig? mdmConfig;
  final ActivationError? error;

  factory ValidatorState.activated(JwtClaims claims) =>
      ValidatorState._(ValidatorStatePhase.activated, claims: claims);
  factory ValidatorState.awaitingUserActivation(MdmConfig c) =>
      ValidatorState._(ValidatorStatePhase.awaitingUserActivation, mdmConfig: c);
  factory ValidatorState.awaitingUserOnboarding() =>
      ValidatorState._(ValidatorStatePhase.awaitingUserOnboarding);
  factory ValidatorState.error(ActivationError e) =>
      ValidatorState._(ValidatorStatePhase.error, error: e);
}

const kJwtStorageKey = 'license.jwt';

/// Persisted mobile auth session token (from `/api/auth/sign-in/mobile`). Kept
/// so a launch with no usable license JWT can silently re-activate (and so the
/// session can be refreshed/revoked) without prompting for credentials again.
const kSessionStorageKey = 'auth.session';

/// Verification-class failures that indicate an integrity/config problem (as
/// opposed to a normal expiry or a transient network/JWKS error). When a cached
/// JWT fails for one of these, the FSM surfaces an error instead of silently
/// routing to onboarding.
const _verificationFailures = {
  ActivationErrorCode.invalidSignature,
  ActivationErrorCode.invalidIssuer,
  ActivationErrorCode.invalidAudience,
  ActivationErrorCode.invalidKid,
  ActivationErrorCode.invalidIat,
};

class FirstLaunchStateMachine {
  FirstLaunchStateMachine({
    required this.secureStore,
    required this.verifier,
    required this.loadJwks,
    required this.readMdmConfig,
  });

  final SecureStore secureStore;
  final JwtVerifier verifier;
  final Future<JwksDocument> Function() loadJwks;
  final Future<Map<String, dynamic>?> Function() readMdmConfig;

  /// Runs the first-launch FSM per contract §6 / architecture Cluster C.1.d.
  /// NOTE: MDM `preActivate=true` headless activation is wired in a later phase;
  /// here a present MDM config surfaces AWAITING_USER_ACTIVATION (no auto-activate).
  Future<ValidatorState> bootstrap() async {
    final cached = await secureStore.read(kJwtStorageKey);
    if (cached != null) {
      try {
        final jwks = await loadJwks();
        final claims = await verifier.verify(cached, jwks);
        return ValidatorState.activated(claims);
      } on LicenseException catch (e) {
        // A cached JWT that fails *verification* (bad signature/issuer/audience/
        // kid/iat) signals an integrity or config problem — surface it rather than
        // letting it masquerade as a clean first launch (which silently routes to
        // onboarding with no diagnostic). Expiry (the offline cliff) and transient
        // network/JWKS errors fall through so the user can re-onboard / retry.
        if (_verificationFailures.contains(e.error.code)) {
          return ValidatorState.error(e.error);
        }
        // fall through: expired or transient cached-JWT error
      }
    }

    final mdm = parseMdmConfig(await readMdmConfig());
    if (mdm != null) {
      return ValidatorState.awaitingUserActivation(mdm);
    }

    return ValidatorState.awaitingUserOnboarding();
  }
}
