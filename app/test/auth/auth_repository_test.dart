import 'package:app/api/api_client.dart';
import 'package:app/auth/auth_models.dart';
import 'package:app/auth/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('register', () {
    test('returns the access token on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/register');
          return http.Response('{"access_token":"tok-1","token_type":"bearer"}', 200);
        }),
      );
      final repo = HttpAuthRepository(client);

      final token = await repo.register('a@b.test', 'secret123');

      expect(token, 'tok-1');
    });

    test('throws AuthException("Email already registered") on 409', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{"detail":"Email already registered"}', 409)),
      );
      final repo = HttpAuthRepository(client);

      await expectLater(
        repo.register('a@b.test', 'secret123'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'Email already registered')),
      );
    });

    test('throws AuthException on 422', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{"detail":"validation error"}', 422)),
      );
      final repo = HttpAuthRepository(client);

      await expectLater(repo.register('bad', ''), throwsA(isA<AuthException>()));
    });
  });

  group('login', () {
    test('returns the access token on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/login');
          return http.Response('{"access_token":"tok-2","token_type":"bearer"}', 200);
        }),
      );
      final repo = HttpAuthRepository(client);

      final token = await repo.login('a@b.test', 'secret123');

      expect(token, 'tok-2');
    });

    test('throws AuthException("Invalid email or password") on 401', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{"detail":"Invalid email or password"}', 401)),
      );
      final repo = HttpAuthRepository(client);

      await expectLater(
        repo.login('a@b.test', 'wrong'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'Invalid email or password')),
      );
    });
  });

  group('me', () {
    test('returns an AuthUser on 200', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/me');
          expect(request.headers['Authorization'], 'Bearer tok-3');
          return http.Response(
            '{"id":"11111111-1111-1111-1111-111111111111","email":"a@b.test","role":"owner","org_id":"22222222-2222-2222-2222-222222222222"}',
            200,
          );
        }),
      );
      final repo = HttpAuthRepository(client);

      final user = await repo.me('tok-3');

      expect(user.id, '11111111-1111-1111-1111-111111111111');
      expect(user.email, 'a@b.test');
      expect(user.role, 'owner');
      expect(user.orgId, '22222222-2222-2222-2222-222222222222');
    });

    test('throws AuthException on 401', () async {
      final client = ApiClient(
        baseUrl: 'http://example.test',
        httpClient: MockClient((request) async => http.Response('{"detail":"Could not validate credentials"}', 401)),
      );
      final repo = HttpAuthRepository(client);

      await expectLater(repo.me('bad-token'), throwsA(isA<AuthException>()));
    });
  });

  test('network failure surfaces as AuthException', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async => throw const SocketExceptionStub()),
    );
    final repo = HttpAuthRepository(client);

    await expectLater(repo.login('a@b.test', 'secret123'), throwsA(isA<AuthException>()));
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
