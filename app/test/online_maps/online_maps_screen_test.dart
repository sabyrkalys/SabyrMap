import 'package:app/online_maps/online_maps_screen.dart';
import 'package:app/online_maps/widgets/online_maps_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: OnlineMapsScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('starts with only Google open', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Онлайн-карты'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(OnlineMapsAppBar), matching: find.text('Установленные карты')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('online_maps_storage')), matching: find.text('238 ГБ / 487 ГБ')),
      findsOneWidget,
    );
    for (final title in ['OPENSTREETMAP', 'GOOGLE MAPS', 'BING MAPS', 'HERE MAPS', 'YANDEX MAPS']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Google Satellite'), findsOneWidget);
    expect(find.text('Bing Road'), findsNothing);
  });

  testWidgets('opening one source leaves the others as they were', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('source_header_bing')));
    await tester.pumpAndSettle();
    expect(find.text('Bing Road'), findsOneWidget);
    expect(find.text('Google Satellite'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source_header_google')));
    await tester.pumpAndSettle();
    expect(find.text('Google Satellite'), findsNothing);
    expect(find.text('Bing Road'), findsOneWidget);
  });

  testWidgets('filter «Только скачанные» keeps only cached maps', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('online_maps_more_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dropdown_filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online_maps_dropdown')), findsNothing);

    await tester.tap(find.byKey(const Key('filter_only_downloaded')));
    await tester.tap(find.byKey(const Key('filter_apply')));
    await tester.pumpAndSettle();

    expect(find.text('Google Bike'), findsOneWidget);
    expect(find.text('Google Satellite'), findsOneWidget);
    expect(find.text('Google Map'), findsNothing);
    expect(find.text('BING MAPS'), findsNothing);
  });

  testWidgets('dropdown closes on a tap outside it', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('online_maps_more_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online_maps_dropdown')), findsOneWidget);

    await tester.tapAt(const Offset(100, 1500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online_maps_dropdown')), findsNothing);
  });

  testWidgets('drawer switches to the altitude stub and closes', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('online_maps_menu_button')));
    await tester.pumpAndSettle();
    expect(find.text('ОНЛАЙН-КАРТЫ'), findsOneWidget);
    expect(find.text('/storage/emulated/0/'), findsOneWidget);
    expect(find.text('AlpineQuest Maps'), findsOneWidget);

    await tester.tap(find.byKey(const Key('drawer_section_altitude')));
    await tester.pumpAndSettle();
    expect(find.text('Раздел в разработке'), findsOneWidget);
    expect(find.text('GOOGLE MAPS'), findsNothing);
    expect(tester.getTopLeft(find.byKey(const Key('side_drawer'))).dx, lessThan(0));
  });

  testWidgets('drawer closes on the scrim and on a second menu tap', (tester) async {
    await pumpScreen(tester);
    Finder drawer() => find.byKey(const Key('side_drawer'));

    await tester.tap(find.byKey(const Key('online_maps_menu_button')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(drawer()).dx, 0);

    await tester.tapAt(const Offset(1000, 1500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(drawer()).dx, lessThan(0));

    await tester.tap(find.byKey(const Key('online_maps_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('online_maps_menu_button')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(drawer()).dx, lessThan(0));
  });
}
