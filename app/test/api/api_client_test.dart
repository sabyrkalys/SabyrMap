import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('get sends request to baseUrl + path with no Authorization header', () async {
    Uri? capturedUri;
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedUri = request.url;
      capturedHeaders = request.headers;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.get('/waypoints');

    expect(capturedUri, Uri.parse('http://example.test/waypoints'));
    expect(capturedHeaders!.containsKey('Authorization'), isFalse);
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

    await client.post('/waypoints', body: {'email': 'a@b.test', 'password': 'secret'});

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

    await client.post('/waypoints');

    expect(capturedBody, '{}');
  });

  test('returns the underlying response unchanged', () async {
    final mockClient = MockClient((request) async => http.Response('{"ok":true}', 201));
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    final response = await client.post('/waypoints');

    expect(response.statusCode, 201);
    expect(response.body, '{"ok":true}');
  });

  test('patch sends JSON-encoded body with Content-Type header', () async {
    String? capturedBody;
    String? capturedMethod;
    final mockClient = MockClient((request) async {
      capturedBody = request.body;
      capturedMethod = request.method;
      return http.Response('{}', 200);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    await client.patch('/waypoints/1', body: {'name': 'New'});

    expect(capturedMethod, 'PATCH');
    expect(jsonDecode(capturedBody!), {'name': 'New'});
  });

  test('delete sends DELETE to baseUrl + path with no Authorization header', () async {
    Uri? capturedUri;
    String? capturedMethod;
    Map<String, String>? capturedHeaders;
    final mockClient = MockClient((request) async {
      capturedUri = request.url;
      capturedMethod = request.method;
      capturedHeaders = request.headers;
      return http.Response('', 204);
    });
    final client = ApiClient(baseUrl: 'http://example.test', httpClient: mockClient);

    final response = await client.delete('/waypoints/1');

    expect(capturedUri, Uri.parse('http://example.test/waypoints/1'));
    expect(capturedMethod, 'DELETE');
    expect(capturedHeaders!.containsKey('Authorization'), isFalse);
    expect(response.statusCode, 204);
  });
}
