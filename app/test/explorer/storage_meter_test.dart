import 'package:app/explorer/storage_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fractions, including 0 % and 100 % edges', () {
    expect(StorageMeter.fractionOf(239, 487), closeTo(0.4908, 1e-4));
    expect(StorageMeter.fractionOf(0, 487), 0);
    expect(StorageMeter.fractionOf(487, 487), 1);
    expect(StorageMeter.fractionOf(600, 487), 1);
    expect(StorageMeter.fractionOf(10, 0), 0);
  });

  testWidgets('the bar shows the fraction in green on grey', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StorageMeter(usedBytes: 1, totalBytes: 4))),
    );
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('storage_meter_bar')));
    expect(bar.value, 0.25);
    expect(bar.color, const Color(0xFF4CAF50));
    expect(bar.backgroundColor, const Color(0xFFE0E0E0));
  });
}
