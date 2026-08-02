class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.username,
    required this.displayName,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String username;
  final String displayName;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      userId: user['id'] as String,
      username: user['username'] as String,
      displayName: user['displayName'] as String,
    );
  }
}

class RegisterRequest {
  const RegisterRequest({
    required this.displayName,
    required this.username,
    required this.email,
    required this.password,
    required this.birthDate,
    required this.timezone,
    required this.language,
    required this.acceptedTerms,
  });

  final String displayName;
  final String username;
  final String email;
  final String password;
  final DateTime birthDate;
  final String timezone;
  final String language;
  final bool acceptedTerms;

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'username': username,
    'email': email,
    'password': password,
    'birthDate': birthDate.toIso8601String(),
    'timezone': timezone,
    'language': language,
    'acceptedTerms': acceptedTerms,
  };
}
