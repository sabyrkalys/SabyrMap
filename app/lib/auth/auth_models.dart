class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    required this.orgId,
  });

  final String id;
  final String email;
  final String role;
  final String orgId;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
