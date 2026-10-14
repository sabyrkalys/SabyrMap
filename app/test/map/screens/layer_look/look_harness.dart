import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../on_screen/harness.dart';

/// Карта с Яндекс Гибридом слоем и кнопка, открывающая экран вида [open].
Future<void> pumpLook(
  WidgetTester tester,
  LayersHarness h,
  Future<void> Function(BuildContext context) open, {
  List<Override> overrides = const [],
}) async {
  await h.pump(
    tester,
    saved: stateWith(const [hybridLayer]),
    overrides: overrides,
    child: Builder(
      builder: (context) => TextButton(key: const Key('open_look'), onPressed: () => open(context), child: const Text('open')),
    ),
  );
  await tester.tap(find.byKey(const Key('open_look')));
  await tester.pumpAndSettle();
}

/// Слайдер строки [key].
Slider sliderOf(WidgetTester tester, String key) =>
    tester.widget<Slider>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Slider)));
