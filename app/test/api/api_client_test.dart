import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('get sends request to baseUrl + path with no auth header when token is null', () async {
    Uri? capturedUri;
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedUri = request.url;
      capturedHeaders = request.headers;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.get('/auth/me');

    expect(capturedUri, Uri.parse('http://example.test/auth/me'));
    expect(capturedHeaders!.containsKey('Authorization'), isFalse);
  });

  test('get attaches Authorization header when token is provided', () async {
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedHeaders = request.headers;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.get('/auth/me', token: 'abc123');

    expect(capturedHeaders!['Authorization'], 'Bearer abc123');
  });

  test('post sends JSON-encoded body with Content-Type header', () async {
    String? capturedBody;
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedBody = request.body;
      capturedHeaders = request.headers;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.post('/auth/login', body: {'email': 'a@b.test', 'password': 'secret'});

    expect(jsonDecode(capturedBody!), {'email': 'a@b.test', 'password': 'secret'});
    expect(capturedHeaders!['Content-Type'], contains('application/json'));
  });

  test('post with no body sends an empty JSON object', () async {
    String? capturedBody;
    final mockClient = MockClient((request) async {
      capturedBody = request.body;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.post('/auth/logout');

    expect(capturedBody, '{}');
  });

  test('returns the underlying response unchanged', () async {
    final mockClient = MockClient((request) async => http.Response('{"ok":true}', 201));
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    final response = await client.post('/auth/register');

    expect(response.statusCode, 201);
    expect(response.body, '{"ok":true}');
  });
}
