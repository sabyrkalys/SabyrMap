import 'package:app/mediafile/mediafile_folder_screen.dart';
import 'package:app/mediafile/mediafile_folder_service.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MediaFileFolderService _serviceWith(MemoryFileSystem fs, {List<String> fileNames = const []}) {
  final dir = fs.directory('/base/mediafile/custom-types')..createSync(recursive: true);
  for (final name in fileNames) {
    dir.childFile(name).writeAsBytesSync([1, 2, 3]);
  }
  return MediaFileFolderService(
    subfolder: 'custom-types',
    fileSystem: fs,
    baseDirectoryPath: '/base/mediafile/custom-types',
  );
}

Widget _harness(MediaFileFolderService service) => MaterialApp(
      home: MediaFileFolderScreen(
        title: 'Файлы меток',
        subfolder: 'custom-types',
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'svg'],
        service: service,
      ),
    );

void main() {
  testWidgets('shows an empty state when the folder has no files', (tester) async {
    final service = _serviceWith(MemoryFileSystem());

    await tester.pumpWidget(_harness(service));
    await tester.pump();

    expect(find.text('Здесь пока нет файлов'), findsOneWidget);
  });

  testWidgets('lists files by name', (tester) async {
    final service = _serviceWith(MemoryFileSystem(), fileNames: ['marker.svg', 'camp.png']);

    await tester.pumpWidget(_harness(service));
    await tester.pump();

    expect(find.byKey(const Key('mediafile_entry_marker.svg')), findsOneWidget);
    expect(find.byKey(const Key('mediafile_entry_camp.png')), findsOneWidget);
  });

  testWidgets('lists subfolders before files; a tap opens the subfolder', (tester) async {
    final fs = MemoryFileSystem();
    final service = _serviceWith(fs, fileNames: ['camp.png']);
    fs.file('/base/mediafile/custom-types/БЛА/drone.svg').createSync(recursive: true);

    await tester.pumpWidget(_harness(service));
    await tester.pump();

    final titles = [for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) (tile.title! as Text).data];
    expect(titles, ['БЛА', 'camp.png']);

    await tester.tap(find.byKey(const Key('mediafile_subfolder_БЛА')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mediafile_entry_drone.svg')), findsOneWidget);
    final screen = tester.widget<MediaFileFolderScreen>(find.byType(MediaFileFolderScreen).last);
    expect(screen.subfolder, 'custom-types/БЛА');
    expect(screen.allowedExtensions, ['png', 'jpg', 'jpeg', 'svg']);
  });

  testWidgets('canceling the delete confirmation keeps the file', (tester) async {
    final service = _serviceWith(MemoryFileSystem(), fileNames: ['marker.svg']);

    await tester.pumpWidget(_harness(service));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mediafile_delete_marker.svg')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mediafile_entry_marker.svg')), findsOneWidget);
    expect(await service.list(), hasLength(1));
  });

  testWidgets('confirming the delete dialog removes the file from the list and the folder', (tester) async {
    final service = _serviceWith(MemoryFileSystem(), fileNames: ['marker.svg']);

    await tester.pumpWidget(_harness(service));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mediafile_delete_marker.svg')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mediafile_entry_marker.svg')), findsNothing);
    expect(find.text('Здесь пока нет файлов'), findsOneWidget);
    expect(await service.list(), isEmpty);
  });
}
