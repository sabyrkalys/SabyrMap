import 'dart:convert';

import 'package:app/api/api_client.dart';

import 'auth_models.dart';

abstract class AuthRepository {
  Future<String> register(String email, String password);
  Future<String> login(String email, String password);
  Future<AuthUser> me(String token);
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<String> register(String email, String password) {
    return _postForToken('/auth/register', email, password, messageForStatus: (status) {
      if (status == 409) return 'Email already registered';
      if (status >= 500) return 'Something went wrong, please try again';
      return 'Please check your email and password';
    });
  }

  @override
  Future<String> login(String email, String password) {
    return _postForToken('/auth/login', email, password, messageForStatus: (status) {
      if (status == 401) return 'Invalid email or password';
      if (status >= 500) return 'Something went wrong, please try again';
      return 'Please check your email and password';
    });
  }

  Future<String> _postForToken(
    String path,
    String email,
    String password, {
    required String Function(int statusCode) messageForStatus,
  }) async {
    try {
      final response = await _client.post(path, body: {'email': email, 'password': password});
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['access_token'] as String;
      }
      throw AuthException(messageForStatus(response.statusCode));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not connect');
    }
  }

  @override
  Future<AuthUser> me(String token) async {
    try {
      final response = await _client.get('/auth/me', token: token);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return AuthUser(
          id: json['id'] as String,
          email: json['email'] as String,
          role: json['role'] as String,
          orgId: json['org_id'] as String,
        );
      }
      throw const AuthException('Could not validate credentials', isAuthFailure: true);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not connect');
    }
  }
}
