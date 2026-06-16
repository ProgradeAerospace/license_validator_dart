import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:prograde_license_validator/src/codec.dart';

void main() {
  test('decodes unpadded base64url', () {
    // "abc" -> YWJj (no padding needed); "ab" -> YWI (needs padding)
    expect(utf8.decode(base64UrlNoPadDecode('YWJj')), 'abc');
    expect(utf8.decode(base64UrlNoPadDecode('YWI')), 'ab');
  });

  test('encodes to unpadded base64url', () {
    expect(base64UrlNoPadEncode(utf8.encode('ab')), 'YWI');
  });

  test('round-trips bytes', () {
    final bytes = List<int>.generate(32, (i) => i * 7 % 256);
    expect(base64UrlNoPadDecode(base64UrlNoPadEncode(bytes)), bytes);
  });
}
