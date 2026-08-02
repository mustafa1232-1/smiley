import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smiley/core/secure_stores.dart';
import 'package:smiley/features/auth/auth_models.dart';
import 'package:smiley/features/auth/auth_repository.dart';
import 'package:smiley/features/gate/gate_validator.dart';
import 'package:smiley/features/partnerships/partnership_repository.dart';
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

class FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    return _session();
  }

  @override
  Future<void> requestPasswordReset(String identifier) async {}

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
  Future<void> requestPartnership(String username) async {}

  @override
  Future<List<PartnerSearchResult>> search(String username) async => [];
}
