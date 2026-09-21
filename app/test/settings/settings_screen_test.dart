import 'package:app/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows only the title and has no logout entry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('Настройки'), findsOneWidget);
    expect(find.byKey(const Key('settings_logout_button')), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });
}
