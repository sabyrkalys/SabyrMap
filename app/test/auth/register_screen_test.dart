import 'dart:async';

import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/auth/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Widget _wrap({required FakeAuthRepository repo, required FakeTokenStorage storage}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(storage),
    ],
    child: const MaterialApp(
      home: RegisterScreen(),
      routes: {'/map': _MapStub.route},
    ),
  );
}

class _MapStub extends StatelessWidget {
  const _MapStub();
  static Widget route(BuildContext context) => const _MapStub();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('map screen'));
}

void main() {
  testWidgets('submit button is disabled until both fields are non-empty', (tester) async {
    await tester.pumpWidget(_wrap(repo: FakeAuthRepository(), storage: FakeTokenStorage()));

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('register_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'secret123');
    await tester.pump();

    final enabledButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('shows the error message and stays on the screen on failure', (tester) async {
    final repo = FakeAuthRepository(registerResult: const AuthException('Email already registered'));
    await tester.pumpWidget(_wrap(repo: repo, storage: FakeTokenStorage()));

    await tester.enterText(find.byKey(const Key('register_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'secret123');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Email already registered'), findsOneWidget);
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('pops back to the previous screen on successful registration', (tester) async {
    const user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');
    final repo = FakeAuthRepository(registerResult: 'tok-1', meResult: user);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  child: const Text('open register'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open register'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    await tester.enterText(find.byKey(const Key('register_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'secret123');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.text('open register'), findsOneWidget);
  });

  testWidgets('submit button is disabled and shows a spinner while loading', (tester) async {
    final gate = Completer<void>();
    const user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');
    final repo = FakeAuthRepository(registerResult: 'tok-1', meResult: user, registerGate: gate);
    await tester.pumpWidget(_wrap(repo: repo, storage: FakeTokenStorage()));

    await tester.enterText(find.byKey(const Key('register_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'secret123');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });
}
