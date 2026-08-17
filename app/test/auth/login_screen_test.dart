import 'dart:async';

import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/auth/login_screen.dart';
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
      home: LoginScreen(),
      routes: {'/register': _RegisterStub.route, '/map': _MapStub.route},
    ),
  );
}

class _RegisterStub extends StatelessWidget {
  const _RegisterStub();
  static Widget route(BuildContext context) => const _RegisterStub();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('register screen'));
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

    await tester.enterText(find.byKey(const Key('login_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret123');
    await tester.pump();

    final enabledButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('shows the error message and stays on the screen on failure', (tester) async {
    final repo = FakeAuthRepository(loginResult: const AuthException('Invalid email or password'));
    await tester.pumpWidget(_wrap(repo: repo, storage: FakeTokenStorage()));

    await tester.enterText(find.byKey(const Key('login_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'wrong');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('submit button is disabled and shows a spinner while loading', (tester) async {
    final gate = Completer<void>();
    const user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');
    final repo = FakeAuthRepository(loginResult: 'tok-1', meResult: user, loginGate: gate);
    await tester.pumpWidget(_wrap(repo: repo, storage: FakeTokenStorage()));

    await tester.enterText(find.byKey(const Key('login_email_field')), 'a@b.test');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret123');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('tapping "Create account" navigates to /register', (tester) async {
    await tester.pumpWidget(_wrap(repo: FakeAuthRepository(), storage: FakeTokenStorage()));

    await tester.tap(find.byKey(const Key('login_create_account_button')));
    await tester.pumpAndSettle();

    expect(find.text('register screen'), findsOneWidget);
  });
}
