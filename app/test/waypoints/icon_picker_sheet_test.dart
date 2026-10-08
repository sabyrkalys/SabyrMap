import 'package:app/icons/icon_library_scanner.dart';
import 'package:app/waypoints/icon_picker/icon_item.dart';
import 'package:app/waypoints/icon_picker/icon_picker_sheet.dart';
import 'package:app/waypoints/icon_picker/marker_icon.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A scanner over an empty icon folder, or one with [files].
  IconLibraryScanner scannerWith([List<String> files = const []]) {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    for (final name in files) {
      dir.childFile(name).createSync();
    }
    return IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
  }

  /// Opens the sheet from a button and records what it completes with.
  Future<List<MarkerIcon?>> open(WidgetTester tester, {IconLibraryScanner? scanner, String? currentIconId}) async {
    final results = <MarkerIcon?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                await showMarkerIconSheet(context, scanner: scanner ?? scannerWith(), currentIconId: currentIconId),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> toggle(WidgetTester tester, String categoryId) async {
    await tester.tap(find.byKey(Key('icon_category_$categoryId')));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  double turns(WidgetTester tester, String categoryId) =>
      tester.widget<AnimatedRotation>(find.byKey(Key('icon_category_chevron_$categoryId'))).turns;

  testWidgets('«Иконка», then «Нет» on its own, then the categories, all folded', (tester) async {
    await open(tester);

    expect(find.text('Иконка'), findsOneWidget);
    for (final category in sampleCategories) {
      expect(find.text(category.title), findsOneWidget, reason: category.title);
      expect(turns(tester, category.id), 0);
    }
    expect(tester.getTopLeft(find.text('Нет')).dy, lessThan(tester.getTopLeft(find.text('МЕТКА')).dy));
    expect(find.byType(IconItem), findsNothing);
  });

  testWidgets('a header folds its icons out and back, the chevron turning over', (tester) async {
    await open(tester);
    await toggle(tester, 'tourism');
    expect(turns(tester, 'tourism'), 0.5);
    expect(find.text('Camp'), findsOneWidget);
    expect(find.text('Museum'), findsOneWidget);

    await toggle(tester, 'tourism');
    expect(turns(tester, 'tourism'), 0);
    expect(find.text('Camp'), findsNothing);
  });

  testWidgets('the sheet is 85% of the screen and keeps its height when categories open', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await open(tester);
    final sheet = find.byKey(const Key('icon_picker_sheet'));
    expect(tester.getSize(sheet).height, closeTo(800 * 0.85, 0.5));
    final header = tester.getTopLeft(find.byKey(const Key('icon_category_tourism'))).dy;
    final title = tester.getTopLeft(find.text('Иконка')).dy;

    await toggle(tester, 'marker');
    await toggle(tester, 'structures');
    expect(tester.getSize(sheet).height, closeTo(800 * 0.85, 0.5));
    // A category above opened, the rest moved down; nothing moved up.
    expect(tester.getTopLeft(find.byKey(const Key('icon_category_tourism'))).dy, greaterThan(header));
    expect(tester.getTopLeft(find.text('Иконка')).dy, title);
  });

  testWidgets('several categories stay open at once', (tester) async {
    await open(tester);
    await toggle(tester, 'marker');
    await toggle(tester, 'food');
    expect(find.text('Star'), findsOneWidget);
    expect(find.text('Cafe'), findsOneWidget);
  });

  testWidgets('an icon without a glyph is a filled 12×12 circle', (tester) async {
    await open(tester);
    await toggle(tester, 'structures');
    final glyph = find.descendant(
      of: find.byKey(const Key('marker_icon_struct-manmade')),
      matching: find.byType(MarkerIconGlyph),
    );
    expect(tester.getSize(find.descendant(of: glyph, matching: find.byType(Container))), const Size(12, 12));
  });

  testWidgets('the list scrolls when the open categories do not fit', (tester) async {
    tester.view.physicalSize = const Size(1080, 1600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final results = await open(tester);
    for (final category in sampleCategories) {
      await scrollTo(tester, find.byKey(Key('icon_category_${category.id}')));
      await toggle(tester, category.id);
    }

    await scrollTo(tester, find.text('Water'));
    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    expect(results.single?.id, 'nature-water');
  });

  testWidgets('a tap on an icon returns it, «Нет» returns noneOption, «ОТМЕНА» null', (tester) async {
    var results = await open(tester);
    await toggle(tester, 'transport');
    await tester.tap(find.text('Fuel'));
    await tester.pumpAndSettle();
    expect(results.single?.id, 'transport-fuel');
    expect(results.single?.icon, Icons.local_gas_station);

    results = await open(tester);
    await tester.tap(find.byKey(const Key('marker_icon_none')));
    await tester.pumpAndSettle();
    expect(results.single, same(noneOption));

    results = await open(tester);
    await tester.tap(find.byKey(const Key('icon_picker_cancel')));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('the user\'s own icon files are the last category, «СВОИ ИКОНКИ»', (tester) async {
    final results = await open(tester, scanner: scannerWith(['camp.png', 'tent.png']));
    await scrollTo(tester, find.text('СВОИ ИКОНКИ'));
    expect(tester.getTopLeft(find.text('СВОИ ИКОНКИ')).dy, greaterThan(tester.getTopLeft(find.text('ПРИРОДА')).dy));

    await scrollTo(tester, find.byKey(const Key('icon_category_own')));
    await toggle(tester, 'own');
    await scrollTo(tester, find.text('tent'));
    await tester.tap(find.text('tent'));
    await tester.pumpAndSettle();
    expect(results.single?.fileName, 'tent.png');
    expect(results.single?.isFile, isTrue);
  });

  testWidgets('no own icons, no «СВОИ ИКОНКИ»', (tester) async {
    await open(tester);
    expect(find.text('СВОИ ИКОНКИ'), findsNothing);
  });
}
