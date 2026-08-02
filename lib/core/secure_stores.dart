import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class GateStore {
  Future<bool> isUnlocked();
  Future<void> markUnlocked();
  Future<void> reset();
}

abstract interface class AuthTokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clear();
}

class SecureGateStore implements GateStore {
  const SecureGateStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'smiley.date_gate.unlocked';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> isUnlocked() async => await _storage.read(key: _key) == '1';

  @override
  Future<void> markUnlocked() => _storage.write(key: _key, value: '1');

  @override
  Future<void> reset() => _storage.delete(key: _key);
}

class SecureAuthTokenStore implements AuthTokenStore {
  const SecureAuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'smiley.auth.access_token';
  static const _refreshKey = 'smiley.auth.refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
