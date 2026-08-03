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
  Future<void> requestEmailVerification();
  Future<void> confirmEmailVerification(String code);
  Future<void> updateSettings({String? worldName, String? themeColor});
  Future<SpaceSummary> summary();
  Future<RelationshipSummaryModel> relationshipSummary({
    String period,
    DateTime? referenceDate,
  });
  Future<List<SpacePost>> posts();
  Future<SpacePost> createPost({
    String? title,
    required String body,
    List<String> assetIds,
  });
  Future<SpacePost> reactToPost({required String postId, String value});
  Future<SpacePost> commentOnPost({
    required String postId,
    required String body,
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
  Future<ChatMessage> sendMessage(String body, {List<String> assetIds});
  Future<ChatMessage> editMessage({
    required String messageId,
    required String body,
  });
  Future<void> deleteMessage(String messageId);
  Future<ChatMessage> reactToMessage({required String messageId, String value});
  Future<ChatMessage> pinMessage({
    required String messageId,
    required bool pinned,
  });
  Future<List<ScheduledMessageModel>> scheduledMessages();
  Future<void> scheduleMessage({
    required String body,
    required DateTime sendAt,
  });
  Future<void> readAllMessages();
  Future<List<CalendarItem>> calendarEvents();
  Future<CalendarItem> createCalendarEvent({
    required String title,
    required DateTime startsAt,
  });
  Future<List<OccasionItem>> occasions();
  Future<void> createOccasion({required String title, required DateTime date});
  Future<List<NotificationItem>> notifications();
  Future<void> readAllNotifications();
  Future<List<NotificationPreferenceModel>> notificationPreferences();
  Future<NotificationPreferenceModel> updateNotificationPreference({
    required String type,
    required bool enabled,
    String? quietFrom,
    String? quietTo,
  });
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
  Future<List<GameSessionModel>> games();
  Future<GameSessionModel> createGame({String gameType});
  Future<GameSessionModel> playGameMove({
    required String gameId,
    required int position,
  });
  Future<GameSessionModel> answerPromptGame({
    required String gameId,
    required String answer,
  });
  Future<GameSessionModel> skipPromptGame({required String gameId});
  Future<List<PlaceItem>> places();
  Future<PlaceItem> createPlace(
    String title, {
    double? latitude,
    double? longitude,
  });
  Future<void> recordPlaceVisit(String placeId, {DateTime? visitedAt});
  Future<List<AlbumModel>> albums();
  Future<void> createAlbum(String title);
  Future<void> addAlbumItem({
    required String albumId,
    required String assetId,
    String? caption,
  });
  Future<RoomModel> musicRoom();
  Future<void> addMusicItem(String title, {String? sourceUrl});
  Future<RoomModel> updateMusicPlayback({
    required String eventType,
    int? positionMs,
  });
  Future<RoomModel> watchRoom();
  Future<void> addWatchItem(String title, {String? sourceUrl});
  Future<RoomModel> updateWatchPlayback({
    required String eventType,
    int? positionMs,
  });
  Future<TreeDayModel> todayTree();
  Future<void> createTreeLeaf({String? title, required String body});
  Future<void> addTreeLeafContribution({
    required String leafId,
    required String body,
  });
  Future<List<TimeCapsuleItem>> timeCapsules();
  Future<void> createTimeCapsule({
    required String title,
    String? body,
    required DateTime opensAt,
  });
  Future<Map<String, dynamic>> exportAccount();
  Future<void> report({required String reason, String? details});
  Future<List<BlockedUserModel>> blockedUsers();
  Future<void> blockPartner({String? reason});
  Future<void> unblockUser(String blockedUserId);
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
  Future<void> requestEmailVerification() async {
    await _api.postJson('/me/email-verification/request', {});
  }

  @override
  Future<void> confirmEmailVerification(String code) async {
    await _api.postJson('/me/email-verification/confirm', {
      'code': code.trim(),
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
  Future<RelationshipSummaryModel> relationshipSummary({
    String period = 'month',
    DateTime? referenceDate,
  }) async {
    final params = <String>[
      'period=$period',
      if (referenceDate != null)
        'referenceDate=${Uri.encodeComponent(referenceDate.toUtc().toIso8601String())}',
    ].join('&');
    final json = await _api.getJson('/relationship-summary?$params');
    return RelationshipSummaryModel.fromJson(json);
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
  Future<SpacePost> reactToPost({
    required String postId,
    String value = 'heart',
  }) async {
    final json = await _api.postJson('/posts/$postId/reactions', {
      'value': value,
    });
    return SpacePost.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<SpacePost> commentOnPost({
    required String postId,
    required String body,
  }) async {
    final json = await _api.postJson('/posts/$postId/comments', {
      'body': body.trim(),
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
  Future<ChatMessage> sendMessage(
    String body, {
    List<String> assetIds = const [],
  }) async {
    final trimmed = body.trim();
    final json = await _api.postJson('/messages', {
      'clientMessageId': 'm-${DateTime.now().microsecondsSinceEpoch}',
      if (trimmed.isNotEmpty) 'body': trimmed,
      if (assetIds.isNotEmpty) 'assetIds': assetIds,
    });
    return ChatMessage.fromJson(json['message'] as Map<String, dynamic>);
  }

  @override
  Future<ChatMessage> editMessage({
    required String messageId,
    required String body,
  }) async {
    final json = await _api.patchJson('/messages/$messageId', {
      'body': body.trim(),
    });
    return ChatMessage.fromJson(json['message'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    await _api.deleteJson('/messages/$messageId');
  }

  @override
  Future<ChatMessage> reactToMessage({
    required String messageId,
    String value = 'heart',
  }) async {
    final json = await _api.postJson('/messages/$messageId/reactions', {
      'value': value,
    });
    return ChatMessage.fromJson(json['message'] as Map<String, dynamic>);
  }

  @override
  Future<ChatMessage> pinMessage({
    required String messageId,
    required bool pinned,
  }) async {
    final json = await _api.postJson('/messages/$messageId/pin', {
      'pinned': pinned,
    });
    return ChatMessage.fromJson(json['message'] as Map<String, dynamic>);
  }

  @override
  Future<List<ScheduledMessageModel>> scheduledMessages() async {
    final json = await _api.getJson('/messages/scheduled');
    return _items(json).map(ScheduledMessageModel.fromJson).toList();
  }

  @override
  Future<void> scheduleMessage({
    required String body,
    required DateTime sendAt,
  }) async {
    await _api.postJson('/messages/scheduled', {
      'body': body.trim(),
      'sendAt': sendAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> readAllMessages() async {
    await _api.postJson('/messages/read-all', {});
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
  Future<List<NotificationPreferenceModel>> notificationPreferences() async {
    final json = await _api.getJson('/notifications/preferences');
    return _items(json).map(NotificationPreferenceModel.fromJson).toList();
  }

  @override
  Future<NotificationPreferenceModel> updateNotificationPreference({
    required String type,
    required bool enabled,
    String? quietFrom,
    String? quietTo,
  }) async {
    final json = await _api.patchJson('/notifications/preferences', {
      'type': type,
      'enabled': enabled,
      'quietFrom': quietFrom,
      'quietTo': quietTo,
    });
    return NotificationPreferenceModel.fromJson(
      json['preference'] as Map<String, dynamic>,
    );
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
  Future<List<GameSessionModel>> games() async {
    final json = await _api.getJson('/games');
    return _items(json).map(GameSessionModel.fromJson).toList();
  }

  @override
  Future<GameSessionModel> createGame({String gameType = 'tic_tac_toe'}) async {
    final json = await _api.postJson('/games', {'gameType': gameType});
    return GameSessionModel.fromJson(json['game'] as Map<String, dynamic>);
  }

  @override
  Future<GameSessionModel> playGameMove({
    required String gameId,
    required int position,
  }) async {
    final json = await _api.postJson('/games/$gameId/moves', {
      'position': position,
    });
    return GameSessionModel.fromJson(json['game'] as Map<String, dynamic>);
  }

  @override
  Future<GameSessionModel> answerPromptGame({
    required String gameId,
    required String answer,
  }) async {
    final json = await _api.postJson('/games/$gameId/answer', {
      'answer': answer.trim(),
    });
    return GameSessionModel.fromJson(json['game'] as Map<String, dynamic>);
  }

  @override
  Future<GameSessionModel> skipPromptGame({required String gameId}) async {
    final json = await _api.postJson('/games/$gameId/skip', {});
    return GameSessionModel.fromJson(json['game'] as Map<String, dynamic>);
  }

  @override
  Future<List<PlaceItem>> places() async {
    final json = await _api.getJson('/places');
    return _items(json).map(PlaceItem.fromJson).toList();
  }

  @override
  Future<PlaceItem> createPlace(
    String title, {
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{'title': title.trim()};
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    final json = await _api.postJson('/places', body);
    return PlaceItem.fromJson(json['place'] as Map<String, dynamic>);
  }

  @override
  Future<void> recordPlaceVisit(String placeId, {DateTime? visitedAt}) async {
    await _api.postJson('/places/$placeId/visits', {
      if (visitedAt != null) 'visitedAt': visitedAt.toUtc().toIso8601String(),
    });
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
  Future<void> addAlbumItem({
    required String albumId,
    required String assetId,
    String? caption,
  }) async {
    await _api.postJson('/albums/$albumId/items', {
      'assetId': assetId,
      if (caption != null && caption.trim().isNotEmpty)
        'caption': caption.trim(),
    });
  }

  @override
  Future<RoomModel> musicRoom() async {
    final json = await _api.getJson('/music-room');
    return RoomModel.fromMusicJson(json['room'] as Map<String, dynamic>);
  }

  @override
  Future<void> addMusicItem(String title, {String? sourceUrl}) async {
    await _api.postJson('/music-room/queue', {
      'title': title.trim(),
      if (sourceUrl != null && sourceUrl.trim().isNotEmpty)
        'sourceUrl': sourceUrl.trim(),
    });
  }

  @override
  Future<RoomModel> updateMusicPlayback({
    required String eventType,
    int? positionMs,
  }) async {
    final body = <String, dynamic>{'eventType': eventType};
    if (positionMs != null) body['positionMs'] = positionMs;
    final json = await _api.postJson('/music-room/playback', body);
    return RoomModel.fromMusicJson(json['room'] as Map<String, dynamic>);
  }

  @override
  Future<RoomModel> watchRoom() async {
    final json = await _api.getJson('/watch-room');
    return RoomModel.fromWatchJson(json['room'] as Map<String, dynamic>);
  }

  @override
  Future<void> addWatchItem(String title, {String? sourceUrl}) async {
    await _api.postJson('/watch-room/items', {
      'title': title.trim(),
      if (sourceUrl != null && sourceUrl.trim().isNotEmpty)
        'sourceUrl': sourceUrl.trim(),
    });
  }

  @override
  Future<RoomModel> updateWatchPlayback({
    required String eventType,
    int? positionMs,
  }) async {
    final body = <String, dynamic>{'eventType': eventType};
    if (positionMs != null) body['positionMs'] = positionMs;
    final json = await _api.postJson('/watch-room/playback', body);
    return RoomModel.fromWatchJson(json['room'] as Map<String, dynamic>);
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
  Future<void> addTreeLeafContribution({
    required String leafId,
    required String body,
  }) async {
    await _api.postJson('/tree/leaves/$leafId/contributions', {
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
  Future<List<BlockedUserModel>> blockedUsers() async {
    final json = await _api.getJson('/blocks');
    return _items(json).map(BlockedUserModel.fromJson).toList();
  }

  @override
  Future<void> blockPartner({String? reason}) async {
    await _api.postJson('/blocks/partner', {
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  @override
  Future<void> unblockUser(String blockedUserId) async {
    await _api.deleteJson('/blocks/$blockedUserId');
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

class BlockedUserModel {
  const BlockedUserModel({
    required this.id,
    required this.blockedId,
    required this.createdAt,
    this.reason,
    this.user,
  });

  final String id;
  final String blockedId;
  final DateTime createdAt;
  final String? reason;
  final BlockedUserProfile? user;

  factory BlockedUserModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return BlockedUserModel(
      id: json['id'] as String,
      blockedId: json['blockedId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      reason: json['reason'] as String?,
      user: user is Map<String, dynamic>
          ? BlockedUserProfile.fromJson(user)
          : null,
    );
  }
}

class BlockedUserProfile {
  const BlockedUserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory BlockedUserProfile.fromJson(Map<String, dynamic> json) {
    return BlockedUserProfile(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'مستخدم',
      avatarUrl: json['avatarUrl'] as String?,
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

class RelationshipSummaryModel {
  const RelationshipSummaryModel({
    required this.period,
    required this.title,
    required this.start,
    required this.end,
    required this.counts,
    required this.topMoods,
    required this.highlights,
    required this.timeline,
    this.importantOccasion,
  });

  final String period;
  final String title;
  final DateTime start;
  final DateTime end;
  final RelationshipSummaryCounts counts;
  final List<RelationshipMoodCount> topMoods;
  final List<RelationshipHighlight> highlights;
  final RelationshipTimelineItem? importantOccasion;
  final List<RelationshipTimelineItem> timeline;

  factory RelationshipSummaryModel.fromJson(Map<String, dynamic> json) {
    return RelationshipSummaryModel(
      period: json['period'] as String? ?? 'month',
      title: json['title'] as String? ?? 'ملخص العلاقة',
      start: DateTime.parse(json['start'] as String).toLocal(),
      end: DateTime.parse(json['end'] as String).toLocal(),
      counts: RelationshipSummaryCounts.fromJson(
        json['counts'] as Map<String, dynamic>? ?? const {},
      ),
      topMoods: (json['topMoods'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(RelationshipMoodCount.fromJson)
          .toList(),
      highlights: (json['highlights'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(RelationshipHighlight.fromJson)
          .toList(),
      importantOccasion: json['importantOccasion'] is Map<String, dynamic>
          ? RelationshipTimelineItem.fromJson(
              json['importantOccasion'] as Map<String, dynamic>,
            )
          : null,
      timeline: (json['timeline'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(RelationshipTimelineItem.fromJson)
          .toList(),
    );
  }
}

class RelationshipSummaryCounts {
  const RelationshipSummaryCounts({
    required this.messages,
    required this.photos,
    required this.videos,
    required this.treeLeaves,
    required this.songs,
    required this.watchSessions,
    required this.places,
    required this.completedGoals,
  });

  final int messages;
  final int photos;
  final int videos;
  final int treeLeaves;
  final int songs;
  final int watchSessions;
  final int places;
  final int completedGoals;

  factory RelationshipSummaryCounts.fromJson(Map<String, dynamic> json) {
    int value(String key) => int.parse((json[key] ?? 0).toString());
    return RelationshipSummaryCounts(
      messages: value('messages'),
      photos: value('photos'),
      videos: value('videos'),
      treeLeaves: value('treeLeaves'),
      songs: value('songs'),
      watchSessions: value('watchSessions'),
      places: value('places'),
      completedGoals: value('completedGoals'),
    );
  }
}

class RelationshipMoodCount {
  const RelationshipMoodCount({
    required this.kind,
    required this.count,
    this.emoji,
  });

  final String kind;
  final int count;
  final String? emoji;

  factory RelationshipMoodCount.fromJson(Map<String, dynamic> json) {
    return RelationshipMoodCount(
      kind: json['kind'] as String? ?? '',
      emoji: json['emoji'] as String?,
      count: int.parse((json['count'] ?? 0).toString()),
    );
  }
}

class RelationshipHighlight {
  const RelationshipHighlight({
    required this.id,
    required this.createdAt,
    required this.reactions,
    required this.comments,
    this.title,
    this.body,
  });

  final String id;
  final String? title;
  final String? body;
  final DateTime createdAt;
  final int reactions;
  final int comments;

  factory RelationshipHighlight.fromJson(Map<String, dynamic> json) {
    return RelationshipHighlight(
      id: json['id'] as String,
      title: json['title'] as String?,
      body: json['body'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      reactions: int.parse((json['reactions'] ?? 0).toString()),
      comments: int.parse((json['comments'] ?? 0).toString()),
    );
  }
}

class RelationshipTimelineItem {
  const RelationshipTimelineItem({
    required this.type,
    required this.id,
    required this.title,
    required this.occurredAt,
  });

  final String type;
  final String id;
  final String title;
  final DateTime occurredAt;

  factory RelationshipTimelineItem.fromJson(Map<String, dynamic> json) {
    return RelationshipTimelineItem(
      type: json['type'] as String? ?? '',
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      occurredAt: DateTime.parse(
        (json['occurredAt'] ?? json['date']) as String,
      ).toLocal(),
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
    required this.reactionCount,
    required this.commentCount,
    this.title,
    this.myReaction,
  });

  final String id;
  final String? title;
  final String body;
  final DateTime createdAt;
  final List<String> assetIds;
  final int reactionCount;
  final int commentCount;
  final String? myReaction;

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
      reactionCount: int.parse((json['reactionCount'] ?? 0).toString()),
      commentCount: int.parse((json['commentCount'] ?? 0).toString()),
      myReaction: json['myReaction'] as String?,
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
    this.assetIds = const [],
    this.editedAt,
    this.senderUsername,
    this.deliveredAt,
    this.readAt,
    this.reactionCount = 0,
    this.myReaction,
    this.pinCount = 0,
    this.pinnedByMe = false,
    this.pending = false,
  });

  final String id;
  final String body;
  final DateTime serverTimestamp;
  final List<String> assetIds;
  final DateTime? editedAt;
  final String? senderUsername;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final int reactionCount;
  final String? myReaction;
  final int pinCount;
  final bool pinnedByMe;
  final bool pending;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;
    final assetIds = (json['assetIds'] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .toList();
    return ChatMessage(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      serverTimestamp: DateTime.parse(json['serverTimestamp'] as String),
      assetIds: assetIds,
      editedAt: _optionalDate(json['editedAt']),
      senderUsername: sender?['username'] as String?,
      deliveredAt: _optionalDate(json['deliveredAt']),
      readAt: _optionalDate(json['readAt']),
      reactionCount: int.parse((json['reactionCount'] ?? 0).toString()),
      myReaction: json['myReaction'] as String?,
      pinCount: int.parse((json['pinCount'] ?? 0).toString()),
      pinnedByMe: json['pinnedByMe'] as bool? ?? false,
    );
  }
}

class ScheduledMessageModel {
  const ScheduledMessageModel({
    required this.id,
    required this.body,
    required this.sendAt,
    this.sentAt,
  });

  final String id;
  final String body;
  final DateTime sendAt;
  final DateTime? sentAt;

  factory ScheduledMessageModel.fromJson(Map<String, dynamic> json) {
    return ScheduledMessageModel(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      sendAt: DateTime.parse(json['sendAt'] as String).toLocal(),
      sentAt: _optionalDate(json['sentAt'])?.toLocal(),
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

class NotificationPreferenceModel {
  const NotificationPreferenceModel({
    required this.type,
    required this.enabled,
    this.quietFrom,
    this.quietTo,
  });

  final String type;
  final bool enabled;
  final String? quietFrom;
  final String? quietTo;

  factory NotificationPreferenceModel.fromJson(Map<String, dynamic> json) {
    return NotificationPreferenceModel(
      type: json['type'] as String,
      enabled: json['enabled'] as bool? ?? true,
      quietFrom: json['quietFrom'] as String?,
      quietTo: json['quietTo'] as String?,
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
    this.emailVerifiedAt,
    this.bio,
  });

  final String id;
  final String username;
  final String? email;
  final DateTime? emailVerifiedAt;
  final String displayName;
  final String? bio;
  final bool searchable;
  final bool canReceiveRequests;
  bool get emailVerified => emailVerifiedAt != null;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      emailVerifiedAt: _optionalDate(json['emailVerifiedAt']),
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

class GameSessionModel {
  const GameSessionModel({
    required this.id,
    required this.gameType,
    required this.status,
    required this.board,
    this.prompt,
    this.options = const [],
    this.players = const [],
    this.answers = const {},
    this.skipped = const [],
    this.currentTurnUserId,
    this.winnerUserId,
  });

  final String id;
  final String gameType;
  final String status;
  final List<String?> board;
  final String? prompt;
  final List<String> options;
  final List<String> players;
  final Map<String, String> answers;
  final List<String> skipped;
  final String? currentTurnUserId;
  final String? winnerUserId;

  bool get finished => status == 'finished';
  bool get isPrompt => gameType == 'daily_prompt';

  factory GameSessionModel.fromJson(Map<String, dynamic> json) {
    final board = (json['board'] as List<dynamic>? ?? [])
        .map((item) => item?.toString())
        .toList();
    while (board.length < 9) {
      board.add(null);
    }
    final answers = (json['answers'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value.toString()),
    );
    return GameSessionModel(
      id: json['id'] as String,
      gameType: json['gameType'] as String? ?? 'tic_tac_toe',
      status: json['status'] as String? ?? 'active',
      board: board.take(9).toList(),
      prompt: json['prompt'] as String?,
      options: (json['options'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      players: (json['players'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      answers: answers,
      skipped: (json['skipped'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      currentTurnUserId: json['currentTurnUserId'] as String?,
      winnerUserId: json['winnerUserId'] as String?,
    );
  }
}

class PlaceItem {
  const PlaceItem({
    required this.id,
    required this.title,
    required this.visitCount,
    this.latitude,
    this.longitude,
    this.lastVisitedAt,
  });

  final String id;
  final String title;
  final double? latitude;
  final double? longitude;
  final int visitCount;
  final DateTime? lastVisitedAt;

  factory PlaceItem.fromJson(Map<String, dynamic> json) {
    return PlaceItem(
      id: json['id'] as String,
      title: json['title'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      visitCount: int.parse((json['visitCount'] ?? 0).toString()),
      lastVisitedAt: _optionalDate(json['lastVisitedAt']),
    );
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
    required this.status,
    required this.items,
    this.latestEvent,
  });

  final String id;
  final String status;
  final List<RoomItem> items;
  final RoomPlaybackEvent? latestEvent;

  factory RoomModel.fromMusicJson(Map<String, dynamic> json) {
    final items = (json['queueItems'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(RoomItem.fromJson)
        .toList();
    return RoomModel(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'idle',
      items: items,
      latestEvent: _latestPlaybackEvent(json),
    );
  }

  factory RoomModel.fromWatchJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(RoomItem.fromJson)
        .toList();
    return RoomModel(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'idle',
      items: items,
      latestEvent: _latestPlaybackEvent(json),
    );
  }

  static RoomPlaybackEvent? _latestPlaybackEvent(Map<String, dynamic> json) {
    final events = (json['playbackEvents'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (events.isEmpty) return null;
    return RoomPlaybackEvent.fromJson(events.first);
  }
}

class RoomItem {
  const RoomItem({
    required this.id,
    required this.title,
    required this.source,
    this.sourceUrl,
  });

  final String id;
  final String title;
  final String source;
  final String? sourceUrl;

  factory RoomItem.fromJson(Map<String, dynamic> json) {
    return RoomItem(
      id: json['id'] as String,
      title: json['title'] as String,
      source: json['source'] as String? ?? 'manual',
      sourceUrl: json['sourceUrl'] as String?,
    );
  }
}

class RoomPlaybackEvent {
  const RoomPlaybackEvent({
    required this.id,
    required this.eventType,
    this.positionMs,
    this.createdAt,
  });

  final String id;
  final String eventType;
  final int? positionMs;
  final DateTime? createdAt;

  factory RoomPlaybackEvent.fromJson(Map<String, dynamic> json) {
    return RoomPlaybackEvent(
      id: json['id'] as String,
      eventType: json['eventType'] as String? ?? 'play',
      positionMs: json['positionMs'] as int?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
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
  const TreeLeafItem({
    required this.id,
    required this.body,
    required this.contributions,
    this.title,
  });

  final String id;
  final String? title;
  final String body;
  final List<TreeLeafContributionItem> contributions;

  factory TreeLeafItem.fromJson(Map<String, dynamic> json) {
    final contributions = (json['contributions'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(TreeLeafContributionItem.fromJson)
        .toList();
    return TreeLeafItem(
      id: json['id'] as String,
      title: json['title'] as String?,
      body: json['body'] as String? ?? '',
      contributions: contributions,
    );
  }
}

class TreeLeafContributionItem {
  const TreeLeafContributionItem({
    required this.id,
    required this.userId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String body;
  final DateTime createdAt;

  factory TreeLeafContributionItem.fromJson(Map<String, dynamic> json) {
    return TreeLeafContributionItem(
      id: json['id'] as String,
      userId: json['userId'] as String,
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
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

DateTime? _optionalDate(Object? value) {
  if (value == null) return null;
  return DateTime.parse(value as String);
}
