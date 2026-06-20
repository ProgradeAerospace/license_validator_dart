import 'dart:convert';
import 'package:http/http.dart' as http;
import 'errors.dart';

/// Releases THIS device's own seat server-side, authenticated by its license JWT
/// (Authorization: License <jwt>). Backs the in-app "release this device" action.
/// Idempotent: a 200 is returned whether or not a seat existed. When
/// [removeFromOrg] is true the device is also detached from its organisation
/// ("remove this iPad from <Org>").
class ReleaseClient {
  ReleaseClient({required this.baseUrl, required this.client});
  final Uri baseUrl;
  final http.Client client;

  Future<void> releaseSelf(String jwt, {bool removeFromOrg = false}) async {
    http.Response res;
    try {
      res = await client.post(
        baseUrl.resolve('/api/devices/self/release'),
        headers: {
          'authorization': 'License $jwt',
          'content-type': 'application/json',
        },
        body: jsonEncode({'removeFromOrg': removeFromOrg}),
      );
    } catch (_) {
      throw LicenseException(
          ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
    }
    if (res.statusCode == 200) return;
    if (res.statusCode == 401) {
      throw LicenseException(
          ActivationError.fromCode(ActivationErrorCode.invalidSession));
    }
    throw LicenseException(
        ActivationError.fromCode(ActivationErrorCode.networkUnreachable));
  }
}
