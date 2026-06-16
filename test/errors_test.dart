import 'package:flutter_test/flutter_test.dart';
import 'package:prograde_license_validator/src/errors.dart';

void main() {
  test('wire string round-trips to enum', () {
    expect(activationErrorCodeFromWire('cap_exceeded'), ActivationErrorCode.capExceeded);
    expect(ActivationErrorCode.invalidSession.wire, 'invalid_session');
    expect(activationErrorCodeFromWire('nonsense'), ActivationErrorCode.unknown);
  });

  test('cap_exceeded maps to release_device, not recoverable', () {
    final e = ActivationError.fromCode(ActivationErrorCode.capExceeded,
        meta: const ActivationErrorMeta(cap: 5, used: 5));
    expect(e.suggestedAction, SuggestedAction.releaseDevice);
    expect(e.recoverable, isFalse);
    expect(e.meta?.cap, 5);
    expect(e.userMessage, contains('seats'));
  });

  test('invalid_session is recoverable -> sign_in_again', () {
    final e = ActivationError.fromCode(ActivationErrorCode.invalidSession);
    expect(e.suggestedAction, SuggestedAction.signInAgain);
    expect(e.recoverable, isTrue);
  });

  test('LicenseException carries the error', () {
    final e = ActivationError.fromCode(ActivationErrorCode.networkUnreachable);
    expect(LicenseException(e).error.code, ActivationErrorCode.networkUnreachable);
  });
}
