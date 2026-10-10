import 'dart:io';

import 'package:app/app/landmark_services_provider.dart';
import 'package:app/explorer/ldk/ldk_details_file_section.dart';
import 'package:app/explorer/ldk/ldk_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../landmarks/services/fixture.dart';
import 'ldk_test_helpers.dart';

void main() {
  late ServicesFixture f;
  late String path;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.runAsync(() async {
      f = await ServicesFixture.create();
      path = await createLdk(f.services, 'Поход');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [landmarkServicesProvider.overrideWithValue(f.services)],
        child: MaterialApp(home: LdkDetailsScreen(path: path)),
      ),
    );
    await settle(tester);
  }

  Future<void> dispose(WidgetTester tester) => tester.runAsync(() async => f.root.deleteSync(recursive: true));

  testWidgets('the action panel has ⋮, ЦЕНТРИРОВАТЬ and the eye', (tester) async {
    await pumpScreen(tester);
    final panel = find.byKey(const Key('ldk_details_actions'));
    expect(find.descendant(of: panel, matching: find.byIcon(Icons.more_vert)), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('ЦЕНТРИРОВАТЬ')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.byIcon(Icons.visibility_outlined)), findsOneWidget);
    expect(find.text('Локальные метки'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('«ФАЙЛ» shows Имя, Папка, Размер, Дата with correct values', (tester) async {
    await pumpScreen(tester);
    for (final label in ['Имя', 'Папка', 'Размер', 'Дата']) {
      expect(find.byKey(Key('ldk_file_row_$label')), findsOneWidget, reason: label);
    }
    final stat = await tester.runAsync(() => File(path).stat());
    String row(String label) => tester
        .widgetList<Text>(find.descendant(of: find.byKey(Key('ldk_file_row_$label')), matching: find.byType(Text)))
        .last
        .data!;
    expect(row('Имя'), 'Поход');
    expect(row('Папка'), f.paths.landmarks);
    expect(row('Размер'), LdkDetailsFileSection.formatSize(stat!.size));
    expect(row('Дата'), LdkDetailsFileSection.formatDate(stat.modified));
    await dispose(tester);
  });

  test('size and date formats', () {
    expect(LdkDetailsFileSection.formatSize(512), '512 Б');
    expect(LdkDetailsFileSection.formatSize(1526), '1,49 кБ');
    expect(LdkDetailsFileSection.formatDate(DateTime(2026, 10, 3, 7, 5, 9)), '03.10.2026 07:05:09');
  });

  testWidgets('the «ФАЙЛ» header collapses and expands', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('ldk_file_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_file_row_Имя')), findsNothing);
    await tester.tap(find.byKey(const Key('ldk_file_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_file_row_Имя')), findsOneWidget);
    await dispose(tester);
  });

  for (final (where, key) in [('app bar', 'maps_more_button'), ('action panel', 'ldk_details_more'), ('section', 'ldk_file_more')]) {
    testWidgets('⋮ in the $where opens the compact menu', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(Key(key)));
      await settle(tester);
      expect(find.byKey(const Key('ldk_context_menu_compact')), findsOneWidget);
      expect(find.text('Поделиться'), findsOneWidget);
      expect(find.text('Переименовать'), findsOneWidget);
      expect(find.text('ОТМЕНА'), findsOneWidget);
      expect(find.text('Удалить'), findsNothing);
      expect(find.text('Копировать'), findsNothing);
      await dispose(tester);
    });
  }

  testWidgets('the eye toggles the map display', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('ldk_details_visibility')));
    await tester.pump();
    expect(f.services.displayRegistry.isDisplayed(path), isTrue);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    await tester.tap(find.byKey(const Key('ldk_details_visibility')));
    await tester.pump();
    expect(f.services.displayRegistry.isDisplayed(path), isFalse);
    await dispose(tester);
  });

  testWidgets('rename from the compact menu updates the screen', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('ldk_details_more')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('ldk_menu_rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ldk_rename_field')), 'Сборы');
    await tester.runAsync(() => tester.tap(find.byKey(const Key('ldk_rename_ok'))));
    for (var i = 0; i < 50 && find.text('Файл переименован').evaluate().isEmpty; i++) {
      await settle(tester);
    }
    await settle(tester);
    expect(find.text('Файл переименован'), findsOneWidget);
    expect(find.text('Сборы'), findsWidgets);
    await dispose(tester);
  });
}
