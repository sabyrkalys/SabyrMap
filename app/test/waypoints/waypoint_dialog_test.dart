import 'dart:io';

import 'package:app/app/landmark_services_provider.dart';
import 'package:app/config/storage_paths.dart';
import 'package:app/map/map_crosshair.dart';
import 'package:app/waypoints/waypoint_color.dart';
import 'package:app/waypoints/waypoint_dialog/coords_system.dart';
import 'package:app/waypoints/waypoint_dialog/marker_group.dart';
import 'package:app/waypoints/waypoint_dialog/waypoint_data.dart';
import 'package:app/waypoints/waypoint_dialog/waypoint_dialog.dart';
import 'package:app/waypoints/icon_picker/marker_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sample_icon_categories.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

void main() {
  late ProviderContainer container;
  var openedAllMarkers = 0;

  /// Opens the dialog from a button and records what it completes with.
  /// The crosshair sits at [crosshair].
  Future<List<WaypointData?>> open(
    WidgetTester tester, {
    String? pointLabel,
    LatLng? crosshair = const LatLng(47.9958, 37.81465),
  }) async {
    final results = <WaypointData?>[];
    openedAllMarkers = 0;
    container = ProviderContainer(
      overrides: [
        allMarkersOpenerProvider.overrideWithValue((_) => openedAllMarkers++),
        builtInIconCategoriesProvider.overrideWithValue(sampleCategories),
      ],
    );
    addTearDown(container.dispose);
    if (crosshair != null) container.read(mapCrosshairProvider.notifier).set(crosshair);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => results.add(
                  pointLabel == null
                      ? await showWaypointDialog(context)
                      : await showWaypointDialog(context, pointLabel: pointLabel),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> ok(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('waypoint_dialog_ok')));
    await tester.pumpAndSettle();
  }

  test('nextWaypointName numbers unnamed waypoints in order', () {
    expect(nextWaypointName(const []), 'Путевая точка 1');
    expect(
      nextWaypointName(const ['Родник', 'Путевая точка 1', 'Путевая точка 7', 'Путевая точка 3']),
      'Путевая точка 8',
    );
    expect(nextWaypointName(const ['Путевая точка', 'Путевая точка 2а']), 'Путевая точка 1');
  });

  testWidgets('layout: title, «Имя» focused, both dropdowns, four actions, ОТМЕНА and ОК', (tester) async {
    await open(tester);

    expect(find.text('Путевая точка'), findsOneWidget);
    expect(find.text('Имя'), findsOneWidget);
    final field = tester.widget<EditableText>(
      find.descendant(of: find.byKey(const Key('waypoint_dialog_name_field')), matching: find.byType(EditableText)),
    );
    expect(field.focusNode.hasFocus, isTrue);
    expect(find.text('Координаты центра экрана'), findsOneWidget);
    expect(find.text('Несортированные метки'), findsOneWidget);
    for (final key in [
      'waypoint_dialog_icon',
      'waypoint_dialog_color',
      'waypoint_dialog_note',
      'waypoint_dialog_more',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.text('ЕЩЁ...'), findsOneWidget);
    expect(find.text('ОТМЕНА'), findsOneWidget);
    expect(find.text('ОК'), findsOneWidget);
  });

  testWidgets('«ОТМЕНА» returns null', (tester) async {
    final results = await open(tester);
    await tester.tap(find.byKey(const Key('waypoint_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waypoint_dialog')), findsNothing);
    expect(results, [null]);
  });

  testWidgets('«ОК» with an empty name is allowed and returns the defaults', (tester) async {
    final results = await open(tester);
    await ok(tester);

    final data = results.single!;
    expect(data.name, '');
    expect(data.point, isNull);
    expect(data.groupId, WaypointData.unsortedGroupId);
    expect(data.iconId, isNull);
    expect(data.colorValue, isNull);
    expect(data.type, 'generic');
    expect(data.note, '');
  });

  Future<void> openProperty(WidgetTester tester, String type) async {
    await tester.tap(find.byKey(const Key('waypoint_dialog_more')));
    await tester.pumpAndSettle();
    final item = find.byKey(Key('waypoint_property_$type'));
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  testWidgets('«ОК» returns the name and the description', (tester) async {
    final results = await open(tester);
    await tester.enterText(find.byKey(const Key('waypoint_dialog_name_field')), '  Родник ');
    await openProperty(tester, 'description');
    await tester.enterText(find.byKey(const Key('waypoint_dialog_description')), 'Холодная вода');
    await ok(tester);

    final data = results.single!;
    expect(data.name, 'Родник');
    expect(data.note, 'Холодная вода');
    expect(data.comment, isNull);
  });

  Future<void> pickIcon(WidgetTester tester, Finder button, String category, String label) async {
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('icon_category_$category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  final flag = find.byKey(const Key('waypoint_dialog_icon'));
  final preview = find.byKey(const Key('waypoint_dialog_icon_preview'));
  final iconLabel = find.byKey(const Key('waypoint_dialog_icon_label'));
  String labelText(WidgetTester tester) => tester.widget<TextField>(iconLabel).controller!.text;

  testWidgets('choosing an icon swaps the flag for a row: its caption and the icon', (tester) async {
    final results = await open(tester);
    expect(iconLabel, findsNothing);
    await pickIcon(tester, flag, 'structures', 'Bunker');

    expect(flag, findsNothing);
    expect(labelText(tester), 'Bunker');
    expect(find.descendant(of: preview, matching: find.byIcon(Icons.shield)), findsOneWidget);
    expect(tester.getSize(preview), const Size(56, 44));
    // The row sits above the palette, which keeps palette, pencil and ЕЩЁ...
    expect(
      tester.getBottomLeft(iconLabel).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('waypoint_dialog_color'))).dy),
    );
    for (final key in ['waypoint_dialog_color', 'waypoint_dialog_note', 'waypoint_dialog_more']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }

    await ok(tester);
    expect(results.single!.markerIconId, 'struct-bunker');
    expect(results.single!.iconLabel, 'Bunker');
    // The caption is not the waypoint's name.
    expect(results.single!.name, '');
  });

  testWidgets('the icon on the right opens «Иконка» again; a new icon renames an untouched caption', (tester) async {
    await open(tester);
    await pickIcon(tester, flag, 'structures', 'Bunker');
    await pickIcon(tester, preview, 'nature', 'Tree');

    expect(labelText(tester), 'Tree');
    expect(find.descendant(of: preview, matching: find.byIcon(Icons.park)), findsOneWidget);
  });

  testWidgets('a caption the user wrote survives choosing another icon', (tester) async {
    final results = await open(tester);
    await pickIcon(tester, flag, 'structures', 'Bunker');
    await tester.enterText(iconLabel, 'Наш бункер');
    await pickIcon(tester, preview, 'nature', 'Tree');

    expect(labelText(tester), 'Наш бункер');
    await ok(tester);
    expect(results.single!.iconLabel, 'Наш бункер');
    expect(results.single!.markerIconId, 'nature-tree');
  });

  testWidgets('an icon without a glyph shows a 14×14 filled circle', (tester) async {
    await open(tester);
    await pickIcon(tester, flag, 'structures', 'Man made');
    final dot = find.descendant(of: preview, matching: find.byType(Container));
    expect(tester.getSize(dot.last), const Size(14, 14));
  });

  testWidgets('«Нет» brings back the flag and drops the caption', (tester) async {
    final results = await open(tester);
    await pickIcon(tester, flag, 'marker', 'Star');
    await tester.tap(preview);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('marker_icon_none')));
    await tester.pumpAndSettle();

    expect(flag, findsOneWidget);
    expect(iconLabel, findsNothing);
    await ok(tester);
    expect(results.single!.markerIconId, isNull);
    expect(results.single!.iconLabel, isNull);
  });

  final paletteButton = find.byKey(const Key('waypoint_dialog_color'));
  final hexField = find.byKey(const Key('waypoint_dialog_color_hex'));
  final swatch = find.byKey(const Key('waypoint_dialog_color_swatch'));
  String hexText(WidgetTester tester) => tester.widget<TextField>(hexField).controller!.text;
  Color? swatchColor(WidgetTester tester) => (tester.widget<Container>(swatch).decoration! as BoxDecoration).color;

  /// Picks the colour the picker opens on (the type's, #607D8B).
  Future<void> pickColor(WidgetTester tester, Finder button) async {
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_color_picker_select_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('a picked colour gets its own row, #AARRGGBB and a swatch; the palette button goes', (tester) async {
    final results = await open(tester);
    expect(hexField, findsNothing);
    await pickColor(tester, paletteButton);

    expect(hexText(tester), '#FF607D8B');
    expect(swatchColor(tester), const Color(0xFF607D8B));
    expect(tester.getSize(swatch), const Size(24, 24));
    expect(paletteButton, findsNothing);
    expect(flag, findsOneWidget);
    expect(tester.getBottomLeft(hexField).dy, lessThan(tester.getTopLeft(flag).dy));

    await ok(tester);
    expect(results.single!.colorValue, 0xFF607D8B);
    expect(results.single!.colorHex, '#607D8B');
  });

  testWidgets('icon and colour together: both rows, icon first, only the pencil and ЕЩЁ... below', (tester) async {
    await open(tester);
    await pickIcon(tester, flag, 'structures', 'Bunker');
    await pickColor(tester, paletteButton);

    expect(iconLabel, findsOneWidget);
    expect(hexField, findsOneWidget);
    expect(tester.getTopLeft(iconLabel).dy, lessThan(tester.getTopLeft(hexField).dy));
    expect(flag, findsNothing);
    expect(paletteButton, findsNothing);
    expect(find.byKey(const Key('waypoint_dialog_note')), findsOneWidget);
    expect(find.byKey(const Key('waypoint_dialog_more')), findsOneWidget);
  });

  testWidgets('typing a whole #AARRGGBB sets the colour; anything less keeps the last one', (tester) async {
    final results = await open(tester);
    await pickColor(tester, paletteButton);

    await tester.enterText(hexField, '#FF62DF1F');
    await tester.pump();
    expect(swatchColor(tester), const Color(0xFF62DF1F));

    await tester.enterText(hexField, '#FF62D');
    await tester.pump();
    expect(swatchColor(tester), const Color(0xFF62DF1F));
    // Mid-typing the field is left as it is.
    expect(hexText(tester), '#FF62D');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(hexText(tester), '#FF62DF1F');

    await ok(tester);
    expect(results.single!.colorValue, 0xFF62DF1F);
  });

  testWidgets('the swatch opens the picker again; the field shows the picked colour', (tester) async {
    await open(tester);
    await pickColor(tester, paletteButton);
    await tester.enterText(hexField, '#FF62DF1F');
    await tester.pump();

    await pickColor(tester, find.byKey(const Key('waypoint_dialog_color_preview')));
    // The picker opened on the colour typed in, and «Выбрать» keeps it.
    expect(hexText(tester), '#FF62DF1F');
    expect(swatchColor(tester), const Color(0xFF62DF1F));
  });

  testWidgets('clearing the HEX field drops the colour and brings the palette button back', (tester) async {
    final results = await open(tester);
    await pickColor(tester, paletteButton);
    await tester.enterText(hexField, '');
    await tester.pump();

    expect(hexField, findsNothing);
    expect(paletteButton, findsOneWidget);
    await ok(tester);
    expect(results.single!.colorValue, isNull);
  });

  testWidgets('«Сбросить» in the picker drops the colour too', (tester) async {
    await open(tester);
    await pickColor(tester, paletteButton);
    await tester.tap(find.byKey(const Key('waypoint_dialog_color_preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_color_picker_reset_button')));
    await tester.pumpAndSettle();

    expect(hexField, findsNothing);
    expect(paletteButton, findsOneWidget);
  });

  test('argbHex / parseArgbHex: #AARRGGBB in capitals, eight hex digits or nothing', () {
    expect(argbHex(0xFF62DF1F), '#FF62DF1F');
    expect(argbHex(0x8012A0C4), '#8012A0C4');
    expect(parseArgbHex('#ff62df1f'), 0xFF62DF1F);
    expect(parseArgbHex('8012A0C4'), 0x8012A0C4);
    expect(parseArgbHex('#62DF1F'), isNull);
    expect(parseArgbHex('#FF62DF1G'), isNull);
    expect(parseArgbHex(''), isNull);
  });

  final pencil = find.byKey(const Key('waypoint_dialog_note'));
  final comment = find.byKey(const Key('waypoint_dialog_comment'));
  final description = find.byKey(const Key('waypoint_dialog_description'));

  testWidgets('«ЕЩЁ...» opens «Ещё...» with nine properties in order; ОТМЕНА changes nothing', (tester) async {
    final results = await open(tester);
    await tester.tap(find.byKey(const Key('waypoint_dialog_more')));
    await tester.pumpAndSettle();

    expect(find.text('Ещё...'), findsOneWidget);
    final titles = ['Иконка', 'Стиль', 'Изображение', 'Галерея', 'Аудио', 'Курс', 'Сайт', 'Ключевые слова', 'Описание'];
    for (var i = 1; i < titles.length; i++) {
      expect(
        tester.getTopLeft(find.text(titles[i])).dy,
        greaterThan(tester.getTopLeft(find.text(titles[i - 1])).dy),
        reason: titles[i],
      );
    }
    expect(find.text('Комментарий'), findsNothing);

    await tester.tap(find.byKey(const Key('more_properties_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('more_properties_sheet')), findsNothing);
    expect(find.byKey(const Key('waypoint_dialog')), findsOneWidget);
    expect(description, findsNothing);
    await ok(tester);
    expect(results.single!.note, '');
  });

  testWidgets('«Описание» shows a borderless five-line block with a label and a line under it', (tester) async {
    await open(tester);
    await openProperty(tester, 'description');

    expect(find.byKey(const Key('more_properties_sheet')), findsNothing);
    expect(find.text('Описание'), findsOneWidget);
    final field = tester.widget<TextField>(description);
    expect(field.minLines, 5);
    expect(field.maxLines, isNull);
    expect(field.decoration!.border, InputBorder.none);
    expect(comment, findsNothing);
    expect(pencil, findsNothing);
    // The cursor moves from «Имя» into the new field.
    final editable = tester.widget<EditableText>(find.descendant(of: description, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('the pencil shows «Комментарий»: one line with an underline, and goes away', (tester) async {
    final results = await open(tester);
    await tester.tap(pencil);
    await tester.pumpAndSettle();

    expect(find.text('Комментарий'), findsOneWidget);
    expect(tester.widget<TextField>(comment).maxLines, 1);
    expect(tester.widget<TextField>(comment).decoration!.enabledBorder, isA<UnderlineInputBorder>());
    expect(pencil, findsNothing);
    expect(description, findsNothing);
    final editable = tester.widget<EditableText>(find.descendant(of: comment, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.enterText(comment, 'У ручья');
    await ok(tester);
    expect(results.single!.comment, 'У ручья');
    expect(results.single!.note, '');
  });

  testWidgets('both fields at once, comment above description; ОК passes each on its own', (tester) async {
    final results = await open(tester);
    await tester.tap(pencil);
    await tester.pumpAndSettle();
    await openProperty(tester, 'description');

    expect(tester.getTopLeft(comment).dy, lessThan(tester.getTopLeft(description).dy));
    await tester.enterText(comment, 'У ручья');
    await tester.enterText(description, 'Вода круглый год');
    await ok(tester);
    expect(results.single!.comment, 'У ручья');
    expect(results.single!.note, 'Вода круглый год');
  });

  testWidgets('with icon, colour and a field chosen only ЕЩЁ... is left in the palette', (tester) async {
    await open(tester);
    await pickIcon(tester, flag, 'marker', 'Star');
    await pickColor(tester, paletteButton);
    await tester.tap(pencil);
    await tester.pumpAndSettle();

    for (final button in [flag, paletteButton, pencil]) {
      expect(button, findsNothing);
    }
    expect(find.byKey(const Key('waypoint_dialog_more')), findsOneWidget);
  });

  testWidgets('«Ещё...» → «Иконка» opens the icon picker', (tester) async {
    await open(tester);
    await openProperty(tester, 'icon');
    expect(find.text('Иконка'), findsOneWidget);
    expect(find.byKey(const Key('marker_icon_none')), findsOneWidget);
  });

  testWidgets('«Ещё...» → «Стиль» sets the waypoint type', (tester) async {
    final results = await open(tester);
    await openProperty(tester, 'style');
    await tester.tap(find.byKey(const Key('waypoint_dialog_type_water')));
    await tester.pumpAndSettle();
    await ok(tester);

    expect(results.single!.type, 'water');
  });

  testWidgets('a stub property closes the sheet and leaves the dialog as it was', (tester) async {
    await open(tester);
    await openProperty(tester, 'website');
    expect(find.byKey(const Key('more_properties_sheet')), findsNothing);
    expect(find.byKey(const Key('waypoint_dialog')), findsOneWidget);
    expect(pencil, findsOneWidget);
  });

  testWidgets('for a target the first point option names the target', (tester) async {
    await open(tester, pointLabel: 'Координаты цели');
    expect(find.text('Координаты цели'), findsOneWidget);
    expect(find.text('Координаты центра экрана'), findsNothing);
  });

  testWidgets('the keyboard does not cover ОК', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.reset);
    await open(tester);

    final okBottom = tester.getBottomLeft(find.byKey(const Key('waypoint_dialog_ok'))).dy;
    expect(okBottom, lessThanOrEqualTo((1920 - 900) / 3));
  });

  group('coordinates', () {
    Future<void> expand(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('waypoint_dialog_coords')));
      await tester.pumpAndSettle();
    }

    Future<void> openEditor(WidgetTester tester) async {
      await expand(tester);
      await tester.tap(find.byKey(const Key('waypoint_dialog_coords_edit')));
      await tester.pumpAndSettle();
    }

    double chevronTurns(WidgetTester tester) =>
        tester.widget<AnimatedRotation>(find.byKey(const Key('waypoint_dialog_coords_chevron'))).turns;

    testWidgets('a tap folds the block out with the crosshair in СК-42, the chevron turns over', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('waypoint_dialog_coords_block')), findsNothing);
      expect(chevronTurns(tester), 0);

      await expand(tester);
      expect(chevronTurns(tester), 0.5);
      // pyproj: (47.99580, 37.81465) is X 5318741.37, Y 7411649.30.
      expect(find.text('X = 5318741  Y = 7411649'), findsOneWidget);
      expect(find.text('Изменить'), findsOneWidget);
      expect(find.text('Указать точку на карте'), findsNothing);

      await tester.tap(find.byKey(const Key('waypoint_dialog_coords')));
      await tester.pumpAndSettle();
      expect(chevronTurns(tester), 0);
      expect(find.byKey(const Key('waypoint_dialog_coords_block')), findsNothing);
    });

    testWidgets('the coordinates follow the map while the dialog is open', (tester) async {
      await open(tester);
      await expand(tester);
      container.read(mapCrosshairProvider.notifier).set(const LatLng(55.75222, 37.61556));
      await tester.pump();
      expect(find.text('X = 6181945  Y = 7413188'), findsOneWidget);
    });

    testWidgets('«Изменить» opens «Координаты» over the waypoint dialog, СК-42 chosen and filled', (tester) async {
      await open(tester);
      await openEditor(tester);

      expect(find.byKey(const Key('coordinates_dialog')), findsOneWidget);
      expect(find.byKey(const Key('waypoint_dialog')), findsOneWidget);
      expect(find.text('Критерий поиска'), findsOneWidget);
      final x = find.byKey(const Key('coords_x_field'));
      expect(tester.widget<TextField>(x).controller!.text, '5318741');
      expect(tester.widget<TextField>(find.byKey(const Key('coords_y_field'))).controller!.text, '7411649');
      final editable = tester.widget<EditableText>(find.descendant(of: x, matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue);
      expect(editable.keyboardType, const TextInputType.numberWithOptions(signed: true, decimal: true));

      Color? background(CoordsSystem system) =>
          (tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: find.byKey(Key('coords_system_${system.name}')),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration?)
              ?.color;
      expect(background(CoordsSystem.sk42), const Color(0xFFE0E0E0));
      expect(background(CoordsSystem.wgs84), isNull);

      await tester.tap(find.byKey(const Key('coords_system_wgs84')));
      await tester.pumpAndSettle();
      expect(background(CoordsSystem.sk42), isNull);
      expect(background(CoordsSystem.wgs84), isNull);
    });

    String fieldText(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

    testWidgets('switching to latitude/longitude converts the values: degrees, °, N/E buttons', (tester) async {
      await open(tester);
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('coords_system_wgs84')));
      await tester.pumpAndSettle();

      // X 5318741, Y 7411649 rounded to the metre: back within ~1e-5°.
      expect(double.parse(fieldText(tester, 'coords_x_field')), closeTo(47.9958, 1e-5));
      expect(double.parse(fieldText(tester, 'coords_y_field')), closeTo(37.81465, 1e-5));
      expect(fieldText(tester, 'coords_x_field'), matches(RegExp(r'^\d+\.\d{6}$')));
      expect(find.text('°'), findsNWidgets(2));
      expect(find.text('N'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.text('X ='), findsNothing);

      await tester.tap(find.byKey(const Key('coords_system_sk42')));
      await tester.pumpAndSettle();
      expect(int.parse(fieldText(tester, 'coords_x_field')), closeTo(5318741, 1));
      expect(int.parse(fieldText(tester, 'coords_y_field')), closeTo(7411649, 1));
      expect(find.text('X ='), findsOneWidget);
    });

    testWidgets('N/E buttons flip the hemisphere, and so the sign of the point', (tester) async {
      final results = await open(tester);
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('coords_system_wgs84')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('coords_x_field')), '33.5');
      await tester.enterText(find.byKey(const Key('coords_y_field')), '70.25');
      await tester.tap(find.byKey(const Key('coords_lat_hemisphere')));
      await tester.tap(find.byKey(const Key('coords_lng_hemisphere')));
      await tester.pumpAndSettle();
      expect(find.text('S'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coords_ok')));
      await tester.pumpAndSettle();
      expect(find.text('33.500000°S  70.250000°W'), findsOneWidget);
      await ok(tester);
      expect(results.single!.point, const LatLng(-33.5, -70.25));
    });

    testWidgets('«Единое поле» in latitude/longitude reads «47.993239°N 37.801170°E»', (tester) async {
      await open(tester);
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('coords_system_wgs84')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('coords_x_field')), '47.993239');
      await tester.enterText(find.byKey(const Key('coords_y_field')), '37.801170');
      await tester.tap(find.byKey(const Key('coords_single_checkbox')));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'coords_single_field'), '47.993239°N 37.801170°E');

      await tester.enterText(find.byKey(const Key('coords_single_field')), '12.5°S 8.25°W');
      await tester.tap(find.byKey(const Key('coords_single_checkbox')));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'coords_x_field'), '12.500000');
      expect(fieldText(tester, 'coords_y_field'), '8.250000');
      expect(find.text('S'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
    });

    testWidgets('«ОК» in «Координаты» moves the waypoint there and shows the new values', (tester) async {
      final results = await open(tester);
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('coords_x_field')), '6181945');
      await tester.enterText(find.byKey(const Key('coords_y_field')), '7413188');
      await tester.tap(find.byKey(const Key('coords_ok')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coordinates_dialog')), findsNothing);
      expect(find.text('Заданные координаты'), findsOneWidget);
      expect(find.text('X = 6181945  Y = 7413188'), findsOneWidget);
      await ok(tester);

      final point = results.single!.point!;
      expect(point.latitude, closeTo(55.75222, 1e-5));
      expect(point.longitude, closeTo(37.61556, 1e-5));
    });

    testWidgets('«ОТМЕНА» and a tap outside leave the coordinates as they were', (tester) async {
      final results = await open(tester);
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('coords_x_field')), '1');
      await tester.tap(find.byKey(const Key('coords_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('coordinates_dialog')), findsNothing);

      await tester.tap(find.byKey(const Key('waypoint_dialog_coords_edit')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('coordinates_dialog')), findsNothing);
      expect(find.byKey(const Key('waypoint_dialog')), findsOneWidget);

      expect(find.text('X = 5318741  Y = 7411649'), findsOneWidget);
      await ok(tester);
      expect(results.single!.point, isNull);
    });

    testWidgets('bad numbers show «Некорректные координаты» and keep the dialog open', (tester) async {
      await open(tester);
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('coords_x_field')), '-');
      await tester.tap(find.byKey(const Key('coords_ok')));
      await tester.pump();
      expect(find.text('Некорректные координаты'), findsOneWidget);
      expect(find.byKey(const Key('coordinates_dialog')), findsOneWidget);

      // A number, but no СК-42 zone in Y.
      await tester.enterText(find.byKey(const Key('coords_x_field')), '5318741');
      await tester.enterText(find.byKey(const Key('coords_y_field')), '411649');
      await tester.tap(find.byKey(const Key('coords_ok')));
      await tester.pump();
      expect(find.byKey(const Key('coordinates_dialog')), findsOneWidget);
    });

    testWidgets('«Единое поле» merges X and Y into one field and splits them back', (tester) async {
      await open(tester);
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('coords_single_checkbox')));
      await tester.pumpAndSettle();

      final single = find.byKey(const Key('coords_single_field'));
      expect(tester.widget<TextField>(single).controller!.text, 'X=5318741 Y=7411649');
      expect(find.byKey(const Key('coords_x_field')), findsNothing);

      await tester.enterText(single, 'X=6181945\nY=7413188');
      await tester.tap(find.byKey(const Key('coords_single_checkbox')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('coords_x_field'))).controller!.text, '6181945');
      expect(tester.widget<TextField>(find.byKey(const Key('coords_y_field'))).controller!.text, '7413188');
    });

    testWidgets('«ОК» from «Единое поле» reads both numbers', (tester) async {
      final results = await open(tester);
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('coords_system_wgs84')));
      await tester.tap(find.byKey(const Key('coords_single_checkbox')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('coords_single_field')), '55,75222 37,61556');
      await tester.tap(find.byKey(const Key('coords_ok')));
      await tester.pumpAndSettle();
      await ok(tester);

      expect(results.single!.point, const LatLng(55.75222, 37.61556));
    });
  });

  test('parseCoordinatePair takes the first two numbers; a comma may be the decimal point', () {
    expect(parseCoordinatePair('X=5318818 Y=7411502'), (5318818.0, 7411502.0));
    expect(parseCoordinatePair('48,5\n-37.25'), (48.5, -37.25));
    expect(parseCoordinatePair('X=5318818, Y=7411502'), (5318818.0, 7411502.0));
    expect(parseCoordinatePair('X=5318818'), isNull);
  });

  test('parseLatLngPair: hemisphere letters, commas, minus signs', () {
    expect(parseLatLngPair('47.993239°N 37.801170°E'), (47.993239, 37.80117));
    expect(parseLatLngPair('47,5 S\n37,25 W'), (-47.5, -37.25));
    expect(parseLatLngPair('-47.5 37.25'), (-47.5, 37.25));
    expect(parseLatLngPair('47.5°Ю 37.25°З'), (-47.5, -37.25));
    expect(parseLatLngPair('47.5'), isNull);
  });

  test('describe: СК-42 as X/Y, latitude/longitude with hemispheres', () {
    const point = LatLng(-12.5, 37.80117);
    expect(CoordsSystem.wgs84.describe(point), '12.500000°S  37.801170°E');
    expect(CoordsSystem.sk42.describe(const LatLng(47.9958, 37.81465)), 'X = 5318741  Y = 7411649');
  });

  test('CoordinatesResult checks the range of its system', () {
    expect(const CoordinatesResult(system: CoordsSystem.wgs84, x: 48, y: 37).isValid, isTrue);
    expect(const CoordinatesResult(system: CoordsSystem.wgs84, x: 91, y: 37).isValid, isFalse);
    expect(const CoordinatesResult(system: CoordsSystem.sk42, x: 5318741, y: 7411649).isValid, isTrue);
    expect(const CoordinatesResult(system: CoordsSystem.sk42, x: 5318741, y: 411649).isValid, isFalse);
  });

  group('groups', () {
    Finder panel() => find.byKey(const Key('waypoint_dialog_group_panel'));

    Future<void> expandGroups(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('waypoint_dialog_group')));
      await tester.pumpAndSettle();
    }

    testWidgets('a tap folds out a raised white panel with every group and its path', (tester) async {
      await open(tester);
      expect(panel(), findsNothing);
      await expandGroups(tester);

      expect(tester.widget<AnimatedRotation>(find.byKey(const Key('waypoint_dialog_group_chevron'))).turns, 0.5);
      final decoration = tester.widget<Container>(panel()).decoration! as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(decoration.boxShadow, isNotEmpty);

      expect(find.descendant(of: panel(), matching: find.text('Несортированные метки')), findsOneWidget);
      expect(find.text('${StoragePaths.unsorted}/'), findsOneWidget);
      expect(find.text('Мои метки'), findsOneWidget);
      expect(find.text('${StoragePaths.landmarks}/'), findsOneWidget);
      expect(find.text('МОИ МЕТКИ'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('МОИ МЕТКИ')).dy,
        allOf(
          greaterThan(tester.getTopLeft(find.text('${StoragePaths.unsorted}/')).dy),
          lessThan(tester.getTopLeft(find.text('Мои метки')).dy),
        ),
      );

      final all = find.byKey(const Key('waypoint_dialog_group_all'));
      expect(find.descendant(of: all, matching: find.byIcon(Icons.folder_sharp)), findsOneWidget);
      expect(find.descendant(of: all, matching: find.byType(Text)), findsOneWidget);
      // The chosen group is the one with the bullet.
      expect(
        find.descendant(
          of: find.byKey(const Key('waypoint_dialog_group_unsorted')),
          matching: find.byKey(const Key('waypoint_dialog_group_bullet')),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(find.text('${StoragePaths.unsorted}/')).softWrap, isTrue);
    });

    testWidgets('picking a group names the row after it, folds the panel and goes into «ОК»', (tester) async {
      final results = await open(tester);
      await expandGroups(tester);
      await tester.tap(find.byKey(const Key('waypoint_dialog_group_my-markers')));
      await tester.pumpAndSettle();

      expect(panel(), findsNothing);
      expect(
        find.descendant(of: find.byKey(const Key('waypoint_dialog_group')), matching: find.text('Мои метки')),
        findsOneWidget,
      );
      await ok(tester);
      expect(results.single!.groupId, MarkerGroup.myMarkersId);
    });

    testWidgets('«Все метки» opens the local markers, folds the panel and keeps the group', (tester) async {
      final results = await open(tester);
      await expandGroups(tester);
      await tester.tap(find.byKey(const Key('waypoint_dialog_group_all')));
      await tester.pumpAndSettle();

      expect(openedAllMarkers, 1);
      expect(panel(), findsNothing);
      await ok(tester);
      expect(results.single!.groupId, MarkerGroup.unsortedId);
    });

    testWidgets('only one of the coordinates and the groups is open at a time', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('waypoint_dialog_coords')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('waypoint_dialog_coords_block')), findsOneWidget);

      await expandGroups(tester);
      expect(panel(), findsOneWidget);
      expect(find.byKey(const Key('waypoint_dialog_coords_block')), findsNothing);

      await tester.tap(find.byKey(const Key('waypoint_dialog_coords')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('waypoint_dialog_coords_block')), findsOneWidget);
      expect(panel(), findsNothing);
    });
  });

  test('the app\'s Dart code never says «alpinequest» (the product is SabyrMap)', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && file.readAsStringSync().toLowerCase().contains('alpinequest')) file.path,
    ];
    expect(offenders, isEmpty);
  });
}
