import 'package:flutter_test/flutter_test.dart';
import 'package:prograde_license_validator/src/storage.dart';

void main() {
  test('InMemorySecureStore read/write/delete', () async {
    final s = InMemorySecureStore();
    expect(await s.read('jwt'), isNull);
    await s.write('jwt', 'abc');
    expect(await s.read('jwt'), 'abc');
    await s.delete('jwt');
    expect(await s.read('jwt'), isNull);
  });

  test('InMemoryKeyValueStore read/write', () async {
    final s = InMemoryKeyValueStore();
    await s.write('k', 'v');
    expect(await s.read('k'), 'v');
  });
}
