import '../../core/api_client.dart';

abstract interface class SpaceRepository {
  Future<SpaceSummary> summary();
  Future<List<SpacePost>> posts();
  Future<SpacePost> createPost({String? title, required String body});
  Future<SpaceMood> createMood({
    required String kind,
    String? emoji,
    String? note,
  });
  Future<List<ChatMessage>> messages();
  Future<ChatMessage> sendMessage(String body);
  Future<List<CalendarItem>> calendarEvents();
  Future<CalendarItem> createCalendarEvent({
    required String title,
    required DateTime startsAt,
  });
  Future<List<NotificationItem>> notifications();
}

class HttpSpaceRepository implements SpaceRepository {
  const HttpSpaceRepository(this._api);

  final ApiClient _api;

  @override
  Future<SpaceSummary> summary() async {
    final json = await _api.getJson('/space');
    return SpaceSummary.fromJson(json);
  }

  @override
  Future<List<SpacePost>> posts() async {
    final json = await _api.getJson('/posts');
    return _items(json).map(SpacePost.fromJson).toList();
  }

  @override
  Future<SpacePost> createPost({String? title, required String body}) async {
    final json = await _api.postJson('/posts', {
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      'body': body.trim(),
    });
    return SpacePost.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<SpaceMood> createMood({
    required String kind,
    String? emoji,
    String? note,
  }) async {
    final body = <String, dynamic>{'kind': kind};
    if (emoji != null) body['emoji'] = emoji;
    if (note != null && note.trim().isNotEmpty) body['note'] = note.trim();

    final json = await _api.postJson('/moods', body);
    return SpaceMood.fromJson(json['mood'] as Map<String, dynamic>);
  }

  @override
  Future<List<ChatMessage>> messages() async {
    final json = await _api.getJson('/messages');
    return _items(json).map(ChatMessage.fromJson).toList();
  }

  @override
  Future<ChatMessage> sendMessage(String body) async {
    final json = await _api.postJson('/messages', {
      'clientMessageId': 'm-${DateTime.now().microsecondsSinceEpoch}',
      'body': body.trim(),
    });
    return ChatMessage.fromJson(json['message'] as Map<String, dynamic>);
  }

  @override
  Future<List<CalendarItem>> calendarEvents() async {
    final json = await _api.getJson('/calendar-events');
    return _items(json).map(CalendarItem.fromJson).toList();
  }

  @override
  Future<CalendarItem> createCalendarEvent({
    required String title,
    required DateTime startsAt,
  }) async {
    final json = await _api.postJson('/calendar-events', {
      'title': title.trim(),
      'startsAt': startsAt.toUtc().toIso8601String(),
    });
    return CalendarItem.fromJson(json['event'] as Map<String, dynamic>);
  }

  @override
  Future<List<NotificationItem>> notifications() async {
    final json = await _api.getJson('/notifications');
    return _items(json).map(NotificationItem.fromJson).toList();
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> json) {
    return (json['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }
}

class SpaceSummary {
  const SpaceSummary({
    required this.partnershipId,
    required this.worldName,
    required this.daysTogether,
    required this.members,
    required this.latestPosts,
    required this.unreadNotifications,
    this.latestMood,
    this.nextEvent,
  });

  final String partnershipId;
  final String? worldName;
  final int? daysTogether;
  final List<SpaceMember> members;
  final SpaceMood? latestMood;
  final List<SpacePost> latestPosts;
  final CalendarItem? nextEvent;
  final int unreadNotifications;

  factory SpaceSummary.fromJson(Map<String, dynamic> json) {
    final partnership = json['partnership'] as Map<String, dynamic>;
    final members = (partnership['members'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(SpaceMember.fromJson)
        .toList();
    final latestMood = json['latestMood'] as Map<String, dynamic>?;
    final nextEvent = json['nextEvent'] as Map<String, dynamic>?;
    final posts = (json['latestPosts'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(SpacePost.fromJson)
        .toList();

    return SpaceSummary(
      partnershipId: partnership['id'] as String,
      worldName: partnership['worldName'] as String?,
      daysTogether: partnership['daysTogether'] as int?,
      members: members,
      latestMood: latestMood == null ? null : SpaceMood.fromJson(latestMood),
      latestPosts: posts,
      nextEvent: nextEvent == null ? null : CalendarItem.fromJson(nextEvent),
      unreadNotifications: json['unreadNotifications'] as int? ?? 0,
    );
  }
}

class SpaceMember {
  const SpaceMember({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String username;
  final String displayName;

  factory SpaceMember.fromJson(Map<String, dynamic> json) {
    return SpaceMember(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? 'مستخدم',
    );
  }
}

class SpaceMood {
  const SpaceMood({
    required this.id,
    required this.kind,
    this.emoji,
    this.note,
  });

  final String id;
  final String kind;
  final String? emoji;
  final String? note;

  factory SpaceMood.fromJson(Map<String, dynamic> json) {
    return SpaceMood(
      id: json['id'] as String,
      kind: json['kind'] as String,
      emoji: json['emoji'] as String?,
      note: json['note'] as String?,
    );
  }
}

class SpacePost {
  const SpacePost({
    required this.id,
    required this.body,
    required this.createdAt,
    this.title,
  });

  final String id;
  final String? title;
  final String body;
  final DateTime createdAt;

  factory SpacePost.fromJson(Map<String, dynamic> json) {
    return SpacePost(
      id: json['id'] as String,
      title: json['title'] as String?,
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.serverTimestamp,
  });

  final String id;
  final String body;
  final DateTime serverTimestamp;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      serverTimestamp: DateTime.parse(json['serverTimestamp'] as String),
    );
  }
}

class CalendarItem {
  const CalendarItem({
    required this.id,
    required this.title,
    required this.startsAt,
  });

  final String id;
  final String title;
  final DateTime startsAt;

  factory CalendarItem.fromJson(Map<String, dynamic> json) {
    return CalendarItem(
      id: json['id'] as String,
      title: json['title'] as String,
      startsAt: DateTime.parse(json['startsAt'] as String),
    );
  }
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    this.body,
  });

  final String id;
  final String title;
  final String? body;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
    );
  }
}
