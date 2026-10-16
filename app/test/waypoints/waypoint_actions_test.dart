import 'dart:io';

import 'package:app/app/landmark_services_provider.dart';
import 'package:app/icons/icon_library_scanner.dart';
import 'package:app/landmarks/explorer/listing/landmark_item.dart';
import 'package:app/waypoints/waypoint_actions.dart';
import 'package:app/waypoints/waypoint_edits.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../landmarks/services/fixture.dart';

void main() {
  late ServicesFixture f;
  late String path;

  setUp(() async {
    f = await ServicesFixture.create();
    path = await WaypointEdits(f.services).create(
      name: 'Summit',
      type: 'generic',
      note: '',
      color: null,
      lat: 1,
      lng: 2,
    );
  });
  tearDown(() => f.dispose());

  LandmarkItem item() => f.services.index.byPath(path)!;

  Future<void> pumpButton(WidgetTester tester, void Function(BuildContext context, WidgetRef ref) onPressed) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [landmarkServicesProvider.overrideWithValue(f.services)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) =>
                ElevatedButton(onPressed: () => onPressed(context, ref), child: const Text('go')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// Даёт записи на диск дойти до индекса.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('editing a waypoint writes the name and the picked icon into its file', (tester) async {
    final fs = MemoryFileSystem();
    fs.directory('/base').createSync(recursive: true);
    fs.file('/base/camp.png').createSync();
    final scanner = IconLibraryScanner(fileSystem: fs, baseDirectoryPath: '/base');
    await pumpButton(tester, (context, ref) => editWaypoint(context, ref, item(), iconScanner: scanner));

    expect(tester.widget<TextField>(find.byKey(const Key('waypoint_name_field'))).controller!.text, 'Summit');
    await tester.tap(find.byKey(const Key('waypoint_icon_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('icon_picker_tile_camp.png')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Renamed');
    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await waitFor(tester, () => item().name == 'Renamed');

    expect(item().name, 'Renamed');
    expect(item().userIcon, 'camp.png');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('deleting a waypoint removes its file after the confirmation', (tester) async {
    await pumpButton(tester, (context, ref) => deleteWaypoint(context, ref, item()));
    await tester.tap(find.text('Удалить'));
    await waitFor(tester, () => f.services.index.byPath(path) == null);

    expect(File(path).existsSync(), isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the card of a waypoint inside a landmark file has no edit or delete', (tester) async {
    final nested = item().copyWith(path: LandmarkItem.nestedPath('/m/set.ldk', 0));
    await pumpButton(tester, (context, ref) => showWaypointDetails(context, ref, nested));

    expect(find.text('Summit'), findsOneWidget);
    expect(find.byKey(const Key('waypoint_edit_button')), findsNothing);
    expect(find.byKey(const Key('waypoint_delete_button')), findsNothing);
  });
}
