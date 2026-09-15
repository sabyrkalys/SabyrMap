import 'package:app/icons/icon_library_scanner.dart';
import 'package:app/icons/icon_picker_sheet.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(IconLibraryScanner scanner, ValueChanged<IconPickResult?> onResult) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final result = await showIconPickerSheet(context, scanner: scanner);
            onResult(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a "Стандартная" tile plus every scanned file, labeled without extension', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    dir.childFile('marker.svg').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');

    await tester.pumpWidget(_harness(scanner, (_) {}));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Стандартная'), findsOneWidget);
    expect(find.text('camp'), findsOneWidget);
    expect(find.text('marker'), findsOneWidget);
  });

  testWidgets('tapping a file tile returns IconPickResult.file with its filename', (tester) async {
    final fs = MemoryFileSystem();
    final dir = fs.directory('/base')..createSync(recursive: true);
    dir.childFile('camp.png').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    IconPickResult? result;

    await tester.pumpWidget(_harness(scanner, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_camp.png')));
    await tester.pumpAndSettle();

    expect(result?.fileName, 'camp.png');
  });

  testWidgets('tapping "Стандартная" returns a reset result', (tester) async {
    final fs = MemoryFileSystem();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    IconPickResult? result = const IconPickResult.file('sentinel.png');

    await tester.pumpWidget(_harness(scanner, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_default_tile')));
    await tester.pumpAndSettle();

    expect(result?.fileName, isNull);
  });

  testWidgets('dismissing without a choice returns null', (tester) async {
    final fs = MemoryFileSystem();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    IconPickResult? result = const IconPickResult.file('sentinel.png');

    await tester.pumpWidget(_harness(scanner, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
