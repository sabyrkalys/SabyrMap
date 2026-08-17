import 'dart:async';

import 'package:app/auth/auth_models.dart';
import 'package:app/auth/auth_repository.dart';
import 'package:app/auth/token_storage.dart';

class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async {
    _token = token;
  }

  @override
  Future<void> delete() async {
    _token = null;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.registerResult,
    this.loginResult,
    this.meResult,
    this.loginGate,
    this.registerGate,
  });

  /// Set to a token String for success, or an AuthException instance to throw.
  Object? registerResult;
  Object? loginResult;
  Object? meResult;

  /// When set, login()/register() await this before resolving — lets a test
  /// observe the transient AuthAuthenticating state before completing it.
  Completer<void>? loginGate;
  Completer<void>? registerGate;

  String? lastRegisterEmail;
  String? lastLoginEmail;
  String? lastMeToken;

  @override
  Future<String> register(String email, String password) async {
    lastRegisterEmail = email;
    if (registerGate != null) await registerGate!.future;
    if (registerResult is AuthException) throw registerResult as AuthException;
    return registerResult as String;
  }

  @override
  Future<String> login(String email, String password) async {
    lastLoginEmail = email;
    if (loginGate != null) await loginGate!.future;
    if (loginResult is AuthException) throw loginResult as AuthException;
    return loginResult as String;
  }

  @override
  Future<AuthUser> me(String token) async {
    lastMeToken = token;
    if (meResult is AuthException) throw meResult as AuthException;
    return meResult as AuthUser;
  }
}
