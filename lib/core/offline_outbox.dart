import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class OfflineOutbox {
  Future<List<QueuedMessage>> messages();
  Future<List<QueuedPost>> posts();
  Future<void> enqueueMessage(String body, {List<String> assetIds});
  Future<void> enqueuePost({required String body, List<String> assetIds});
  Future<void> removeMessage(String id);
  Future<void> removePost(String id);
}

class SharedPreferencesOfflineOutbox implements OfflineOutbox {
  const SharedPreferencesOfflineOutbox();

  static const _messagesKey = 'smiley.offline.messages';
  static const _postsKey = 'smiley.offline.posts';

  @override
  Future<List<QueuedMessage>> messages() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_messagesKey), QueuedMessage.fromJson);
  }

  @override
  Future<List<QueuedPost>> posts() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_postsKey), QueuedPost.fromJson);
  }

  @override
  Future<void> enqueueMessage(
    String body, {
    List<String> assetIds = const [],
  }) async {
    final items = await messages();
    items.add(
      QueuedMessage(
        id: _id(),
        body: body.trim(),
        assetIds: assetIds,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await _save(_messagesKey, items.map((item) => item.toJson()).toList());
  }

  @override
  Future<void> enqueuePost({
    required String body,
    List<String> assetIds = const [],
  }) async {
    final items = await posts();
    items.add(
      QueuedPost(
        id: _id(),
        body: body.trim(),
        assetIds: assetIds,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await _save(_postsKey, items.map((item) => item.toJson()).toList());
  }

  @override
  Future<void> removeMessage(String id) async {
    final items = await messages();
    await _save(
      _messagesKey,
      items
          .where((item) => item.id != id)
          .map((item) => item.toJson())
          .toList(),
    );
  }

  @override
  Future<void> removePost(String id) async {
    final items = await posts();
    await _save(
      _postsKey,
      items
          .where((item) => item.id != id)
          .map((item) => item.toJson())
          .toList(),
    );
  }

  Future<void> _save(String key, List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(items));
  }
}

class QueuedMessage {
  const QueuedMessage({
    required this.id,
    required this.body,
    required this.assetIds,
    required this.createdAt,
  });

  final String id;
  final String body;
  final List<String> assetIds;
  final DateTime createdAt;

  factory QueuedMessage.fromJson(Map<String, dynamic> json) {
    return QueuedMessage(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      assetIds: (json['assetIds'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'body': body,
      'assetIds': assetIds,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class QueuedPost {
  const QueuedPost({
    required this.id,
    required this.body,
    required this.assetIds,
    required this.createdAt,
  });

  final String id;
  final String body;
  final List<String> assetIds;
  final DateTime createdAt;

  factory QueuedPost.fromJson(Map<String, dynamic> json) {
    return QueuedPost(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      assetIds: (json['assetIds'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'body': body,
      'assetIds': assetIds,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

List<T> _decodeList<T>(
  String? encoded,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (encoded == null || encoded.isEmpty) return [];
  final decoded = jsonDecode(encoded) as List<dynamic>;
  return decoded.cast<Map<String, dynamic>>().map(fromJson).toList();
}

String _id() => 'q-${DateTime.now().microsecondsSinceEpoch}';
