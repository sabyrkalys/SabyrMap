import 'dart:ui';

import 'package:app/app_icons.dart';
import 'package:app/menu/menu_widgets.dart';
import 'package:app/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget panel) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomLeft, child: panel))));
  }

  MenuPanel samplePanel({VoidCallback? onTap, ValueChanged<bool>? onChecked, bool checked = false}) {
    return MenuPanel(
      title: 'МЕТКИ',
      arrowCenterX: 75,
      items: [
        MenuListItem(icon: AppIcons.flag, label: 'Все метки', onTap: onTap),
        const MenuListItem(icon: AppIcons.search, label: 'Поиск на карте'),
      ],
      sections: [
        MenuSection(title: 'ОПЦИИ', children: [
          MenuCheckboxItem(label: 'Названия меток', value: checked, onChanged: onChecked ?? (_) {}),
        ]),
        const MenuSection(title: 'ИНФОРМЕРЫ', children: []),
      ],
    );
  }

  testWidgets('shows the title, help button, items and section headers; sections start collapsed', (tester) async {
    await pump(tester, samplePanel());

    expect(find.text('МЕТКИ'), findsOneWidget);
    expect(find.byKey(const Key('menu_panel_help')), findsOneWidget);
    expect(find.text('Все метки'), findsOneWidget);
    expect(find.text('ОПЦИИ'), findsOneWidget);
    expect(find.text('ИНФОРМЕРЫ'), findsOneWidget);
    expect(find.text('Названия меток'), findsNothing);
  });

  testWidgets('tapping a section header expands and collapses it', (tester) async {
    await pump(tester, samplePanel());

    await tester.tap(find.byKey(const Key('menu_section_ОПЦИИ')));
    await tester.pumpAndSettle();
    expect(find.text('Названия меток'), findsOneWidget);

    await tester.tap(find.byKey(const Key('menu_section_ОПЦИИ')));
    await tester.pumpAndSettle();
    expect(find.text('Названия меток'), findsNothing);
  });

  testWidgets('items with an action use the normal style, placeholders the disabled style', (tester) async {
    var taps = 0;
    await pump(tester, samplePanel(onTap: () => taps++));

    final context = tester.element(find.text('Все метки'));
    expect(tester.widget<Text>(find.text('Все метки')).style, AppTextStyles.menuItem(context));
    expect(tester.widget<Text>(find.text('Поиск на карте')).style, AppTextStyles.menuItemDisabled(context));

    await tester.tap(find.text('Все метки'));
    expect(taps, 1);
  });

  testWidgets('checkbox reports changes', (tester) async {
    bool? reported;
    await pump(tester, samplePanel(onChecked: (v) => reported = v));
    await tester.tap(find.byKey(const Key('menu_section_ОПЦИИ')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Названия меток'));
    expect(reported, isTrue);
  });

  testWidgets('switch item reports changes', (tester) async {
    bool? reported;
    await pump(
      tester,
      MenuPanel(
        title: 'ОРИЕНТИРОВАНИЕ',
        arrowCenterX: 225,
        items: [MenuSwitchItem(icon: AppIcons.compass, label: 'Компас', value: false, onChanged: (v) => reported = v)],
      ),
    );

    await tester.tap(find.byType(Switch));
    expect(reported, isTrue);
  });

  testWidgets('background is 85% white with a 10 px blur, width capped at 400', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, samplePanel());

    final card = find.byKey(const Key('menu_panel_card'));
    expect(tester.getSize(card).width, 400);
    final material = tester.widget<Material>(find.descendant(of: card, matching: find.byType(Material)).first);
    expect(material.color, Colors.white.withValues(alpha: 0.85));
    final filter = tester.widget<BackdropFilter>(find.descendant(of: card, matching: find.byType(BackdropFilter)));
    expect(filter.filter, ImageFilter.blur(sigmaX: 10, sigmaY: 10));
  });

  testWidgets('arrow is centered at arrowCenterX', (tester) async {
    await pump(tester, samplePanel());

    final arrow = find.byKey(const Key('menu_panel_arrow'));
    expect(tester.getSize(arrow), const Size(16, 8));
    expect(tester.getCenter(arrow).dx, 75);
  });

  testWidgets('scrolls instead of overflowing on a short landscape screen', (tester) async {
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, samplePanel());
    await tester.tap(find.byKey(const Key('menu_section_ОПЦИИ')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
