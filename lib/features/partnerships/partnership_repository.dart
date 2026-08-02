import '../../core/api_client.dart';

abstract interface class PartnershipRepository {
  Future<List<PartnerSearchResult>> search(String username);
  Future<void> requestPartnership(String username);
  Future<List<PartnershipRequest>> requests();
  Future<CurrentPartnership?> current();
  Future<void> acceptRequest(String id);
  Future<void> rejectRequest(String id);
  Future<void> cancelRequest(String id);
  Future<CurrentPartnership> completeOnboarding(OnboardingInput input);
}

class HttpPartnershipRepository implements PartnershipRepository {
  const HttpPartnershipRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<PartnerSearchResult>> search(String username) async {
    final encoded = Uri.encodeQueryComponent(username);
    final json = await _api.getJson('/users/search?username=$encoded');
    final items = (json['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return items.map(PartnerSearchResult.fromJson).toList();
  }

  @override
  Future<void> requestPartnership(String username) async {
    await _api.postJson('/partnership-requests', {'username': username});
  }

  @override
  Future<List<PartnershipRequest>> requests() async {
    final json = await _api.getJson('/partnership-requests');
    final items = (json['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return items.map(PartnershipRequest.fromJson).toList();
  }

  @override
  Future<CurrentPartnership?> current() async {
    final json = await _api.getJson('/partnerships/current');
    final partnership = json['partnership'] as Map<String, dynamic>?;
    return partnership == null ? null : CurrentPartnership.fromJson(partnership);
  }

  @override
  Future<void> acceptRequest(String id) async {
    await _api.postJson('/partnership-requests/$id/accept', {});
  }

  @override
  Future<void> rejectRequest(String id) async {
    await _api.postJson('/partnership-requests/$id/reject', {});
  }

  @override
  Future<void> cancelRequest(String id) async {
    await _api.postJson('/partnership-requests/$id/cancel', {});
  }

  @override
  Future<CurrentPartnership> completeOnboarding(OnboardingInput input) async {
    final json = await _api.postJson(
      '/partnerships/${input.partnershipId}/onboarding',
      input.toJson(),
    );
    return CurrentPartnership.fromJson(
      json['partnership'] as Map<String, dynamic>,
    );
  }
}

class PartnerSearchResult {
  const PartnerSearchResult({
    required this.displayName,
    required this.username,
    required this.canReceiveRequests,
    this.avatarUrl,
  });

  final String displayName;
  final String username;
  final bool canReceiveRequests;
  final String? avatarUrl;

  factory PartnerSearchResult.fromJson(Map<String, dynamic> json) {
    return PartnerSearchResult(
      displayName: json['displayName'] as String,
      username: json['username'] as String,
      canReceiveRequests: json['canReceiveRequests'] as bool? ?? false,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class PartnershipRequest {
  const PartnershipRequest({
    required this.id,
    required this.status,
    required this.direction,
    required this.otherUser,
  });

  final String id;
  final String status;
  final String direction;
  final SmileyUser otherUser;

  bool get incoming => direction == 'incoming';

  factory PartnershipRequest.fromJson(Map<String, dynamic> json) {
    return PartnershipRequest(
      id: json['id'] as String,
      status: json['status'] as String,
      direction: json['direction'] as String,
      otherUser: SmileyUser.fromJson(json['otherUser'] as Map<String, dynamic>),
    );
  }
}

class CurrentPartnership {
  const CurrentPartnership({
    required this.id,
    required this.status,
    required this.members,
    required this.onboardingCompleted,
    this.startedAt,
    this.worldName,
    this.themeColor,
  });

  final String id;
  final String status;
  final List<SmileyUser> members;
  final bool onboardingCompleted;
  final DateTime? startedAt;
  final String? worldName;
  final String? themeColor;

  bool get needsOnboarding => status == 'pending_onboarding';
  bool get active => status == 'active';

  factory CurrentPartnership.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(SmileyUser.fromJson)
        .toList();

    return CurrentPartnership(
      id: json['id'] as String,
      status: json['status'] as String,
      members: members,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      worldName: json['worldName'] as String?,
      themeColor: json['themeColor'] as String?,
    );
  }
}

class SmileyUser {
  const SmileyUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory SmileyUser.fromJson(Map<String, dynamic> json) {
    return SmileyUser(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? 'مستخدم',
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class OnboardingInput {
  const OnboardingInput({
    required this.partnershipId,
    required this.startDate,
    required this.worldName,
    this.themeColor,
  });

  final String partnershipId;
  final DateTime startDate;
  final String worldName;
  final String? themeColor;

  Map<String, dynamic> toJson() {
    return {
      'startDate': startDate.toUtc().toIso8601String(),
      'worldName': worldName,
      if (themeColor != null) 'themeColor': themeColor,
      'answers': <String, dynamic>{},
      'occasions': <Map<String, dynamic>>[],
    };
  }
}
