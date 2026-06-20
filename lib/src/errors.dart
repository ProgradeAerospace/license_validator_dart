enum SuggestedAction { retry, contactAdmin, signInAgain, releaseDevice, updateApp, waitAndRetry }

enum ActivationErrorCode {
  invalidSession('invalid_session'),
  invalidCredentials('invalid_credentials'),
  accountInactive('account_inactive'),
  orgInactive('org_inactive'),
  authUnavailable('auth_unavailable'),
  invalidKey('invalid_key'),
  noEligibleLicense('no_eligible_license'),
  appNotInLicense('app_not_in_license'),
  capExceeded('cap_exceeded'),
  licenseRevoked('license_revoked'),
  licenseExpired('license_expired'),
  platformNotSupported('platform_not_supported'),
  networkUnreachable('network_unreachable'),
  jwksUnreachable('jwks_unreachable'),
  fingerprintCollectionFailed('fingerprint_collection_failed'),
  invalidSignature('invalid_signature'),
  invalidIssuer('invalid_issuer'),
  invalidAudience('invalid_audience'),
  invalidKid('invalid_kid'),
  invalidIat('invalid_iat'),
  rateLimited('rate_limited'),
  unknown('unknown');

  const ActivationErrorCode(this.wire);
  final String wire;
}

ActivationErrorCode activationErrorCodeFromWire(String? wire) {
  for (final c in ActivationErrorCode.values) {
    if (c.wire == wire) return c;
  }
  return ActivationErrorCode.unknown;
}

class ActivationErrorMeta {
  const ActivationErrorMeta({this.cap, this.used, this.revokedAt, this.expiredAt, this.minVersion});
  final int? cap;
  final int? used;
  final String? revokedAt;
  final String? expiredAt;
  final String? minVersion;
}

class ActivationError {
  const ActivationError({
    required this.code,
    required this.recoverable,
    required this.suggestedAction,
    required this.userMessage,
    this.meta,
  });

  final ActivationErrorCode code;
  final bool recoverable;
  final SuggestedAction suggestedAction;
  final String userMessage;
  final ActivationErrorMeta? meta;

  factory ActivationError.fromCode(ActivationErrorCode code,
      {ActivationErrorMeta? meta, String? userMessage}) {
    final spec = _table[code]!;
    return ActivationError(
      code: code,
      recoverable: spec.$1,
      suggestedAction: spec.$2,
      userMessage: userMessage ?? spec.$3,
      meta: meta,
    );
  }

  @override
  String toString() => 'ActivationError(${code.wire}, $suggestedAction)';
}

/// (recoverable, suggestedAction, defaultUserMessage) per contract §5.1/§5.2.
const Map<ActivationErrorCode, (bool, SuggestedAction, String)> _table = {
  ActivationErrorCode.invalidSession:
      (true, SuggestedAction.signInAgain, 'Your session expired. Please sign in again.'),
  ActivationErrorCode.invalidCredentials:
      (true, SuggestedAction.retry, 'Incorrect email or password.'),
  ActivationErrorCode.accountInactive:
      (false, SuggestedAction.contactAdmin, 'Your account is inactive. Please contact your administrator.'),
  ActivationErrorCode.orgInactive:
      (false, SuggestedAction.contactAdmin, "Your organisation's access is suspended. Please contact your administrator."),
  ActivationErrorCode.authUnavailable:
      (true, SuggestedAction.waitAndRetry, 'The sign-in service is temporarily unavailable. Please try again shortly.'),
  ActivationErrorCode.invalidKey:
      (false, SuggestedAction.contactAdmin, 'This license key is not valid. Please contact your administrator.'),
  ActivationErrorCode.noEligibleLicense:
      (false, SuggestedAction.contactAdmin, 'Your organisation has no license for this app. Please contact your administrator.'),
  ActivationErrorCode.appNotInLicense:
      (false, SuggestedAction.contactAdmin, 'This license does not cover this app. Please contact your administrator.'),
  ActivationErrorCode.capExceeded:
      (false, SuggestedAction.releaseDevice, 'All seats for this license are in use. Please contact your administrator to release a device.'),
  ActivationErrorCode.licenseRevoked:
      (false, SuggestedAction.contactAdmin, 'This license has been revoked. Please contact your administrator.'),
  ActivationErrorCode.licenseExpired:
      (false, SuggestedAction.contactAdmin, 'This license has expired. Please contact your administrator to renew.'),
  ActivationErrorCode.platformNotSupported:
      (false, SuggestedAction.contactAdmin, 'This platform is not supported.'),
  ActivationErrorCode.networkUnreachable:
      (true, SuggestedAction.waitAndRetry, 'Cannot reach the license server. Please check your internet connection.'),
  ActivationErrorCode.jwksUnreachable:
      (true, SuggestedAction.waitAndRetry, 'Cannot reach the license server. Please check your internet connection.'),
  ActivationErrorCode.fingerprintCollectionFailed:
      (true, SuggestedAction.retry, 'Could not read this device. Please try again.'),
  ActivationErrorCode.invalidSignature:
      (true, SuggestedAction.signInAgain, 'License could not be verified. Please sign in again.'),
  ActivationErrorCode.invalidIssuer:
      (true, SuggestedAction.signInAgain, 'License could not be verified. Please sign in again.'),
  ActivationErrorCode.invalidAudience:
      (true, SuggestedAction.signInAgain, 'License could not be verified. Please sign in again.'),
  ActivationErrorCode.invalidKid:
      (true, SuggestedAction.signInAgain, 'License could not be verified. Please sign in again.'),
  ActivationErrorCode.invalidIat:
      (true, SuggestedAction.signInAgain, 'License could not be verified. Please sign in again.'),
  ActivationErrorCode.rateLimited:
      (true, SuggestedAction.waitAndRetry, 'Too many attempts. Please wait a moment and try again.'),
  ActivationErrorCode.unknown:
      (true, SuggestedAction.retry, 'Something went wrong. Please try again.'),
};

class LicenseException implements Exception {
  LicenseException(this.error);
  final ActivationError error;
  @override
  String toString() => 'LicenseException(${error.code.wire})';
}
