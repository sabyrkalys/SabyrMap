import 'package:app/settings/settings_panel.dart';
import 'package:app/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mainItems = ['Скрыть кнопки меню', 'Блокировка экрана', 'Снимок экрана', 'Настройки'];
  const optionItems = ['Координатная сетка СК-42 (Гаусса-Крюгера)', 'Ночной режим', 'Координаты центра экрана'];

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: SettingsPanel(arrowCenterX: 25)),
        ),
      ),
    );
  }

  Future<void> tapHeader(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings_options_header')));
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

  void expectInOrder(WidgetTester tester, List<String> texts) {
    for (var i = 1; i < texts.length; i++) {
      expect(top(tester, texts[i]), greaterThan(top(tester, texts[i - 1])), reason: texts[i]);
    }
  }

  testWidgets('opens with the main items and the options header, options collapsed', (tester) async {
    await pumpPanel(tester);

    expectInOrder(tester, [...mainItems, 'ОПЦИИ']);
    for (final item in optionItems) {
      expect(find.text(item), findsNothing);
    }
  });

  testWidgets('tapping the options header shows the option items below it', (tester) async {
    await pumpPanel(tester);
    await tapHeader(tester);

    expectInOrder(tester, [...mainItems, 'ОПЦИИ', ...optionItems]);
    expect(find.byKey(const Key('settings_option_checkbox')), findsNWidgets(optionItems.length));
  });

  testWidgets('tapping the options header again hides the option items only', (tester) async {
    await pumpPanel(tester);
    await tapHeader(tester);
    await tapHeader(tester);

    for (final item in optionItems) {
      expect(find.text(item), findsNothing);
    }
    for (final item in mainItems) {
      expect(find.text(item), findsOneWidget);
    }
  });

  testWidgets('all items are placeholders shown in the disabled style', (tester) async {
    await pumpPanel(tester);
    await tapHeader(tester);

    final context = tester.element(find.byType(SettingsPanel));
    for (final item in [...mainItems, ...optionItems]) {
      expect(tester.widget<Text>(find.text(item)).style, AppTextStyles.menuItemDisabled(context));
    }
  });
}
