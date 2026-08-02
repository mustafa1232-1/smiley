import '../../core/api_client.dart';

abstract interface class SpaceRepository {
  Future<UserProfile> me();
  Future<void> updateProfile({
    required String displayName,
    String? bio,
    required bool searchable,
    required bool canReceiveRequests,
  });
  Future<void> updateSettings({String? worldName, String? themeColor});
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
  Future<void> readAllNotifications();
  Future<List<WishItem>> wishes();
  Future<void> createWish(String title);
  Future<void> toggleWish(String id);
  Future<List<GoalItem>> goals();
  Future<void> createGoal({required String title, List<String> steps});
  Future<void> toggleGoal(String id);
  Future<void> toggleGoalStep(String id);
  Future<List<SharedListModel>> sharedLists();
  Future<void> createSharedList({required String title, required String kind});
  Future<void> addSharedListItem({required String listId, required String title});
  Future<void> toggleSharedListItem(String id);
  Future<List<PlaceItem>> places();
  Future<void> createPlace(String title);
  Future<List<AlbumModel>> albums();
  Future<void> createAlbum(String title);
  Future<RoomModel> musicRoom();
  Future<void> addMusicItem(String title);
  Future<RoomModel> watchRoom();
  Future<void> addWatchItem(String title);
}

class HttpSpaceRepository implements SpaceRepository {
  const HttpSpaceRepository(this._api);

  final ApiClient _api;

  @override
  Future<UserProfile> me() async {
    final json = await _api.getJson('/me');
    return UserProfile.fromJson(json['user'] as Map<String, dynamic>);
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    String? bio,
    required bool searchable,
    required bool canReceiveRequests,
  }) async {
    await _api.patchJson('/me', {
      'displayName': displayName.trim(),
      if (bio != null) 'bio': bio.trim(),
      'searchable': searchable,
      'canReceivePartnershipRequests': canReceiveRequests,
    });
  }

  @override
  Future<void> updateSettings({String? worldName, String? themeColor}) async {
    final body = <String, dynamic>{};
    if (worldName != null && worldName.trim().isNotEmpty) {
      body['worldName'] = worldName.trim();
    }
    if (themeColor != null) body['themeColor'] = themeColor;
    await _api.patchJson('/partnerships/current/settings', body);
  }

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

  @override
  Future<void> readAllNotifications() async {
    await _api.postJson('/notifications/read-all', {});
  }

  @override
  Future<List<WishItem>> wishes() async {
    final json = await _api.getJson('/wishes');
    return _items(json).map(WishItem.fromJson).toList();
  }

  @override
  Future<void> createWish(String title) async {
    await _api.postJson('/wishes', {'title': title.trim()});
  }

  @override
  Future<void> toggleWish(String id) async {
    await _api.postJson('/wishes/$id/toggle', {});
  }

  @override
  Future<List<GoalItem>> goals() async {
    final json = await _api.getJson('/goals');
    return _items(json).map(GoalItem.fromJson).toList();
  }

  @override
  Future<void> createGoal({required String title, List<String> steps = const []}) async {
    await _api.postJson('/goals', {
      'title': title.trim(),
      'steps': steps.map((step) => step.trim()).where((step) => step.isNotEmpty).toList(),
    });
  }

  @override
  Future<void> toggleGoal(String id) async {
    await _api.postJson('/goals/$id/toggle', {});
  }

  @override
  Future<void> toggleGoalStep(String id) async {
    await _api.postJson('/goal-steps/$id/toggle', {});
  }

  @override
  Future<List<SharedListModel>> sharedLists() async {
    final json = await _api.getJson('/shared-lists');
    return _items(json).map(SharedListModel.fromJson).toList();
  }

  @override
  Future<void> createSharedList({required String title, required String kind}) async {
    await _api.postJson('/shared-lists', {
      'title': title.trim(),
      'kind': kind.trim().isEmpty ? 'general' : kind.trim(),
    });
  }

  @override
  Future<void> addSharedListItem({required String listId, required String title}) async {
    await _api.postJson('/shared-lists/$listId/items', {'title': title.trim()});
  }

  @override
  Future<void> toggleSharedListItem(String id) async {
    await _api.postJson('/shared-list-items/$id/toggle', {});
  }

  @override
  Future<List<PlaceItem>> places() async {
    final json = await _api.getJson('/places');
    return _items(json).map(PlaceItem.fromJson).toList();
  }

  @override
  Future<void> createPlace(String title) async {
    await _api.postJson('/places', {'title': title.trim()});
  }

  @override
  Future<List<AlbumModel>> albums() async {
    final json = await _api.getJson('/albums');
    return _items(json).map(AlbumModel.fromJson).toList();
  }

  @override
  Future<void> createAlbum(String title) async {
    await _api.postJson('/albums', {'title': title.trim()});
  }

  @override
  Future<RoomModel> musicRoom() async {
    final json = await _api.getJson('/music-room');
    return RoomModel.fromMusicJson(json['room'] as Map<String, dynamic>);
  }

  @override
  Future<void> addMusicItem(String title) async {
    await _api.postJson('/music-room/queue', {'title': title.trim()});
  }

  @override
  Future<RoomModel> watchRoom() async {
    final json = await _api.getJson('/watch-room');
    return RoomModel.fromWatchJson(json['room'] as Map<String, dynamic>);
  }

  @override
  Future<void> addWatchItem(String title) async {
    await _api.postJson('/watch-room/items', {'title': title.trim()});
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

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.searchable,
    required this.canReceiveRequests,
    this.email,
    this.bio,
  });

  final String id;
  final String username;
  final String? email;
  final String displayName;
  final String? bio;
  final bool searchable;
  final bool canReceiveRequests;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      displayName: json['displayName'] as String? ?? 'مستخدم',
      bio: json['bio'] as String?,
      searchable: json['searchable'] as bool? ?? true,
      canReceiveRequests:
          json['canReceivePartnershipRequests'] as bool? ?? true,
    );
  }
}

class WishItem {
  const WishItem({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  factory WishItem.fromJson(Map<String, dynamic> json) {
    return WishItem(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['completedAt'] != null,
    );
  }
}

class GoalItem {
  const GoalItem({
    required this.id,
    required this.title,
    required this.completed,
    required this.steps,
  });

  final String id;
  final String title;
  final bool completed;
  final List<GoalStepItem> steps;

  factory GoalItem.fromJson(Map<String, dynamic> json) {
    final steps = (json['steps'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(GoalStepItem.fromJson)
        .toList();
    return GoalItem(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['completedAt'] != null,
      steps: steps,
    );
  }
}

class GoalStepItem {
  const GoalStepItem({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  factory GoalStepItem.fromJson(Map<String, dynamic> json) {
    return GoalStepItem(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['completedAt'] != null,
    );
  }
}

class SharedListModel {
  const SharedListModel({
    required this.id,
    required this.title,
    required this.kind,
    required this.items,
  });

  final String id;
  final String title;
  final String kind;
  final List<SharedListEntry> items;

  factory SharedListModel.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(SharedListEntry.fromJson)
        .toList();
    return SharedListModel(
      id: json['id'] as String,
      title: json['title'] as String,
      kind: json['kind'] as String,
      items: items,
    );
  }
}

class SharedListEntry {
  const SharedListEntry({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  factory SharedListEntry.fromJson(Map<String, dynamic> json) {
    return SharedListEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['completedAt'] != null,
    );
  }
}

class PlaceItem {
  const PlaceItem({
    required this.id,
    required this.title,
  });

  final String id;
  final String title;

  factory PlaceItem.fromJson(Map<String, dynamic> json) {
    return PlaceItem(id: json['id'] as String, title: json['title'] as String);
  }
}

class AlbumModel {
  const AlbumModel({
    required this.id,
    required this.title,
    required this.itemCount,
  });

  final String id;
  final String title;
  final int itemCount;

  factory AlbumModel.fromJson(Map<String, dynamic> json) {
    return AlbumModel(
      id: json['id'] as String,
      title: json['title'] as String,
      itemCount: (json['items'] as List<dynamic>? ?? []).length,
    );
  }
}

class RoomModel {
  const RoomModel({
    required this.id,
    required this.items,
  });

  final String id;
  final List<RoomItem> items;

  factory RoomModel.fromMusicJson(Map<String, dynamic> json) {
    final items = (json['queueItems'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(RoomItem.fromJson)
        .toList();
    return RoomModel(id: json['id'] as String, items: items);
  }

  factory RoomModel.fromWatchJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(RoomItem.fromJson)
        .toList();
    return RoomModel(id: json['id'] as String, items: items);
  }
}

class RoomItem {
  const RoomItem({
    required this.id,
    required this.title,
  });

  final String id;
  final String title;

  factory RoomItem.fromJson(Map<String, dynamic> json) {
    return RoomItem(id: json['id'] as String, title: json['title'] as String);
  }
}
