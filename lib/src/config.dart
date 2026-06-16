class ValidatorConfig {
  ValidatorConfig({
    required this.portalBaseUrl,
    required this.expectedAudience,
    this.clockTolerance = const Duration(seconds: 60),
    this.statusPollInterval = const Duration(minutes: 10),
    this.allowInsecureLocalhost = false,
  }) {
    if (portalBaseUrl.scheme != 'https' && !allowInsecureLocalhost) {
      throw ArgumentError(
          'portalBaseUrl must be https unless allowInsecureLocalhost is true (dev only): $portalBaseUrl');
    }
  }

  final Uri portalBaseUrl;
  final String expectedAudience;
  final Duration clockTolerance;
  final Duration statusPollInterval;
  final bool allowInsecureLocalhost;

  /// Expected JWT `iss` — must equal the portal's NEXT_PUBLIC_APP_URL exactly.
  String get expectedIssuer => portalBaseUrl.toString().replaceAll(RegExp(r'/$'), '');
}
