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

  // Internal: builds from an already-hashed vendor id (used by [copyWith]).
  DeviceFingerprint._({
    required this.platform,
    required this.platformVersion,
    required this.deviceModel,
    required this.bundleId,
    required this.vendorIdHash,
    required String displayName,
  }) : displayName = _cap(displayName);

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

  /// Returns a copy with a different [displayName] (e.g. a user-entered device
  /// name at onboarding), preserving the already-hashed vendor id.
  DeviceFingerprint copyWith({String? displayName}) => DeviceFingerprint._(
        platform: platform,
        platformVersion: platformVersion,
        deviceModel: deviceModel,
        bundleId: bundleId,
        vendorIdHash: vendorIdHash,
        displayName: displayName ?? this.displayName,
      );

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
