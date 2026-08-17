import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  Future<http.Response> get(String path, {String? token}) {
    return _httpClient.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
    );
  }

  Future<http.Response> post(String path, {Map<String, dynamic>? body, String? token}) {
    return _httpClient.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body ?? const {}),
    );
  }

  Map<String, String> _headers(String? token) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
