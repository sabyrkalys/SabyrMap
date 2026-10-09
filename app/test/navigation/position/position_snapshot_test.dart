import 'package:app/navigation/position/position_snapshot.dart';
import 'package:app/navigation/position/position_source.dart';
import 'package:app/navigation/position/position_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  test('valid coordinates are valid', () {
    expect(at(50.45, 30.52).isValid, isTrue);
    expect(at(-90, 180).isValid, isTrue);
  });

  test('latitude 91 or longitude 181 is invalid', () {
    expect(at(91, 0).isValid, isFalse);
    expect(at(0, -181).isValid, isFalse);
  });

  test('NaN and infinity are invalid', () {
    expect(at(double.nan, 0).isValid, isFalse);
    expect(at(0, double.infinity).isValid, isFalse);
  });

  test('the stub source has no position', () async {
    const stub = StubPositionSource();
    expect(await stub.getCurrent(), isNull);
    expect(await stub.watch().isEmpty, isTrue);
  });

  test('PositionStream shares one subscription, throttles and drops invalid', () async {
    final source = FakePositionSource();
    var now = DateTime(2026);
    final stream = PositionStream(source, minInterval: const Duration(seconds: 1), clock: () => now);
    final a = <PositionSnapshot>[];
    final b = <PositionSnapshot>[];
    final subA = stream.stream.listen(a.add);
    final subB = stream.stream.listen(b.add);
    expect(source.watchCalls, 1);

    Future<void> send(double lat) async {
      source.controller.add(at(lat, lat));
      await Future<void>.delayed(Duration.zero);
    }

    await send(1);
    now = now.add(const Duration(milliseconds: 300));
    await send(2);
    now = now.add(const Duration(seconds: 1));
    source.controller.add(at(95, 0));
    await send(3);
    expect([for (final s in a) s.location.latitude], [1, 3]);
    expect(b, hasLength(2));

    await subA.cancel();
    await subB.cancel();
    await stream.close();
  });
}
