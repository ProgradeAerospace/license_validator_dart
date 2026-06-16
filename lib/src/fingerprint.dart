import 'dart:convert';
import 'package:crypto/crypto.dart';

class DeviceFingerprint {
  DeviceFingerprint({
    required this.platform,
    required this.platformVersion,
    required this.deviceModel,
    required this.bundleId,
    required String rawVendorId,
    required String displayName,
  })  : vendorIdHash = sha256.convert(utf8.encode(rawVendorId)).toString(),
        displayName = _cap(displayName);

  final String platform; // ios | android | macos | windows
  final String platformVersion;
  final String deviceModel;
  final String bundleId;
  final String vendorIdHash; // 64-char hex
  final String displayName;

  static String _cap(String s) {
    final t = s.trim();
    return t.length > 120 ? t.substring(0, 120) : t;
  }

  Map<String, dynamic> toActivationJson() => {
        'fingerprint': {
          'platform': platform,
          'platformVersion': platformVersion,
          'deviceModel': deviceModel,
          'bundleId': bundleId,
          'vendorIdHash': vendorIdHash,
          'displayName': displayName,
        },
      };
}
