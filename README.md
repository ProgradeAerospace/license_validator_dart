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
      portalBaseUrl: Uri.parse('https://portal.progradeaerospace.com.au'),
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

The suite covers activation, JWT verification, JWKS caching, state machine, MDM config parsing, storage, errors, and the canonical cross-package contract fixtures.

---

## Contract fixtures (Pattern #12)

`test/fixtures/fixtures.json` is a **vendored copy** of the canonical cross-package fixture file defined by `license-validator-contract.md` §7 and generated in the portal repo. `test/contract_fixtures_test.dart` runs every fixture: JWT fixtures through `JwtVerifier`/`JwksDocument`, MDM fixtures through `parseMdmConfig`, and HTTP-error fixtures through the `ActivationClient` error mapping. The Swift package (`ProgradeLicenseValidator`) runs the identical file, so both validators are pinned to the same decisions.

Sync procedure (whenever the contract or fixtures change):

1. In the portal repo: `npm run generate-validator-fixtures` (emits `portal/docs/specs/fixtures.json`).
2. Copy it over `test/fixtures/fixtures.json` here and `Tests/ProgradeLicenseValidatorTests/Resources/fixtures.json` in `ProgradeLicenseValidator`.
3. Run `flutter test` here and `swift test` in the Swift package.
4. Commit all three repos in lockstep. Never hand-edit the vendored file.

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

## Portal integration notes

- **Activation request body:** `clientVersion` is sent **inside** the `fingerprint` object (not at the top level of the request body), matching the portal `/api/licenses/activate` route contract. The body shape is `{ "appId": "...", "fingerprint": { ...device fields..., "clientVersion": "..." } }`.

- **Auth routes (`/api/auth/redeem-invite/mobile`, `/api/auth/sign-in/mobile`):** Callers **must** send an `Origin: <portal origin>` header — Neon Auth (Better Auth) CSRF rejects server-side calls without it with `403 "Missing or null Origin"`. The validator's own `/api/licenses/activate` and `/api/licenses/:id/status` calls do **not** go through Neon Auth and do not need this header, but the app's onboarding and sign-in screens (e.g. in NavMath) must send it.

- **`statusUrl` in activation response:** The `statusUrl` field returned by activate may be an absolute URL. The validator ignores it and uses the `license_id` claim from the signed JWT for all status polling — this is already the implemented behaviour.

---

## Status

**Phase 1 complete** — sign-in / user-account activation path is fully implemented and tested.

**Later phases (not yet implemented):**
- Native MDM config readers (iOS `UserDefaults`, Android `RestrictionsManager`).
- MDM headless pre-activation (`preActivate: true`).
- Live `FingerprintCollector` using `device_info_plus` / `package_info_plus`.
