import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smiley/core/offline_outbox.dart';
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
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.public_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chat_outlined));
    await tester.pumpAndSettle();

    expect(find.text('المحادثة'), findsWidgets);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
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
  }) async {
    _messages.add(
      QueuedMessage(
        id: 'message-${_messages.length}',
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
  Future<void> addMusicItem(String title) async {}

  @override
  Future<void> addSharedListItem({
    required String listId,
    required String title,
  }) async {}

  @override
  Future<void> addWatchItem(String title) async {}

  @override
  Future<List<AlbumModel>> albums() async => [];

  @override
  Future<List<CalendarItem>> calendarEvents() async => [];

  @override
  Future<void> createAlbum(String title) async {}

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
    );
  }

  @override
  Future<void> createPlace(String title) async {}

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
  Future<void> createTimeCapsule({
    required String title,
    String? body,
    required DateTime opensAt,
  }) async {}

  @override
  Future<void> createTreeLeaf({String? title, required String body}) async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<Map<String, dynamic>> exportAccount() async => {};

  @override
  Future<List<GoalItem>> goals() async => [];

  @override
  Future<List<GameSessionModel>> games() async => [];

  @override
  Future<GameSessionModel> createGame() async {
    return const GameSessionModel(
      id: 'game',
      status: 'active',
      board: [null, null, null, null, null, null, null, null, null],
    );
  }

  @override
  Future<GameSessionModel> playGameMove({
    required String gameId,
    required int position,
  }) async {
    return GameSessionModel(
      id: gameId,
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
  Future<RoomModel> musicRoom() async {
    return const RoomModel(id: 'music', items: []);
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
  Future<void> readAllNotifications() async {}

  @override
  Future<void> readAllMessages() async {}

  @override
  Future<void> report({required String reason, String? details}) async {}

  @override
  Future<ChatMessage> sendMessage(
    String body, {
    List<String> assetIds = const [],
  }) async {
    return ChatMessage(
      id: 'message',
      body: body,
      assetIds: assetIds,
      serverTimestamp: DateTime(2026, 8, 3),
    );
  }

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
  Future<List<TimeCapsuleItem>> timeCapsules() async => [];

  @override
  Future<void> updateProfile({
    required String displayName,
    String? bio,
    required bool searchable,
    required bool canReceiveRequests,
  }) async {}

  @override
  Future<void> updateSettings({String? worldName, String? themeColor}) async {}

  @override
  Future<RoomModel> watchRoom() async {
    return const RoomModel(id: 'watch', items: []);
  }

  @override
  Future<List<WishItem>> wishes() async => [];
}
