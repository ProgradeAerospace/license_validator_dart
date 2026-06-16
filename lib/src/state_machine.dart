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
      } on LicenseException {
        // fall through: invalid/expired cached JWT
      }
    }

    final mdm = parseMdmConfig(await readMdmConfig());
    if (mdm != null) {
      return ValidatorState.awaitingUserActivation(mdm);
    }

    return ValidatorState.awaitingUserOnboarding();
  }
}
