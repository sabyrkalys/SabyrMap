import 'package:app/explorer/dialogs/rename_folder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String?> results;

  Future<void> open(WidgetTester tester, {String name = 'Поход'}) async {
    results = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(await RenameFolderDialog.show(context, name)),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  TextButton ok(WidgetTester tester) => tester.widget<TextButton>(find.byKey(const Key('rename_folder_ok')));

  testWidgets('starts with the current name; valid name enables ОК', (tester) async {
    await open(tester);
    expect(find.text('Переименовать папку'), findsOneWidget);
    expect(find.text('Поход'), findsOneWidget);
    expect(ok(tester).onPressed, isNotNull);
  });

  testWidgets('an empty name disables ОК', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('rename_folder_field')), '   ');
    await tester.pump();
    expect(ok(tester).onPressed, isNull);
  });

  testWidgets('slashes disable ОК and show a hint', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('rename_folder_field')), 'a/b');
    await tester.pump();
    expect(ok(tester).onPressed, isNull);
    expect(find.text('Недопустимые символы'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rename_folder_field')), r'a\b');
    await tester.pump();
    expect(ok(tester).onPressed, isNull);
  });

  testWidgets('ОК returns the trimmed name', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('rename_folder_field')), '  Озеро ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename_folder_ok')));
    await tester.pumpAndSettle();
    expect(results, ['Озеро']);
  });

  testWidgets('ОТМЕНА returns null', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('rename_folder_cancel')));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });
}
