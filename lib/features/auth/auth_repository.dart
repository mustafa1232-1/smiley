import '../../core/api_client.dart';
import 'auth_models.dart';

abstract interface class AuthRepository {
  Future<AuthSession> login({
    required String identifier,
    required String password,
  });
  Future<AuthSession> register(RegisterRequest request);
  Future<void> requestPasswordReset(String identifier);
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
}
