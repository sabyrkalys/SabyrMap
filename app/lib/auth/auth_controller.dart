import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../config.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'token_storage.dart';

sealed class AuthState {
  const AuthState();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.errorMessage});

  final String? errorMessage;
}

class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final AuthUser user;
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: AppConfig.apiBaseUrl);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return HttpAuthRepository(ref.watch(apiClientProvider));
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

const String _devAutoLoginEmail = 'alpinequest.dev@example.com';
const String _devAutoLoginPassword = 'dev-password-123';

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnauthenticated();

  AuthRepository get _repository => ref.read(authRepositoryProvider);
  TokenStorage get _storage => ref.read(tokenStorageProvider);

  Future<void> bootstrap() async {
    final token = await _storage.read();
    if (token == null) {
      if (AppConfig.devAutoLoginEnabled) {
        await _devAutoLogin();
      } else {
        state = const AuthUnauthenticated();
      }
      return;
    }
    state = const AuthAuthenticating();
    try {
      final user = await _repository.me(token);
      state = AuthAuthenticated(user);
    } on AuthException catch (e) {
      if (e.isAuthFailure) {
        await _storage.delete();
      }
      if (AppConfig.devAutoLoginEnabled) {
        await _devAutoLogin();
      } else {
        state = const AuthUnauthenticated();
      }
    }
  }

  Future<void> _devAutoLogin() async {
    state = const AuthAuthenticating();
    try {
      final token = await _repository.login(_devAutoLoginEmail, _devAutoLoginPassword);
      final user = await _repository.me(token);
      await _storage.write(token);
      state = AuthAuthenticated(user);
      return;
    } on AuthException {
      // Falls through to registration below (e.g. dev account doesn't exist yet).
    }
    try {
      final token = await _repository.register(_devAutoLoginEmail, _devAutoLoginPassword);
      final user = await _repository.me(token);
      await _storage.write(token);
      state = AuthAuthenticated(user);
    } on AuthException catch (e) {
      state = AuthUnauthenticated(errorMessage: e.message);
    }
  }

  Future<void> login(String email, String password) => _authenticate(
        () => _repository.login(email, password),
      );

  Future<void> register(String email, String password) => _authenticate(
        () => _repository.register(email, password),
      );

  Future<void> _authenticate(Future<String> Function() obtainToken) async {
    state = const AuthAuthenticating();
    try {
      final token = await obtainToken();
      final user = await _repository.me(token);
      await _storage.write(token);
      state = AuthAuthenticated(user);
    } on AuthException catch (e) {
      state = AuthUnauthenticated(errorMessage: e.message);
    }
  }

  Future<void> logout() async {
    await _storage.delete();
    state = const AuthUnauthenticated();
  }

  void clearError() {
    if (state is AuthUnauthenticated) {
      state = const AuthUnauthenticated();
    }
  }
}
