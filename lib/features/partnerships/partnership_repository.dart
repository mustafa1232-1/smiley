import '../../core/api_client.dart';

abstract interface class PartnershipRepository {
  Future<List<PartnerSearchResult>> search(String username);
  Future<void> requestPartnership(String username);
}

class HttpPartnershipRepository implements PartnershipRepository {
  const HttpPartnershipRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<PartnerSearchResult>> search(String username) async {
    final json = await _api.getJson('/users/search?username=$username');
    final items = (json['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return items.map(PartnerSearchResult.fromJson).toList();
  }

  @override
  Future<void> requestPartnership(String username) async {
    await _api.postJson('/partnership-requests', {'username': username});
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
