import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smiley/core/offline_outbox.dart';
import 'package:smiley/core/push_service.dart';
import 'package:smiley/core/secure_stores.dart';
import 'package:smiley/core/realtime_client.dart';
import 'package:smiley/features/auth/auth_models.dart';
import 'package:smiley/features/auth/auth_repository.dart';
import 'package:smiley/features/gate/gate_validator.dart';
import 'package:smiley/features/partnerships/partnership_repository.dart';
import 'package:smiley/features/space/space_repository.dart';
import 'package:smiley/main.dart';

void main() {
  test('date gate accepts only the configured date', () {
    const validator = GateValidator();

    expect(validator.accepts(DateTime(2026, 8, 2)), isFalse);
    expect(validator.accepts(DateTime(2026, 8, 3)), isTrue);
  });

  testWidgets('wrong date keeps the app on the date gate', (tester) async {
    final gateStore = MemoryGateStore();

    await tester.pumpWidget(
      SmileyApp(
        gateStore: gateStore,
        tokenStore: MemoryAuthTokenStore(),
        authRepository: FakeAuthRepository(),
        partnershipRepository: FakePartnershipRepository(),
        spaceRepository: FakeSpaceRepository(),
        offlineOutbox: MemoryOfflineOutbox(),
        realtimeClient: RealtimeClient.disabled(),
        pushService: PushService(registerToken: (_, _) async {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    picker.onDateChanged(DateTime(2026, 8, 2));
    await tester.pump(const Duration(milliseconds: 250));

    expect(await gateStore.isUnlocked(), isFalse);
    expect(find.text('الدخول'), findsNothing);
  });

  testWidgets('correct date unlocks auth screen', (tester) async {
    final gateStore = MemoryGateStore();

    await tester.pumpWidget(
      SmileyApp(
        gateStore: gateStore,
        tokenStore: MemoryAuthTokenStore(),
        authRepository: FakeAuthRepository(),
        partnershipRepository: FakePartnershipRepository(),
        spaceRepository: FakeSpaceRepository(),
        offlineOutbox: MemoryOfflineOutbox(),
        realtimeClient: RealtimeClient.disabled(),
        pushService: PushService(registerToken: (_, _) async {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(DateTime(2026, 8, 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));

    expect(await gateStore.isUnlocked(), isTrue);
    expect(find.text('الدخول'), findsOneWidget);
  });
  testWidgets('tabs show distinct empty states before adding partner', (
    tester,
  ) async {
    final gateStore = MemoryGateStore()..unlocked = true;
    final tokenStore = MemoryAuthTokenStore();
    await tokenStore.saveTokens(accessToken: 'access', refreshToken: 'refresh');

    await tester.pumpWidget(
      SmileyApp(
        gateStore: gateStore,
        tokenStore: tokenStore,
        authRepository: FakeAuthRepository(),
        partnershipRepository: FakePartnershipRepository(),
        spaceRepository: FakeSpaceRepository(),
        offlineOutbox: MemoryOfflineOutbox(),
        realtimeClient: RealtimeClient.disabled(),
        pushService: PushService(registerToken: (_, _) async {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.public_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chat_outlined));
    await tester.pumpAndSettle();

    expect(find.text('المحادثة'), findsWidgets);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(find.text('إضافة شريك للمحادثة'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded).last);
    await tester.pumpAndSettle();

    expect(find.text('عالم Smiley'), findsWidgets);
    expect(find.text('بدء العالم'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();

    expect(find.text('التقويم'), findsWidgets);
    expect(find.text('إضافة شريك للتقويم'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    expect(find.text('المزيد'), findsWidgets);
  });
}

class MemoryGateStore implements GateStore {
  bool unlocked = false;

  @override
  Future<bool> isUnlocked() async => unlocked;

  @override
  Future<void> markUnlocked() async {
    unlocked = true;
  }

  @override
  Future<void> reset() async {
    unlocked = false;
  }
}

class MemoryAuthTokenStore implements AuthTokenStore {
  String? access;
  String? refresh;

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }
}

class MemoryOfflineOutbox implements OfflineOutbox {
  final List<QueuedMessage> _messages = [];
  final List<QueuedPost> _posts = [];

  @override
  Future<void> enqueueMessage(
    String body, {
    List<String> assetIds = const [],
    String? id,
  }) async {
    _messages.add(
      QueuedMessage(
        id: id ?? 'message-${_messages.length}',
        body: body,
        assetIds: assetIds,
        createdAt: DateTime(2026, 8, 3),
      ),
    );
  }

  @override
  Future<void> enqueuePost({
    required String body,
    List<String> assetIds = const [],
  }) async {
    _posts.add(
      QueuedPost(
        id: 'post-${_posts.length}',
        body: body,
        assetIds: assetIds,
        createdAt: DateTime(2026, 8, 3),
      ),
    );
  }

  @override
  Future<List<QueuedMessage>> messages() async => [..._messages];

  @override
  Future<List<QueuedPost>> posts() async => [..._posts];

  @override
  Future<void> removeMessage(String id) async {
    _messages.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> removePost(String id) async {
    _posts.removeWhere((item) => item.id == id);
  }
}

class FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    return _session();
  }

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<void> logoutAll() async {}

  @override
  Future<void> revokeSession(String id) async {}

  @override
  Future<List<LoginSessionModel>> sessions() async => [];

  @override
  Future<void> requestPasswordReset(String identifier) async {}

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String password,
  }) async {}

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    return _session();
  }

  @override
  Future<AuthSession> register(RegisterRequest request) async {
    return _session();
  }

  AuthSession _session() {
    return const AuthSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      userId: 'user-id',
      username: 'user',
      displayName: 'مستخدم',
    );
  }
}

class FakePartnershipRepository implements PartnershipRepository {
  @override
  Future<void> acceptRequest(String id) async {}

  @override
  Future<void> cancelRequest(String id) async {}

  @override
  Future<CurrentPartnership> completeOnboarding(OnboardingInput input) async {
    return CurrentPartnership(
      id: input.partnershipId,
      status: 'active',
      members: const [],
      onboardingCompleted: true,
      startedAt: input.startDate,
      worldName: input.worldName,
    );
  }

  @override
  Future<CurrentPartnership?> current() async => null;

  @override
  Future<void> leaveCurrentPartnership() async {}

  @override
  Future<void> requestPartnership(String username) async {}

  @override
  Future<List<PartnershipRequest>> requests() async => [];

  @override
  Future<void> rejectRequest(String id) async {}

  @override
  Future<List<PartnerSearchResult>> search(String username) async => [];
}

class FakeSpaceRepository implements SpaceRepository {
  @override
  Future<void> addMusicItem(String title, {String? sourceUrl}) async {}

  @override
  Future<RoomModel> updateMusicPlayback({
    required String eventType,
    int? positionMs,
    String? itemId,
    String? sourceUrl,
    String? title,
  }) async {
    return RoomModel(
      id: 'music',
      status: eventType == 'pause' ? 'paused' : 'playing',
      items: const [],
      latestEvent: RoomPlaybackEvent(
        id: 'event',
        eventType: eventType,
        positionMs: positionMs,
      ),
    );
  }

  @override
  Future<void> addSharedListItem({
    required String listId,
    required String title,
  }) async {}

  @override
  Future<void> addWatchItem(String title, {String? sourceUrl}) async {}

  @override
  Future<RoomModel> updateWatchPlayback({
    required String eventType,
    int? positionMs,
    String? itemId,
    String? sourceUrl,
    String? title,
  }) async {
    return RoomModel(
      id: 'watch',
      status: eventType == 'pause' ? 'paused' : 'playing',
      items: const [],
      latestEvent: RoomPlaybackEvent(
        id: 'event',
        eventType: eventType,
        positionMs: positionMs,
      ),
    );
  }

  @override
  Future<List<AlbumModel>> albums() async => [];

  @override
  Future<List<CalendarItem>> calendarEvents() async => [];

  @override
  Future<void> createAlbum(String title) async {}

  @override
  Future<void> addAlbumItem({
    required String albumId,
    required String assetId,
    String? caption,
  }) async {}

  @override
  Future<CalendarItem> createCalendarEvent({
    required String title,
    required DateTime startsAt,
  }) async {
    return CalendarItem(id: 'event', title: title, startsAt: startsAt);
  }

  @override
  Future<void> createOccasion({
    required String title,
    required DateTime date,
  }) async {}

  @override
  Future<void> createGoal({
    required String title,
    List<String> steps = const [],
  }) async {}

  @override
  Future<SpaceMood> createMood({
    required String kind,
    String? emoji,
    String? note,
  }) async {
    return SpaceMood(id: 'mood', kind: kind, emoji: emoji, note: note);
  }

  @override
  Future<SpacePost> createPost({
    String? title,
    required String body,
    List<String> assetIds = const [],
  }) async {
    return SpacePost(
      id: 'post',
      title: title,
      body: body,
      createdAt: DateTime(2026, 8, 3),
      assetIds: assetIds,
      reactionCount: 0,
      commentCount: 0,
    );
  }

  @override
  Future<SpacePost> updatePost({
    required String postId,
    required String body,
  }) async {
    return SpacePost(
      id: postId,
      body: body,
      createdAt: DateTime(2026, 8, 3),
      assetIds: const [],
      reactionCount: 0,
      commentCount: 0,
    );
  }

  @override
  Future<void> deletePost(String postId) async {}

  @override
  Future<SpacePost> reactToPost({
    required String postId,
    String value = 'heart',
  }) async {
    return SpacePost(
      id: postId,
      body: 'post',
      createdAt: DateTime(2026, 8, 3),
      assetIds: const [],
      reactionCount: 1,
      commentCount: 0,
      myReaction: value,
    );
  }

  @override
  Future<SpacePost> commentOnPost({
    required String postId,
    required String body,
  }) async {
    return SpacePost(
      id: postId,
      body: 'post',
      createdAt: DateTime(2026, 8, 3),
      assetIds: const [],
      reactionCount: 0,
      commentCount: 1,
    );
  }

  @override
  Future<PlaceItem> createPlace(
    String title, {
    double? latitude,
    double? longitude,
  }) async {
    return PlaceItem(
      id: 'place',
      title: title,
      latitude: latitude,
      longitude: longitude,
      visitCount: 0,
    );
  }

  @override
  Future<void> recordPlaceVisit(String placeId, {DateTime? visitedAt}) async {}

  @override
  Future<void> createSharedList({
    required String title,
    required String kind,
  }) async {}

  @override
  Future<void> createWish(String title) async {}

  @override
  Future<void> requestEmailVerification() async {}

  @override
  Future<void> confirmEmailVerification(String code) async {}

  @override
  Future<void> requestPhoneVerification() async {}

  @override
  Future<void> confirmPhoneVerification(String code) async {}

  @override
  Future<void> createTimeCapsule({
    required String title,
    String? body,
    required DateTime opensAt,
  }) async {}

  @override
  Future<void> createTreeLeaf({String? title, required String body}) async {}

  @override
  Future<void> addTreeLeafContribution({
    required String leafId,
    required String body,
  }) async {}

  @override
  Future<void> deleteAccount(String password) async {}

  @override
  Future<Map<String, dynamic>> exportAccount() async => {};

  @override
  Future<StorageUsageSummary> storageUsage() async {
    return const StorageUsageSummary();
  }

  @override
  Future<List<GoalItem>> goals() async => [];

  @override
  Future<List<GameSessionModel>> games() async => [];

  @override
  Future<GameSessionModel> createGame({String gameType = 'tic_tac_toe'}) async {
    return GameSessionModel(
      id: 'game',
      gameType: gameType,
      status: 'active',
      board: const [null, null, null, null, null, null, null, null, null],
      prompt: gameType == 'daily_prompt' ? 'question' : null,
      players: const ['user', 'partner'],
    );
  }

  @override
  Future<GameSessionModel> answerPromptGame({
    required String gameId,
    required String answer,
  }) async {
    return GameSessionModel(
      id: gameId,
      gameType: 'daily_prompt',
      status: 'active',
      board: const [null, null, null, null, null, null, null, null, null],
      prompt: 'question',
      players: const ['user', 'partner'],
      answers: {'user': answer},
    );
  }

  @override
  Future<GameSessionModel> skipPromptGame({required String gameId}) async {
    return GameSessionModel(
      id: gameId,
      gameType: 'daily_prompt',
      status: 'active',
      board: const [null, null, null, null, null, null, null, null, null],
      prompt: 'question',
      players: const ['user', 'partner'],
      skipped: const ['user'],
    );
  }

  @override
  Future<GameSessionModel> playGameMove({
    required String gameId,
    required int position,
  }) async {
    return GameSessionModel(
      id: gameId,
      gameType: 'tic_tac_toe',
      status: 'active',
      board: List<String?>.filled(9, null)..[position] = 'x',
    );
  }

  @override
  Future<UserProfile> me() async {
    return const UserProfile(
      id: 'user-id',
      username: 'user',
      displayName: 'مستخدم',
      searchable: true,
      canReceiveRequests: true,
    );
  }

  @override
  Future<List<ChatMessage>> messages() async => [];

  @override
  Future<PagedResult<ChatMessage>> messagesPage({
    String? cursor,
    int limit = 100,
  }) async {
    return const PagedResult(items: []);
  }

  @override
  Future<RoomModel> musicRoom() async {
    return const RoomModel(id: 'music', status: 'idle', items: []);
  }

  @override
  Future<List<NotificationItem>> notifications() async => [];

  @override
  Future<List<NotificationPreferenceModel>> notificationPreferences() async =>
      [];

  @override
  Future<NotificationPreferenceModel> updateNotificationPreference({
    required String type,
    required bool enabled,
    String? quietFrom,
    String? quietTo,
  }) async {
    return NotificationPreferenceModel(
      type: type,
      enabled: enabled,
      quietFrom: quietFrom,
      quietTo: quietTo,
    );
  }

  @override
  Future<List<OccasionItem>> occasions() async => [];

  @override
  Future<MediaAssetModel> uploadMedia({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    return MediaAssetModel(
      id: 'asset',
      objectKey: fileName,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<List<PlaceItem>> places() async => [];

  @override
  Future<List<SpacePost>> posts() async => [];

  @override
  Future<PagedResult<SpacePost>> postsPage({
    String? cursor,
    int limit = 50,
  }) async {
    return const PagedResult(items: []);
  }

  @override
  Future<void> readAllNotifications() async {}

  @override
  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {}

  @override
  Future<void> readAllMessages() async {}

  @override
  Future<void> report({required String reason, String? details}) async {}

  @override
  Future<List<BlockedUserModel>> blockedUsers() async => [];

  @override
  Future<void> blockPartner({String? reason}) async {}

  @override
  Future<void> unblockUser(String blockedUserId) async {}

  @override
  Future<RelationshipSummaryModel> relationshipSummary({
    String period = 'month',
    DateTime? referenceDate,
  }) async {
    return RelationshipSummaryModel(
      period: period,
      title: 'ملخص العلاقة',
      start: DateTime(2026, 8),
      end: DateTime(2026, 9),
      counts: const RelationshipSummaryCounts(
        messages: 0,
        photos: 0,
        videos: 0,
        treeLeaves: 0,
        songs: 0,
        watchSessions: 0,
        places: 0,
        completedGoals: 0,
      ),
      topMoods: const [],
      highlights: const [],
      timeline: const [],
    );
  }

  @override
  Future<ChatMessage> sendMessage(
    String body, {
    List<String> assetIds = const [],
    String? clientMessageId,
    String? replyToId,
  }) async {
    return ChatMessage(
      id: 'message',
      body: body,
      assetIds: assetIds,
      serverTimestamp: DateTime(2026, 8, 3),
    );
  }

  @override
  Future<ChatMessage> editMessage({
    required String messageId,
    required String body,
  }) async {
    return ChatMessage(
      id: messageId,
      body: body,
      serverTimestamp: DateTime(2026, 8, 3),
      editedAt: DateTime(2026, 8, 3, 1),
    );
  }

  @override
  Future<void> deleteMessage(String messageId) async {}

  @override
  Future<ChatMessage> reactToMessage({
    required String messageId,
    String value = 'heart',
  }) async {
    return ChatMessage(
      id: messageId,
      body: 'message',
      serverTimestamp: DateTime(2026, 8, 3),
      reactionCount: 1,
      myReaction: value,
    );
  }

  @override
  Future<ChatMessage> pinMessage({
    required String messageId,
    required bool pinned,
  }) async {
    return ChatMessage(
      id: messageId,
      body: 'message',
      serverTimestamp: DateTime(2026, 8, 3),
      pinCount: pinned ? 1 : 0,
      pinnedByMe: pinned,
    );
  }

  @override
  Future<List<ScheduledMessageModel>> scheduledMessages() async => [];

  @override
  Future<void> scheduleMessage({
    required String body,
    required DateTime sendAt,
  }) async {}

  @override
  Future<SpaceSummary> summary() async {
    return const SpaceSummary(
      partnershipId: 'partnership',
      worldName: 'عالمنا',
      daysTogether: 1,
      members: [],
      latestPosts: [],
      unreadNotifications: 0,
    );
  }

  @override
  Future<List<SharedListModel>> sharedLists() async => [];

  @override
  Future<void> toggleGoal(String id) async {}

  @override
  Future<void> toggleGoalStep(String id) async {}

  @override
  Future<void> toggleSharedListItem(String id) async {}

  @override
  Future<void> toggleWish(String id) async {}

  @override
  Future<TreeDayModel> todayTree() async {
    return TreeDayModel(
      id: 'tree',
      date: DateTime(2026, 8, 3),
      leaves: const [],
    );
  }

  @override
  Future<void> sendRoomReaction(String room, String emoji) async {}

  @override
  Future<void> sendRoomComment(String room, String text) async {}

  @override
  Future<List<TreeLeafItem>> allTreeLeaves() async => const [];

  @override
  Future<List<TimeCapsuleItem>> timeCapsules() async => [];

  @override
  Future<TimeCapsuleItem> openTimeCapsule(String id) async {
    return TimeCapsuleItem(
      id: id,
      title: 'capsule',
      body: 'open',
      opensAt: DateTime(2026, 8, 3),
      opened: true,
      canOpen: true,
      locked: false,
    );
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    String? avatarUrl,
    String? bio,
    DateTime? birthDate,
    String? gender,
    String? timezone,
    String? language,
    ProfileFavorites? favorites,
    required bool searchable,
    required bool canReceiveRequests,
  }) async {}

  @override
  Future<void> updateUsername(String username) async {}

  @override
  Future<void> updateSettings({String? worldName, String? themeColor}) async {}

  @override
  Future<RoomModel> watchRoom() async {
    return const RoomModel(id: 'watch', status: 'idle', items: []);
  }

  @override
  Future<List<WishItem>> wishes() async => [];
}
