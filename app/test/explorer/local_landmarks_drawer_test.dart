import 'package:app/explorer/local_landmarks_drawer.dart';
import 'package:app/landmarks/explorer/places/place_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'explorer_test_harness.dart';

void main() {
  testWidgets('every place is listed; the device shows its size and meter', (tester) async {
    final h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await tester.tap(find.byKey(const Key('explorer_menu_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drawer_place_landmarks')), findsOneWidget);
    expect(find.text('Мои загрузки'), findsOneWidget);
    expect(find.text('Память устройства (487 ГБ)'), findsOneWidget);
    expect(find.text('ЛОКАЛЬНЫЕ МЕТКИ'), findsOneWidget);
    expect(find.text('ОНЛАЙН-МЕТКИ'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('tapping a place opens it', (tester) async {
    final h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await tester.tap(find.byKey(const Key('explorer_menu_button')));
    await tester.pumpAndSettle();
    await h.tap(tester, find.byKey(const Key('drawer_place_device')));

    final state = h.f.services.explorerController.state;
    expect(state.currentPlace!.kind, PlaceRootKind.deviceFolder);
    expect(state.currentFolder, h.device);
    expect(find.byKey(const Key('folder_row_DCIM')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('explorer_subtitle'))).data, 'Память устройства (487 ГБ)');

    await tester.tap(find.byKey(const Key('explorer_menu_button')));
    await tester.pumpAndSettle();
    expect(find.text('239 ГБ / 487 ГБ'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('online marks show «Раздел в разработке»', (tester) async {
    final h = await ExplorerHarness.create(tester);
    await h.pumpApp(tester);
    await tester.tap(find.byKey(const Key('explorer_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('online_my_marks')));
    await tester.pump();
    expect(find.text('Раздел в разработке'), findsOneWidget);
    await h.dispose(tester);
  });

  test('the device title carries the volume size only for the device place', () {
    const device = PlaceRoot(id: 'device', title: 'Память устройства', path: '/s', kind: PlaceRootKind.deviceFolder);
    const marks = PlaceRoot(id: 'landmarks', title: 'Мои метки', path: '/l', kind: PlaceRootKind.landmarks);
    expect(LocalLandmarksDrawer.titleOf(device, null), 'Память устройства');
    expect(LocalLandmarksDrawer.titleOf(marks, null), 'Мои метки');
  });
}
