import 'package:app/bookmarks/bookmark.dart';
import 'package:app/bookmarks/dialogs/bookmark_delete_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bookmark = Bookmark(id: 'a', name: 'Поход', path: '/l/Поход', createdAt: 0, order: 0);
  late List<bool?> results;

  Future<void> open(WidgetTester tester) async {
    results = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(await BookmarkDeleteConfirmDialog.show(context, bookmark)),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('a red title with the bookmark name and «Вы уверены?»', (tester) async {
    await open(tester);
    final title = tester.widget<Text>(find.byKey(const Key('bookmark_delete_title')));
    expect(title.data, 'Удалить «Поход»');
    expect(title.style!.color, const Color(0xFFD32F2F));
    expect(find.text('Вы уверены?'), findsOneWidget);
  });

  testWidgets('НЕТ returns false', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('bookmark_delete_no')));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('ДА returns true', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('bookmark_delete_yes')));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });
}
