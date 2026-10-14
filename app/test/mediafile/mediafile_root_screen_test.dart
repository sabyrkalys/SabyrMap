import 'package:app/mediafile/mediafile_folder_screen.dart';
import 'package:app/mediafile/mediafile_folder_service.dart';
import 'package:app/mediafile/mediafile_root_screen.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists the known subfolders first, then the rest; a tap opens one', (tester) async {
    final fs = MemoryFileSystem();
    fs.directory('/base/mediafile/maps').createSync(recursive: true);
    fs.directory('/base/mediafile/tracks-old').createSync(recursive: true);
    final service = MediaFileFolderService(subfolder: '', fileSystem: fs, baseDirectoryPath: '/base/mediafile');

    await tester.pumpWidget(MaterialApp(home: MediaFileRootScreen(service: service)));
    await tester.pump();

    final titles = [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) ((tile.title! as Text).data!),
    ];
    expect(titles, ['Карты', 'Ортофото', 'Файлы меток', 'tracks-old']);

    await tester.tap(find.byKey(const Key('mediafile_folder_orthophoto')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final screen = tester.widget<MediaFileFolderScreen>(find.byType(MediaFileFolderScreen));
    expect(screen.subfolder, 'orthophoto');
    expect(screen.allowedExtensions, ['mbtiles']);
  });
}
