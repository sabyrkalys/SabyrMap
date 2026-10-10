import 'dart:io';

import 'package:app/explorer/ldk/ldk_item_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../explorer_test_harness.dart';
import 'ldk_test_helpers.dart';

void main() {
  late ExplorerHarness h;
  late String path;

  Future<void> withFile(WidgetTester tester) async {
    h = await ExplorerHarness.create(tester);
    await tester.runAsync(() async => path = await createLdk(h.f.services, 'Поход'));
    await h.pumpApp(tester);
  }

  testWidgets('no .ldk files → the section is hidden', (tester) async {
    h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    expect(find.byKey(const Key('ldk_section')), findsNothing);
    expect(find.text('ФАЙЛЫ МЕТОК'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('one .ldk → a card with «group · size» and «1 элем.»', (tester) async {
    await withFile(tester);
    expect(find.byKey(const Key('ldk_section')), findsOneWidget);
    expect(find.text('ФАЙЛЫ МЕТОК'), findsOneWidget);
    expect(find.text('1 элем.'), findsOneWidget);
    expect(find.byKey(LdkItemCard.keyFor(path)), findsOneWidget);
    expect(find.text('Поход'), findsOneWidget);
    final size = await tester.runAsync(() => File(path).length());
    expect(find.text('Мои метки · $size Б'), findsOneWidget);
    // В общем списке меток файл не дублируется.
    expect(find.byKey(const Key('item_row_Поход')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('tap opens the details screen', (tester) async {
    await withFile(tester);
    await h.tap(tester, find.byKey(LdkItemCard.keyFor(path)));
    await tester.pumpAndSettle();
    await h.settle(tester);
    expect(find.byKey(const Key('ldk_details_screen')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('long press opens the context menu', (tester) async {
    await withFile(tester);
    await tester.longPress(find.byKey(LdkItemCard.keyFor(path)));
    await h.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_context_menu')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('⋮ on the card opens the context menu', (tester) async {
    await withFile(tester);
    await h.tap(tester, find.byKey(const Key('ldk_card_menu_поход_1760000000000.ldk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_context_menu')), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('section ⋮ → «Выбрать все» selects every .ldk', (tester) async {
    await withFile(tester);
    await tester.tap(find.byKey(const Key('ldk_section_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_section_sheet')), findsOneWidget);
    await h.tap(tester, find.byKey(const Key('ldk_section_select_all')));
    await tester.pumpAndSettle();
    final selection = h.f.services.explorerController.selection;
    expect(selection.state.isActive, isTrue);
    expect(selection.contains(path), isTrue);
    expect(find.byType(Checkbox), findsOneWidget);
    await h.dispose(tester);
  });
}
