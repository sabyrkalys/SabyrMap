import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/compass/compass_source.dart';
import 'package:app/main.dart';
import 'package:app/tracks/tracks_controller.dart';
import 'package:app/waypoints/waypoints_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth/fakes.dart';
import 'compass/fakes.dart';
import 'tracks/fakes.dart';
import 'waypoints/fakes.dart';

void main() {
  testWidgets('login then logout then login again returns to LoginScreen each time', (tester) async {
    const user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');
    final repo = FakeAuthRepository(loginResult: 'tok-1', meResult: user);
    final storage = FakeTokenStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          tokenStorageProvider.overrideWithValue(storage),
          waypointsRepositoryProvider.overrideWithValue(FakeWaypointsRepository()),
          tracksRepositoryProvider.overrideWithValue(FakeTracksRepository()),
          compassSourceProvider.overrideWithValue(FakeUnavailableCompassSource()),
        ],
        child: const AlpineQuestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsWidgets);

    await tester.enterText(find.byKey(const Key('login_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret123');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsNothing);
    expect(find.byKey(const Key('nav_settings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_logout_button')));
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsWidgets);

    // log back in a second time, proving AuthGate is still the live navigation authority
    await tester.enterText(find.byKey(const Key('login_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret123');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nav_settings')), findsOneWidget);
  });
}
