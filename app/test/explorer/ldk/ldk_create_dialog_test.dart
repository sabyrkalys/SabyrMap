import 'package:app/explorer/ldk/ldk_create_dialog.dart';
import 'package:app/explorer/ldk/ldk_properties_dialog.dart';
import 'package:app/landmarks/models/landmark_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../landmarks/services/fixture.dart';
import 'ldk_test_helpers.dart';

void main() {
  late ServicesFixture f;
  LdkProperties? result;
  var closed = false;

  Future<void> openDialog(WidgetTester tester) async {
    closed = false;
    result = null;
    await tester.runAsync(() async => f = await ServicesFixture.create());
    await tester.pumpWidget(
      hostApp(f.services, (context) async {
        result = await LdkCreateDialog.show(context);
        closed = true;
      }),
    );
    await tester.tap(find.byKey(const Key('host_button')));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) => tester.runAsync(() async => f.root.deleteSync(recursive: true));

  testWidgets('the name field is focused', (tester) async {
    await openDialog(tester);
    final field = tester.widget<EditableText>(
      find.descendant(of: find.byKey(const Key('ldk_create_name')), matching: find.byType(EditableText)),
    );
    expect(field.focusNode.hasFocus, isTrue);
    expect(find.text('Файл'), findsOneWidget);
    expect(find.text('Имя'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('only a name: no format dropdown', (tester) async {
    await openDialog(tester);
    final dialog = find.byKey(const Key('ldk_create_dialog'));
    expect(find.descendant(of: dialog, matching: find.byType(TextField)), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.byType(DropdownButton<String>)), findsNothing);
    expect(find.descendant(of: dialog, matching: find.byType(DropdownButtonFormField<String>)), findsNothing);
    await dispose(tester);
  });

  testWidgets('«Ещё...» opens the properties dialog and keeps its values', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byKey(const Key('ldk_create_name')), 'Поход');
    await tester.tap(find.byKey(const Key('ldk_create_more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ldk_properties_dialog')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Поход'), findsWidgets);
    await tester.enterText(find.byKey(const Key('ldk_props_description')), 'Три дня');
    await tester.tap(find.byKey(const Key('ldk_props_ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ldk_create_ok')));
    await tester.pumpAndSettle();
    expect(result, const LdkProperties(name: 'Поход', description: 'Три дня'));
    await dispose(tester);
  });

  testWidgets('ОТМЕНА returns null', (tester) async {
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('ldk_create_cancel')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
    await dispose(tester);
  });

  testWidgets('ОК passes the name; an empty name works too', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byKey(const Key('ldk_create_name')), '  Поход  ');
    await tester.tap(find.byKey(const Key('ldk_create_ok')));
    await tester.pumpAndSettle();
    expect(result!.name, 'Поход');

    await tester.tap(find.byKey(const Key('host_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ldk_create_ok')));
    await tester.pumpAndSettle();
    expect(result!.name, '');
    await dispose(tester);
  });

  testWidgets('createIn makes an .ldk file through the creation service', (tester) async {
    String? created;
    await tester.runAsync(() async => f = await ServicesFixture.create());
    final folder = p.join(f.paths.landmarks, 'Поход');
    await tester.pumpWidget(
      hostApp(f.services, (context) async => created = await LdkCreateDialog.createIn(context, f.services, folder)),
    );
    await tester.tap(find.byKey(const Key('host_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ldk_create_name')), 'Сборы');
    await tester.runAsync(() => tester.tap(find.byKey(const Key('ldk_create_ok'))));
    for (var i = 0; i < 50 && created == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(p.extension(created!), '.ldk');
    expect(p.dirname(created!), folder);
    final file = await tester.runAsync(() => f.services.repository.load(created!));
    expect(file!.type, LandmarkType.ldkFile);
    expect(file.content.userMetadata.name, 'Сборы');
    expect(find.text('Файл создан'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('createIn with an empty name names the file automatically', (tester) async {
    String? created;
    await tester.runAsync(() async => f = await ServicesFixture.create());
    await tester.pumpWidget(
      hostApp(
        f.services,
        (context) async => created = await LdkCreateDialog.createIn(context, f.services, f.paths.landmarks),
      ),
    );
    await tester.tap(find.byKey(const Key('host_button')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.byKey(const Key('ldk_create_ok'))));
    for (var i = 0; i < 50 && created == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(p.basename(created!), startsWith('untitled_'));
    expect(p.extension(created!), '.ldk');
    await dispose(tester);
  });
}
