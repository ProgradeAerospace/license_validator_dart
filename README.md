# prograde_license_validator

Dart/Flutter package implementing the Prograde license-validator wire contract (sign-in / user-account path) for NavMath. It handles JWT-based device activation, first-launch bootstrapping, and license status polling.

The canonical contract lives in the portal repo at `docs/specs/license-validator-contract.md`. This package implements Phase 1 of that contract (sign-in path). MDM headless activation and native platform readers are a later phase.

---

## Public API

### `LicenseValidator`

The top-level facade. Construct it once at app startup and inject it wherever license state is needed.

```dart
LicenseValidator({
  required ValidatorConfig config,
  required SecureStore secureStore,
  required KeyValueStore jwksStore,
  required http.Client httpClient,
  required Future<Map<String, dynamic>?> Function() readMdmConfig,
})
```

#### Methods

| Method | Description |
|--------|-------------|
| `Future<ValidatorState> bootstrap()` | Runs the first-launch FSM. Returns `activated` if a valid cached JWT exists, `awaitingUserActivation` if an MDM config is present, or `awaitingUserOnboarding` if neither. |
| `Future<ActivationResult> activateWithSession({required String token, required DeviceFingerprint fingerprint, required String clientVersion})` | Exchanges a bearer token (from the portal sign-in / invite-redeem flow) for a signed license JWT and persists it. |
| `Future<ActivationResult> activateWithLicenseKey({required String licenseKey, required DeviceFingerprint fingerprint, required String clientVersion})` | Exchanges a license key (`lk_...`) for a signed license JWT and persists it. |
| `Future<LicenseStatus?> refreshStatus()` | Polls the portal for live license status using the stored JWT. Returns `null` if no JWT is stored. |
| `Future<void> clear()` | Deletes the stored JWT (sign-out / fail-closed). |

### `ValidatorState` / `ValidatorStatePhase`

`bootstrap()` returns a `ValidatorState` whose `.phase` is one of:

```dart
enum ValidatorStatePhase {
  activated,               // valid JWT in store — user is licensed
  awaitingUserActivation,  // MDM config present — show activation UI
  awaitingUserOnboarding,  // no JWT, no MDM — show sign-in / invite UI
  error,                   // non-recoverable error during bootstrap
}
```

`ValidatorState.claims` holds the decoded `JwtClaims` when `phase == activated`.

### `ActivationError` / `LicenseException`

Errors from activation and JWT verification surface as `LicenseException(error)` where `error` is an `ActivationError`:

```dart
class ActivationError {
  final ActivationErrorCode code;       // enum, e.g. invalidSession, capExceeded
  final bool recoverable;
  final SuggestedAction suggestedAction; // retry | contactAdmin | signInAgain | ...
  final String userMessage;              // human-readable, safe to show in UI
  final ActivationErrorMeta? meta;       // cap/used/expiry details where relevant
}
```

`SuggestedAction` values: `retry`, `contactAdmin`, `signInAgain`, `releaseDevice`, `updateApp`, `waitAndRetry`.

---

## Minimal wiring example

```dart
import 'package:http/http.dart' as http;
import 'package:prograde_license_validator/src/validator.dart';
import 'package:prograde_license_validator/src/config.dart';
import 'package:prograde_license_validator/src/storage_flutter.dart';
import 'package:prograde_license_validator/src/mdm_config.dart';

Future<LicenseValidator> buildValidator() async {
  return LicenseValidator(
    config: ValidatorConfig(
      portalBaseUrl: Uri.parse('https://portal.prograde.aero'),
      expectedAudience: 'navmath',
    ),
    secureStore: FlutterSecureStore(),
    jwksStore: await SharedPrefsKeyValueStore.create(),
    httpClient: http.Client(),
    // readPlatformMdmConfig is currently a stub returning null.
    // Native MDM readers (iOS UserDefaults / Android RestrictionsManager)
    // are wired in a later phase.
    readMdmConfig: readPlatformMdmConfig,
  );
}
```

**Device fingerprint (Phase 1 — manual construction):** The live `FingerprintCollector` that reads `device_info_plus` / `package_info_plus` is a later phase. For now, construct `DeviceFingerprint` with known values or collect the fields yourself:

```dart
import 'package:prograde_license_validator/src/fingerprint.dart';

final fingerprint = DeviceFingerprint(
  platform: 'ios',
  platformVersion: '17.4',
  deviceModel: 'iPhone15,2',
  bundleId: 'aero.prograde.navmath',
  rawVendorId: identifierForVendor,   // from device_info_plus
  displayName: deviceName,
);
```

---

## Running the unit tests

```bash
flutter test
```

52 tests covering activation, JWT verification, JWKS caching, state machine, MDM config parsing, storage, errors, and contract conformance fixtures.

---

## Gated end-to-end test against a local portal

The e2e test lives in `test/integration_test_local/e2e_local_test.dart`. It is **skipped automatically** when the required env vars are absent, so `flutter test` stays hermetic.

To run it against a real portal:

```bash
E2E_PORTAL_URL=http://localhost:3000 \
E2E_INVITE_CODE=<invite-code> \
E2E_PASSWORD=Passw0rd! \
flutter test test/integration_test_local/e2e_local_test.dart
```

**Prerequisites:**

- The portal must be running with a bootstrapped signing key (JWKS endpoint reachable at `$E2E_PORTAL_URL/.well-known/jwks.json`).
- A navmath license and an unused invite code must be seeded in the portal database.
- See the portal runbook `docs/runbooks/local-licensing-dev.md` for setup steps.

**Issuer gotcha:** The JWT `iss` claim is compared verbatim against `portalBaseUrl` (trailing slash stripped). It must exactly match the portal's `NEXT_PUBLIC_APP_URL` env var. A mismatch produces an `invalidIssuer` error even when the portal is reachable.

---

## Status

**Phase 1 complete** — sign-in / user-account activation path is fully implemented and tested.

**Later phases (not yet implemented):**
- Native MDM config readers (iOS `UserDefaults`, Android `RestrictionsManager`).
- MDM headless pre-activation (`preActivate: true`).
- Live `FingerprintCollector` using `device_info_plus` / `package_info_plus`.
