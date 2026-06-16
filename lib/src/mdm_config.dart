final RegExp _kKeyFormat = RegExp(r'^lk_[0-9a-f]{32}$');
const _kAllowedEnvs = {'production', 'staging'};

class MdmConfig {
  MdmConfig({
    required this.schemaVersion,
    required this.licenseKey,
    required this.portalEnvironment,
    required this.preActivate,
    this.minValidatorVersion,
  });
  final int schemaVersion;
  final String licenseKey;
  final String portalEnvironment;
  final bool preActivate;
  final String? minValidatorVersion;
}

/// Normalises a raw managed-config map to the canonical [MdmConfig], or null
/// when absent/unreadable (app falls back to user-account onboarding).
/// Per docs/specs/mdm-managed-config-schema.md "Validation behaviour summary".
MdmConfig? parseMdmConfig(Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return null;

  final schemaVersion = raw['schemaVersion'];
  if (schemaVersion is! int) return null;
  // Validator only knows schema v1; anything else cannot be safely interpreted.
  if (schemaVersion != 1) return null;

  final key = raw['licenseKey'];
  if (key is! String || !_kKeyFormat.hasMatch(key)) return null;

  var env = (raw['portalEnvironment'] as String?) ?? 'production';
  if (!_kAllowedEnvs.contains(env)) env = 'production';

  final pre = raw['preActivate'];
  return MdmConfig(
    schemaVersion: schemaVersion,
    licenseKey: key,
    portalEnvironment: env,
    preActivate: pre is bool ? pre : false,
    minValidatorVersion: raw['minValidatorVersion'] as String?,
  );
}

/// Reads the platform managed-config. STUBBED in Phase 1 — returns null so the
/// state machine routes to user-account onboarding. A later phase wires the
/// native platform channel (iOS UserDefaults / Android RestrictionsManager).
Future<Map<String, dynamic>?> readPlatformMdmConfig() async => null;
