import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
  Future<SpacePost> createPost({
    String? title,
    required String body,
    List<String> assetIds,
  });
  Future<MediaAssetModel> uploadMedia({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  });
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
  Future<List<OccasionItem>> occasions();
  Future<void> createOccasion({required String title, required DateTime date});
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
  Future<void> addSharedListItem({
    required String listId,
    required String title,
  });
  Future<void> toggleSharedListItem(String id);
  Future<List<PlaceItem>> places();
  Future<void> createPlace(String title);
  Future<List<AlbumModel>> albums();
  Future<void> createAlbum(String title);
  Future<RoomModel> musicRoom();
  Future<void> addMusicItem(String title);
  Future<RoomModel> watchRoom();
  Future<void> addWatchItem(String title);
  Future<TreeDayModel> todayTree();
  Future<void> createTreeLeaf({String? title, required String body});
  Future<List<TimeCapsuleItem>> timeCapsules();
  Future<void> createTimeCapsule({
    required String title,
    String? body,
    required DateTime opensAt,
  });
  Future<Map<String, dynamic>> exportAccount();
  Future<void> report({required String reason, String? details});
  Future<void> deleteAccount();
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
  Future<SpacePost> createPost({
    String? title,
    required String body,
    List<String> assetIds = const [],
  }) async {
    final json = await _api.postJson('/posts', {
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      'body': body.trim(),
      if (assetIds.isNotEmpty) 'assetIds': assetIds,
    });
    return SpacePost.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<MediaAssetModel> uploadMedia({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final presignJson = await _api.postJson('/uploads/presign', {
      'fileName': fileName,
      'mimeType': mimeType,
      'sizeBytes': bytes.length,
    });

    final upload = UploadTicket.fromJson(presignJson);
    final putResponse = await http.put(
      Uri.parse(upload.uploadUrl),
      headers: upload.headers,
      body: bytes,
    );
    if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
      throw ApiException(
        code: 'upload_failed',
        message: 'تعذر رفع الملف. حاول مرة أخرى.',
      );
    }

    final completed = await _api.postJson(
      '/uploads/${upload.uploadId}/complete',
      {},
    );
    return MediaAssetModel.fromJson(completed['asset'] as Map<String, dynamic>);
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
  Future<List<OccasionItem>> occasions() async {
    final json = await _api.getJson('/occasions');
    return _items(json).map(OccasionItem.fromJson).toList();
  }

  @override
  Future<void> createOccasion({
    required String title,
    required DateTime date,
  }) async {
    await _api.postJson('/occasions', {
      'title': title.trim(),
      'date': date.toUtc().toIso8601String(),
    });
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
  Future<void> createGoal({
    required String title,
    List<String> steps = const [],
  }) async {
    await _api.postJson('/goals', {
      'title': title.trim(),
      'steps': steps
          .map((step) => step.trim())
          .where((step) => step.isNotEmpty)
          .toList(),
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
  Future<void> createSharedList({
    required String title,
    required String kind,
  }) async {
    await _api.postJson('/shared-lists', {
      'title': title.trim(),
      'kind': kind.trim().isEmpty ? 'general' : kind.trim(),
    });
  }

  @override
  Future<void> addSharedListItem({
    required String listId,
    required String title,
  }) async {
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

  @override
  Future<TreeDayModel> todayTree() async {
    final json = await _api.getJson('/tree/today');
    return TreeDayModel.fromJson(json['day'] as Map<String, dynamic>);
  }

  @override
  Future<void> createTreeLeaf({String? title, required String body}) async {
    await _api.postJson('/tree/leaves', {
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      'body': body.trim(),
    });
  }

  @override
  Future<List<TimeCapsuleItem>> timeCapsules() async {
    final json = await _api.getJson('/time-capsules');
    return _items(json).map(TimeCapsuleItem.fromJson).toList();
  }

  @override
  Future<void> createTimeCapsule({
    required String title,
    String? body,
    required DateTime opensAt,
  }) async {
    await _api.postJson('/time-capsules', {
      'title': title.trim(),
      if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      'opensAt': opensAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<Map<String, dynamic>> exportAccount() async {
    return _api.getJson('/account/export');
  }

  @override
  Future<void> report({required String reason, String? details}) async {
    await _api.postJson('/reports', {
      'reason': reason.trim(),
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }

  @override
  Future<void> deleteAccount() async {
    await _api.deleteJson('/me');
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
    required this.assetIds,
    this.title,
  });

  final String id;
  final String? title;
  final String body;
  final DateTime createdAt;
  final List<String> assetIds;

  factory SpacePost.fromJson(Map<String, dynamic> json) {
    final assetIds = (json['assetIds'] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .toList();
    return SpacePost(
      id: json['id'] as String,
      title: json['title'] as String?,
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      assetIds: assetIds,
    );
  }
}

class UploadTicket {
  const UploadTicket({
    required this.uploadId,
    required this.uploadUrl,
    required this.headers,
  });

  final String uploadId;
  final String uploadUrl;
  final Map<String, String> headers;

  factory UploadTicket.fromJson(Map<String, dynamic> json) {
    final upload = json['upload'] as Map<String, dynamic>;
    final headers = (json['headers'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value.toString()),
    );
    return UploadTicket(
      uploadId: upload['id'] as String,
      uploadUrl: json['uploadUrl'] as String,
      headers: headers,
    );
  }
}

class MediaAssetModel {
  const MediaAssetModel({
    required this.id,
    required this.objectKey,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String id;
  final String objectKey;
  final String mimeType;
  final int sizeBytes;

  factory MediaAssetModel.fromJson(Map<String, dynamic> json) {
    return MediaAssetModel(
      id: json['id'] as String,
      objectKey: json['objectKey'] as String,
      mimeType: json['mimeType'] as String,
      sizeBytes: int.parse(json['sizeBytes'].toString()),
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
  const NotificationItem({required this.id, required this.title, this.body});

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
  const PlaceItem({required this.id, required this.title});

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
  const RoomModel({required this.id, required this.items});

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
  const RoomItem({required this.id, required this.title});

  final String id;
  final String title;

  factory RoomItem.fromJson(Map<String, dynamic> json) {
    return RoomItem(id: json['id'] as String, title: json['title'] as String);
  }
}

class OccasionItem {
  const OccasionItem({
    required this.id,
    required this.title,
    required this.date,
  });

  final String id;
  final String title;
  final DateTime date;

  factory OccasionItem.fromJson(Map<String, dynamic> json) {
    return OccasionItem(
      id: json['id'] as String,
      title: json['title'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }
}

class TreeDayModel {
  const TreeDayModel({
    required this.id,
    required this.date,
    required this.leaves,
  });

  final String id;
  final DateTime date;
  final List<TreeLeafItem> leaves;

  factory TreeDayModel.fromJson(Map<String, dynamic> json) {
    final leaves = (json['leaves'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(TreeLeafItem.fromJson)
        .toList();
    return TreeDayModel(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      leaves: leaves,
    );
  }
}

class TreeLeafItem {
  const TreeLeafItem({required this.id, required this.body, this.title});

  final String id;
  final String? title;
  final String body;

  factory TreeLeafItem.fromJson(Map<String, dynamic> json) {
    return TreeLeafItem(
      id: json['id'] as String,
      title: json['title'] as String?,
      body: json['body'] as String? ?? '',
    );
  }
}

class TimeCapsuleItem {
  const TimeCapsuleItem({
    required this.id,
    required this.title,
    required this.opensAt,
    required this.opened,
    this.body,
  });

  final String id;
  final String title;
  final String? body;
  final DateTime opensAt;
  final bool opened;

  factory TimeCapsuleItem.fromJson(Map<String, dynamic> json) {
    return TimeCapsuleItem(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      opensAt: DateTime.parse(json['opensAt'] as String),
      opened: json['openedAt'] != null,
    );
  }
}
