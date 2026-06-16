import 'dart:convert';

/// Decodes a base64url string that may omit `=` padding (JWT/JWK style).
List<int> base64UrlNoPadDecode(String input) {
  final pad = (4 - input.length % 4) % 4;
  return base64Url.decode(input + ('=' * pad));
}

/// Encodes bytes as base64url with padding stripped.
String base64UrlNoPadEncode(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
