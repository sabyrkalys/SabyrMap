import 'package:app/auth/auth_controller.dart';
import 'package:app/auth/auth_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');

ProviderContainer _buildContainer({
  required FakeAuthRepository repo,
  required FakeTokenStorage storage,
}) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(storage),
    ],
  );
}

void main() {
  test('initial state is AuthUnauthenticated', () {
    final container = _buildContainer(repo: FakeAuthRepository(), storage: FakeTokenStorage());
    addTearDown(container.dispose);

    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });

  group('bootstrap', () {
    test('stays AuthUnauthenticated when no token is stored', () async {
      final container = _buildContainer(repo: FakeAuthRepository(), storage: FakeTokenStorage());
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });

    test('becomes AuthAuthenticated when a stored token validates', () async {
      final storage = FakeTokenStorage();
      await storage.write('tok-1');
      final repo = FakeAuthRepository(meResult: _user);
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.email, 'a@b.test');
      expect(repo.lastMeToken, 'tok-1');
    });

    test('clears the token and becomes AuthUnauthenticated when the stored token is invalid', () async {
      final storage = FakeTokenStorage();
      await storage.write('bad-token');
      final repo = FakeAuthRepository(meResult: const AuthException('Could not validate credentials', isAuthFailure: true));
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
      expect(await storage.read(), isNull);
    });

    test('keeps the stored token when the me() failure is a network error, not a 401', () async {
      final storage = FakeTokenStorage();
      await storage.write('some-token');
      final repo = FakeAuthRepository(meResult: const AuthException('Could not connect'));
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
      expect(await storage.read(), 'some-token');
    });
  });

  group('login', () {
    test('on success stores the token and becomes AuthAuthenticated', () async {
      final storage = FakeTokenStorage();
      final repo = FakeAuthRepository(loginResult: 'tok-2', meResult: _user);
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login('a@b.test', 'secret123');

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect(await storage.read(), 'tok-2');
    });

    test('on failure becomes AuthUnauthenticated carrying the error message', () async {
      final repo = FakeAuthRepository(loginResult: const AuthException('Invalid email or password'));
      final container = _buildContainer(repo: repo, storage: FakeTokenStorage());
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login('a@b.test', 'wrong');

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthUnauthenticated>());
      expect((state as AuthUnauthenticated).errorMessage, 'Invalid email or password');
    });
  });

  group('register', () {
    test('on success stores the token and becomes AuthAuthenticated', () async {
      final storage = FakeTokenStorage();
      final repo = FakeAuthRepository(registerResult: 'tok-3', meResult: _user);
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).register('a@b.test', 'secret123');

      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
      expect(await storage.read(), 'tok-3');
    });

    test('on failure becomes AuthUnauthenticated carrying the error message', () async {
      final repo = FakeAuthRepository(registerResult: const AuthException('Email already registered'));
      final container = _buildContainer(repo: repo, storage: FakeTokenStorage());
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).register('a@b.test', 'secret123');

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthUnauthenticated>());
      expect((state as AuthUnauthenticated).errorMessage, 'Email already registered');
    });
  });

  test('logout clears the token and becomes AuthUnauthenticated', () async {
    final storage = FakeTokenStorage();
    await storage.write('tok-4');
    final repo = FakeAuthRepository(meResult: _user);
    final container = _buildContainer(repo: repo, storage: storage);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).bootstrap();
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    expect(await storage.read(), isNull);
  });

  group('clearError', () {
    test('clears an existing error message', () async {
      final repo = FakeAuthRepository(loginResult: const AuthException('Invalid email or password'));
      final container = _buildContainer(repo: repo, storage: FakeTokenStorage());
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).login('a@b.test', 'wrong');
      expect((container.read(authControllerProvider) as AuthUnauthenticated).errorMessage, isNotNull);

      container.read(authControllerProvider.notifier).clearError();

      expect((container.read(authControllerProvider) as AuthUnauthenticated).errorMessage, isNull);
    });

    test('does nothing when not in an unauthenticated state', () async {
      final storage = FakeTokenStorage();
      await storage.write('tok-1');
      const user = AuthUser(id: 'u1', email: 'a@b.test', role: 'owner', orgId: 'o1');
      final repo = FakeAuthRepository(meResult: user);
      final container = _buildContainer(repo: repo, storage: storage);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).bootstrap();
      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());

      container.read(authControllerProvider.notifier).clearError();

      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    });
  });
}
