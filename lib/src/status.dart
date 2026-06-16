import 'dart:convert';
import 'package:http/http.dart' as http;
import 'errors.dart';

enum LicenseStatusReason { revoked, expired, capChanged, unknown }

LicenseStatusReason? _reason(String? w) {
  switch (w) {
    case null:
      return null;
    case 'revoked':
      return LicenseStatusReason.revoked;
    case 'expired':
      return LicenseStatusReason.expired;
    case 'cap_changed':
      return LicenseStatusReason.capChanged;
    default:
      return LicenseStatusReason.unknown;
  }
}

class LicenseStatus {
  LicenseStatus({required this.active, this.reason, this.revokedAt, this.expiredAt, this.expiresAt});
  final bool active;
  final LicenseStatusReason? reason;
  final String? revokedAt;
  final String? expiredAt;
  final String? expiresAt;

  factory LicenseStatus.fromJson(Map<String, dynamic> j) => LicenseStatus(
        active: j['active'] as bool,
        reason: _reason(j['reason'] as String?),
        revokedAt: j['revokedAt'] as String?,
        expiredAt: j['expiredAt'] as String?,
        expiresAt: j['expiresAt'] as String?,
      );
}

class StatusClient {
  StatusClient({required this.baseUrl, required this.client});
  final Uri baseUrl;
  final http.Client client;

  Future<LicenseStatus> fetch({required String licenseId, required String jwt}) async {
    http.Response res;
    try {
      res = await client.get(
        baseUrl.resolve('/api/licenses/$licenseId/status'),
        headers: {'authorization': 'License $jwt'},
      );
    } catch (_) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
    }
    if (res.statusCode == 200) {
      try {
        return LicenseStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      } catch (_) {
        throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
      }
    }
    if (res.statusCode == 401) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.invalidSession));
    }
    if (res.statusCode == 429) {
      throw LicenseException(ActivationError.fromCode(ActivationErrorCode.rateLimited));
    }
    throw LicenseException(ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
  }
}
