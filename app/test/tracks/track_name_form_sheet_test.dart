import 'package:app/tracks/track_name_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(ValueChanged<TrackNameFormResult?> onResult) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final result = await showTrackNameFormSheet(context, initialName: 'Трек 22.08.2026 15:30');
            onResult(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('pre-fills the initial name and save is disabled once cleared', (tester) async {
    TrackNameFormResult? result;
    await tester.pumpWidget(_harness((r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Трек 22.08.2026 15:30'), findsOneWidget);
    var saveButton = tester.widget<FilledButton>(find.byKey(const Key('track_save_button')));
    expect(saveButton.onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('track_name_field')), '');
    await tester.pump();
    saveButton = tester.widget<FilledButton>(find.byKey(const Key('track_save_button')));
    expect(saveButton.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('track_name_field')), 'My hike');
    await tester.pump();
    await tester.tap(find.byKey(const Key('track_save_button')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.name, 'My hike');
  });

  testWidgets('returns null when dismissed without saving', (tester) async {
    TrackNameFormResult? result = const TrackNameFormResult(name: 'sentinel');
    await tester.pumpWidget(_harness((r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
