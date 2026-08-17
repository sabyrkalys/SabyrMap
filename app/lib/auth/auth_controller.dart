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

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnauthenticated();

  AuthRepository get _repository => ref.read(authRepositoryProvider);
  TokenStorage get _storage => ref.read(tokenStorageProvider);

  Future<void> bootstrap() async {
    final token = await _storage.read();
    if (token == null) {
      state = const AuthUnauthenticated();
      return;
    }
    state = const AuthAuthenticating();
    try {
      final user = await _repository.me(token);
      state = AuthAuthenticated(user);
    } on AuthException {
      await _storage.delete();
      state = const AuthUnauthenticated();
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
}
