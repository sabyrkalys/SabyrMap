import 'package:app/settings/settings_panel.dart';
import 'package:app/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const items = ['Скрыть кнопки меню', 'Блокировка экрана', 'Снимок экрана', 'Настройки'];

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: SettingsPanel()),
        ),
      ),
    );
  }

  Future<void> tapHeader(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings_options_header')));
    await tester.pumpAndSettle();
  }

  testWidgets('starts collapsed with only the options header', (tester) async {
    await pumpPanel(tester);

    expect(find.text('ОПЦИИ'), findsOneWidget);
    for (final item in items) {
      expect(find.text(item), findsNothing);
    }
  });

  testWidgets('tapping the header expands the four items above it, in order', (tester) async {
    await pumpPanel(tester);
    await tapHeader(tester);

    final tops = [for (final item in items) tester.getTopLeft(find.text(item)).dy];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]));
    }
    expect(tester.getTopLeft(find.text('ОПЦИИ')).dy, greaterThan(tops.last));
  });

  testWidgets('tapping the header again collapses the panel', (tester) async {
    await pumpPanel(tester);
    await tapHeader(tester);
    await tapHeader(tester);

    for (final item in items) {
      expect(find.text(item), findsNothing);
    }
  });

  testWidgets('items are placeholders shown in the disabled style', (tester) async {
    await pumpPanel(tester);
    await tapHeader(tester);

    final context = tester.element(find.byType(SettingsPanel));
    for (final item in items) {
      expect(tester.widget<Text>(find.text(item)).style, AppTextStyles.menuItemDisabled(context));
    }
  });
}
