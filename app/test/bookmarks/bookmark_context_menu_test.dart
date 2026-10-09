import 'package:app/bookmarks/bookmark_context_menu.dart';
import 'package:app/bookmarks/bookmark_controller.dart';
import 'package:app/bookmarks/bookmark_store.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BookmarkController c;

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    c = BookmarkController(BookmarkStore(AppSettings(await SharedPreferences.getInstance())));
    await c.addFromFolder('/l/Поход');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => BookmarkContextMenu.show(context, c.bookmarks.single, c),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('title is the bookmark name; only «Удалить» and «ОТМЕНА»', (tester) async {
    await open(tester);
    expect(tester.widget<Text>(find.byKey(const Key('bookmark_menu_title'))).data, 'Поход');
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.text('ОТМЕНА'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('bookmark_menu')), matching: find.byType(InkWell)), findsNWidgets(2));
  });

  testWidgets('«Удалить» → НЕТ keeps the bookmark and the menu', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('bookmark_menu_remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookmark_delete_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('bookmark_delete_no')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookmark_delete_dialog')), findsNothing);
    expect(find.byKey(const Key('bookmark_menu')), findsOneWidget);
    expect(c.bookmarks, hasLength(1));
  });

  testWidgets('«Удалить» → ДА removes it, closes the menu, says so', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('bookmark_menu_remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bookmark_delete_yes')));
    await tester.pumpAndSettle();
    expect(c.isEmpty, isTrue);
    expect(find.byKey(const Key('bookmark_menu')), findsNothing);
    expect(find.text('Закладка удалена'), findsOneWidget);
  });

  testWidgets('«ОТМЕНА» closes without doing anything', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('bookmark_menu_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookmark_menu')), findsNothing);
    expect(c.bookmarks, hasLength(1));
  });
}
