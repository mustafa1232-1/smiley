import '../../core/api_client.dart';
import 'auth_models.dart';

abstract interface class AuthRepository {
  Future<AuthSession> login({
    required String identifier,
    required String password,
  });
  Future<AuthSession> register(RegisterRequest request);
  Future<void> requestPasswordReset(String identifier);
  Future<AuthSession> refresh(String refreshToken);
  Future<void> logout(String refreshToken);
  Future<void> logoutAll();
  Future<List<LoginSessionModel>> sessions();
  Future<void> revokeSession(String id);
}

class HttpAuthRepository implements AuthRepository {
  const HttpAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final json = await _api.postJson('/auth/login', {
      'identifier': identifier,
      'password': password,
    });
    return AuthSession.fromJson(json);
  }

  @override
  Future<AuthSession> register(RegisterRequest request) async {
    final json = await _api.postJson('/auth/register', request.toJson());
    return AuthSession.fromJson(json);
  }

  @override
  Future<void> requestPasswordReset(String identifier) async {
    await _api.postJson('/auth/password-reset/request', {
      'identifier': identifier,
    });
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    final json = await _api.postJson('/auth/refresh', {
      'refreshToken': refreshToken,
    });
    return AuthSession.fromJson(json);
  }

  @override
  Future<void> logout(String refreshToken) async {
    await _api.postJson('/auth/logout', {'refreshToken': refreshToken});
  }

  @override
  Future<void> logoutAll() async {
    await _api.postJson('/auth/logout-all', {});
  }

  @override
  Future<List<LoginSessionModel>> sessions() async {
    final json = await _api.getJson('/auth/sessions');
    final items = json['items'] as List<dynamic>? ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map(LoginSessionModel.fromJson)
        .toList();
  }

  @override
  Future<void> revokeSession(String id) async {
    await _api.deleteJson('/auth/sessions/$id');
  }
}

class LoginSessionModel {
  const LoginSessionModel({
    required this.id,
    required this.current,
    required this.createdAt,
    required this.updatedAt,
    this.revokedAt,
    this.userAgent,
    this.platform,
    this.deviceName,
  });

  final String id;
  final bool current;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? revokedAt;
  final String? userAgent;
  final String? platform;
  final String? deviceName;

  bool get active => revokedAt == null;

  factory LoginSessionModel.fromJson(Map<String, dynamic> json) {
    final device = json['device'] as Map<String, dynamic>?;
    return LoginSessionModel(
      id: json['id'] as String,
      current: json['current'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      revokedAt: _optionalDate(json['revokedAt']),
      userAgent: json['userAgent'] as String?,
      platform: device?['platform'] as String?,
      deviceName: device?['deviceName'] as String?,
    );
  }
}

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  return DateTime.parse(value as String);
}
