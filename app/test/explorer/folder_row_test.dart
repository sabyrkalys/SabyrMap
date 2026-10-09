import 'dart:io';

import 'package:app/explorer/folder_count_badge.dart';
import 'package:app/explorer/folder_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('labels use the right plural', () {
    expect(const FolderCounts(folders: 1, files: 2).label, '1 папка · 2 файл.');
    expect(const FolderCounts(folders: 3, files: 0).label, '3 папки · 0 файл.');
    expect(const FolderCounts(folders: 5, files: 1).label, '5 папок · 1 файл.');
    expect(const FolderCounts(folders: 11, files: 1).label, '11 папок · 1 файл.');
    expect(const FolderCounts(folders: 21, files: 1).label, '21 папка · 1 файл.');
  });

  testWidgets('counts subfolders and landmark files; tap opens', (tester) async {
    final dir = (await tester.runAsync(() async {
      final d = Directory.systemTemp.createTempSync('folder_row_');
      Directory(p.join(d.path, 'a')).createSync();
      Directory(p.join(d.path, 'b')).createSync();
      File(p.join(d.path, 'x.wpt')).writeAsBytesSync([1]);
      File(p.join(d.path, 'y.trk')).writeAsBytesSync([1]);
      File(p.join(d.path, 'notes.txt')).writeAsBytesSync([1]);
      return d;
    }))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    var opened = 0;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FolderRow(path: dir.path, name: 'Trip', onTap: () => opened++)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('2 папки · 2 файл.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('folder_row_Trip')));
    expect(opened, 1);
  });

  test('a missing folder counts as empty', () async {
    final counts = await FolderCounts.of('/no/such/folder');
    expect(counts.label, '0 папок · 0 файл.');
  });
}
