import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  static const Map<String, String> _headers = {'Content-Type': 'application/json'};

  Future<http.Response> get(String path) {
    return _httpClient.get(Uri.parse('$baseUrl$path'), headers: _headers);
  }

  Future<http.Response> post(String path, {Map<String, dynamic>? body}) {
    return _httpClient.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body ?? const {}),
    );
  }

  Future<http.Response> patch(String path, {Map<String, dynamic>? body}) {
    return _httpClient.patch(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body ?? const {}),
    );
  }

  Future<http.Response> delete(String path) {
    return _httpClient.delete(Uri.parse('$baseUrl$path'), headers: _headers);
  }
}
