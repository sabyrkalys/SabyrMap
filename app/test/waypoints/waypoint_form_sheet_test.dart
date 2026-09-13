import 'package:app/waypoints/waypoint_color.dart';
import 'package:app/waypoints/waypoint_form_sheet.dart';
import 'package:app/waypoints/waypoint_models.dart';
import 'package:app/waypoints/waypoint_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Waypoint _existingWaypoint() {
  return Waypoint(
    id: 'w1',
    orgId: 'o1',
    ownerId: 'u1',
    name: 'Old name',
    type: 'water',
    note: 'Old note',
    lat: 1.0,
    lng: 2.0,
    canEdit: true,
    createdAt: DateTime.utc(2026, 8, 22),
    color: null,
  );
}

Widget _harness(VoidCallback onOpen, ValueChanged<WaypointFormResult?> onResult, {Waypoint? existing}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            onOpen();
            final result = await showWaypointFormSheet(context, existing: existing);
            onResult(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('save is disabled until a name is entered, then submits name/type/note', (tester) async {
    WaypointFormResult? result;
    await tester.pumpWidget(_harness(() {}, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(find.byKey(const Key('waypoint_save_button')));
    expect(saveButton.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
    await tester.pump();
    await tester.tap(find.byKey(const Key('waypoint_type_chip_water')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('waypoint_note_field')), 'Bring rope');
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.name, 'Summit');
    expect(result!.type, 'water');
    expect(result!.note, 'Bring rope');
  });

  testWidgets('pre-fills fields when editing an existing waypoint', (tester) async {
    await tester.pumpWidget(_harness(() {}, (_) {}, existing: _existingWaypoint()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Old name'), findsOneWidget);
    expect(find.text('Old note'), findsOneWidget);
    final waterChip = tester.widget<ChoiceChip>(find.byKey(const Key('waypoint_type_chip_water')));
    expect(waterChip.selected, isTrue);
  });

  testWidgets('returns null when dismissed without saving', (tester) async {
    WaypointFormResult? result =
        const WaypointFormResult(name: 'sentinel', type: 'generic', note: '', color: null);
    await tester.pumpWidget(_harness(() {}, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('swatch defaults to the selected type color when no override is set', (tester) async {
    await tester.pumpWidget(_harness(() {}, (_) {}));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final swatch = tester.widget<Container>(find.byKey(const Key('waypoint_color_swatch')));
    final decoration = swatch.decoration as BoxDecoration;
    expect(decoration.color, colorFromHex(waypointTypeColors[defaultWaypointType]!));
  });

  testWidgets('falls back to the default type color for an unrecognized waypoint type', (tester) async {
    final existing = Waypoint(
      id: 'w1',
      orgId: 'o1',
      ownerId: 'u1',
      name: 'Old name',
      type: 'not-a-real-type',
      note: null,
      lat: 1.0,
      lng: 2.0,
      canEdit: true,
      createdAt: DateTime.utc(2026, 8, 22),
      color: null,
    );
    await tester.pumpWidget(_harness(() {}, (_) {}, existing: existing));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final swatch = tester.widget<Container>(find.byKey(const Key('waypoint_color_swatch')));
    final decoration = swatch.decoration as BoxDecoration;
    expect(decoration.color, colorFromHex(waypointTypeColors[defaultWaypointType]!));
  });

  testWidgets('picking a color in the dialog carries it into the form result', (tester) async {
    WaypointFormResult? result;
    await tester.pumpWidget(_harness(() {}, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_color_swatch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_color_picker_select_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    // Tapping "Select" without changing the picker's initial selection keeps
    // it at the effective default it was seeded with -- this asserts the
    // round trip works, not a specific chosen hue (see Task 8 Step 3 note on
    // why the exact seeded value is `waypointTypeColors[defaultWaypointType]`
    // for a new waypoint).
    expect(result!.color, waypointTypeColors[defaultWaypointType]);
  });

  testWidgets('reset to default clears a previously-picked color', (tester) async {
    WaypointFormResult? result;
    await tester.pumpWidget(_harness(() {}, (r) => result = r, existing: _existingWaypoint()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('waypoint_color_swatch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_color_picker_select_button')));
    await tester.pumpAndSettle();

    // Now open again and reset.
    await tester.tap(find.byKey(const Key('waypoint_color_swatch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_color_picker_reset_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    expect(result!.color, isNull);
  });

  testWidgets('changing type does not clear a previously-picked custom color', (tester) async {
    WaypointFormResult? result;
    await tester.pumpWidget(_harness(() {}, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('waypoint_name_field')), 'Summit');
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_color_swatch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waypoint_color_picker_select_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('waypoint_type_chip_water')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('waypoint_save_button')));
    await tester.pumpAndSettle();

    expect(result!.type, 'water');
    expect(result!.color, waypointTypeColors[defaultWaypointType]);
  });
}
