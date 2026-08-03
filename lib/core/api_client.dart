import 'dart:convert';

import 'package:http/http.dart' as http;

const _requestTimeout = Duration(seconds: 20);

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    this.refreshTokenProvider,
    this.tokenSaver,
    this.onAuthFailed,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final Future<String?> Function()? refreshTokenProvider;
  final Future<void> Function({
    required String accessToken,
    required String refreshToken,
  })?
  tokenSaver;
  final Future<void> Function()? onAuthFailed;
  final http.Client _client;
  Future<bool>? _refreshInFlight;

  Future<Map<String, dynamic>> getJson(String path) {
    return _requestJson('GET', path);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) {
    return _requestJson('POST', path, body: body);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) {
    return _requestJson('PATCH', path, body: body);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _requestJson('DELETE', path, body: body);
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool canRefresh = true,
  }) async {
    var response = await _send(method, path, body: body);
    if (response.statusCode == 401 && canRefresh && path != '/auth/refresh') {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        response = await _send(method, path, body: body);
      }
    }
    return _decode(response);
  }

  Future<bool> _refreshAccessToken() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _doRefreshAccessToken();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefreshAccessToken() async {
    final refreshProvider = refreshTokenProvider;
    final save = tokenSaver;
    if (refreshProvider == null || save == null) return false;

    final refreshToken = await refreshProvider();
    if (refreshToken == null) return false;

    try {
      final response = await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
        includeAuth: false,
      );
      final json = _decode(response);
      await save(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      );
      return true;
    } on ApiException {
      await onAuthFailed?.call();
      return false;
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool includeAuth = true,
  }) async {
    try {
      final headers = await _headers(includeAuth: includeAuth);
      final uri = _uri(path);
      final encodedBody = body == null ? null : jsonEncode(body);
      return switch (method) {
        'GET' =>
          await _client.get(uri, headers: headers).timeout(_requestTimeout),
        'POST' =>
          await _client
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_requestTimeout),
        'PATCH' =>
          await _client
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(_requestTimeout),
        'DELETE' =>
          await _client
              .delete(uri, headers: headers, body: encodedBody)
              .timeout(_requestTimeout),
        _ => throw StateError('Unsupported HTTP method $method'),
      };
    } catch (error) {
      if (error is ApiException) rethrow;
      throw const ApiException(
        code: 'network_error',
        message: 'تعذر الاتصال بالخادم. تأكد من الإنترنت ثم حاول مرة أخرى.',
      );
    }
  }

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Future<Map<String, String>> _headers({required bool includeAuth}) async {
    final token = includeAuth ? await tokenProvider() : null;
    return {
      'content-type': 'application/json',
      'accept': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final code = decoded['code']?.toString() ?? 'request_failed';
    final message =
        decoded['message']?.toString() ?? 'تعذر إكمال الطلب. حاول مرة أخرى.';
    throw ApiException(code: code, message: message);
  }
}

class ApiException implements Exception {
  const ApiException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => message;
}
