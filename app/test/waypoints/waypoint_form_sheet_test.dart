import 'package:app/waypoints/waypoint_form_sheet.dart';
import 'package:app/waypoints/waypoint_models.dart';
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
    WaypointFormResult? result = const WaypointFormResult(name: 'sentinel', type: 'generic', note: '');
    await tester.pumpWidget(_harness(() {}, (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
