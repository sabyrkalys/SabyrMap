import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('read returns null before anything is written', () async {
    final storage = FakeTokenStorage();

    expect(await storage.read(), isNull);
  });

  test('write then read returns the stored token', () async {
    final storage = FakeTokenStorage();

    await storage.write('token-123');

    expect(await storage.read(), 'token-123');
  });

  test('delete clears the stored token', () async {
    final storage = FakeTokenStorage();
    await storage.write('token-123');

    await storage.delete();

    expect(await storage.read(), isNull);
  });
}
