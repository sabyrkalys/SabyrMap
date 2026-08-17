import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/map/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/fakes.dart';

void main() {
  testWidgets('MapScreen builds without throwing and shows a logout action', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          tokenStorageProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('tapping logout calls AuthController.logout', (tester) async {
    final storage = FakeTokenStorage();
    await storage.write('tok-1');
    final repo = FakeAuthRepository(
      meResult: const AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1'),
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();

    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });
}
