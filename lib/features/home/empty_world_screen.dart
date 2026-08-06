import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart'
    hide PlayerState;

import '../../core/animations.dart';
import '../../core/api_client.dart';
import '../../core/avatar.dart';
import '../../core/offline_outbox.dart';
import '../../core/realtime_client.dart';
import '../../core/secure_stores.dart';
import '../../core/weather_service.dart';
import '../auth/auth_repository.dart';
import '../partnerships/partnership_repository.dart';
import '../space/space_repository.dart';

class EmptyWorldScreen extends StatefulWidget {
  const EmptyWorldScreen({
    required this.partnershipRepository,
    required this.spaceRepository,
    required this.offlineOutbox,
    required this.authRepository,
    required this.realtimeClient,
    required this.tokenStore,
    required this.onSignedOut,
    super.key,
  });

  final PartnershipRepository partnershipRepository;
  final SpaceRepository spaceRepository;
  final OfflineOutbox offlineOutbox;
  final AuthRepository authRepository;
  final RealtimeClient realtimeClient;
  final AuthTokenStore tokenStore;
  final VoidCallback onSignedOut;

  @override
  State<EmptyWorldScreen> createState() => _EmptyWorldScreenState();
}

class _EmptyWorldScreenState extends State<EmptyWorldScreen> {
  int _index = 0;
  late Future<_WorldState> _state = _load();
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    widget.realtimeClient.connect();
    _realtimeSubscription = widget.realtimeClient.events.listen((event) {
      final type = event['type']?.toString() ?? '';
      if (type == 'notification.created') {
        _showIncomingNotification(event);
        _reload();
      } else if (type.startsWith('partnership.')) {
        _reload();
      }
    });
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  // Shows a floating in-app banner when a realtime notification arrives, with a
  // shortcut to open the conversation.
  void _showIncomingNotification(Map<String, dynamic> event) {
    if (!mounted) return;
    final payload = event['payload'];
    final notification = payload is Map ? payload['notification'] : null;
    final title = notification is Map
        ? notification['title']?.toString()
        : null;
    final body = notification is Map ? notification['body']?.toString() : null;
    final text = [
      title,
      body,
    ].where((value) => value != null && value.isNotEmpty).join(' — ');
    if (text.isEmpty) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'عرض',
            onPressed: () => setState(() => _index = 1),
          ),
        ),
      );
  }

  Future<_WorldState> _load() async {
    final current = await widget.partnershipRepository.current();
    final requests = current == null
        ? await widget.partnershipRepository.requests()
        : <PartnershipRequest>[];
    return _WorldState(current: current, requests: requests);
  }

  void _reload() {
    setState(() => _state = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WorldState>(
      future: _state,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final current = state?.current;
        final active = current?.active ?? false;

        return Scaffold(
          appBar: AppBar(
            title: Text(current?.worldName ?? 'Smiley'),
            actions: [
              IconButton(
                tooltip: 'تحديث',
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: snapshot.hasError
              ? _ErrorState(
                  message: snapshot.error.toString(),
                  onRetry: _reload,
                )
              : !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_index),
                    child: _pageFor(state!),
                  ),
                ),
          floatingActionButton: active
              ? null
              : PopIn(
                  child: FloatingActionButton(
                    onPressed: _openPartnerSearch,
                    tooltip: 'إضافة شريك',
                    child: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'الرئيسية',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_outlined),
                label: 'المحادثة',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_border_rounded),
                label: 'العالم',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined),
                label: 'التقويم',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_rounded),
                label: 'المزيد',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pageFor(_WorldState state) {
    final current = state.current;
    if (current == null) {
      return switch (_index) {
        0 => _NoPartnerTab(
          requests: state.requests,
          onRefresh: _reload,
          onAddPartner: _openPartnerSearch,
          onAccept: _acceptRequest,
          onReject: _rejectRequest,
          onCancel: _cancelRequest,
        ),
        1 => _PartnerRequiredTab(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'المحادثة',
          message:
              'المحادثة الخاصة والرسائل والوسائط تبدأ بعد قبول الشريك وإكمال إعداد العلاقة.',
          buttonLabel: 'إضافة شريك للمحادثة',
          onAddPartner: _openPartnerSearch,
        ),
        2 => _PartnerRequiredTab(
          icon: Icons.favorite_border_rounded,
          title: 'عالم Smiley',
          message:
              'الذكريات، المزاج، الشجرة، الألعاب، والغرف المشتركة تظهر هنا بعد إنشاء العالم مع الشريك.',
          buttonLabel: 'بدء العالم',
          onAddPartner: _openPartnerSearch,
        ),
        3 => _PartnerRequiredTab(
          icon: Icons.calendar_month_rounded,
          title: 'التقويم',
          message:
              'المواعيد والمناسبات والعدّادات لا تبدأ قبل وجود شراكة نشطة حتى لا تُنشأ بيانات وهمية.',
          buttonLabel: 'إضافة شريك للتقويم',
          onAddPartner: _openPartnerSearch,
        ),
        _ => _MoreHubTabV2(
          repository: widget.spaceRepository,
          partnershipRepository: widget.partnershipRepository,
          authRepository: widget.authRepository,
          hasActivePartnership: false,
          onPartnershipChanged: _reload,
          onSignOut: _signOut,
          events: widget.realtimeClient.events,
        ),
      };
    }

    if (current.needsOnboarding) {
      return switch (_index) {
        0 => _OnboardingTab(
          partnership: current,
          onComplete: _completeOnboarding,
        ),
        4 => _MoreHubTabV2(
          repository: widget.spaceRepository,
          partnershipRepository: widget.partnershipRepository,
          authRepository: widget.authRepository,
          hasActivePartnership: false,
          onPartnershipChanged: _reload,
          onSignOut: _signOut,
          events: widget.realtimeClient.events,
        ),
        _ => _PartnerRequiredTab(
          icon: Icons.auto_awesome_rounded,
          title: 'إعداد العلاقة',
          message: 'أكمل إعداد البداية أولاً لتفعيل هذا التبويب.',
          buttonLabel: 'تحديث الحالة',
          onAddPartner: _reload,
        ),
      };
    }

    return switch (_index) {
      0 => _HomeTab(
        repository: widget.spaceRepository,
        offlineOutbox: widget.offlineOutbox,
        events: widget.realtimeClient.events,
        onOpenTab: (index) => setState(() => _index = index),
      ),
      1 => _ChatTab(
        repository: widget.spaceRepository,
        offlineOutbox: widget.offlineOutbox,
        events: widget.realtimeClient.events,
      ),
      2 => _WorldTab(
        repository: widget.spaceRepository,
        events: widget.realtimeClient.events,
      ),
      3 => _CalendarTab(
        repository: widget.spaceRepository,
        events: widget.realtimeClient.events,
      ),
      _ => _MoreHubTabV2(
        repository: widget.spaceRepository,
        partnershipRepository: widget.partnershipRepository,
        authRepository: widget.authRepository,
        hasActivePartnership: true,
        onPartnershipChanged: _reload,
        onSignOut: _signOut,
      ),
    };
  }

  Future<void> _acceptRequest(String id) async {
    await widget.partnershipRepository.acceptRequest(id);
    _reload();
  }

  Future<void> _rejectRequest(String id) async {
    await widget.partnershipRepository.rejectRequest(id);
    _reload();
  }

  Future<void> _cancelRequest(String id) async {
    await widget.partnershipRepository.cancelRequest(id);
    _reload();
  }

  Future<void> _completeOnboarding(OnboardingInput input) async {
    await widget.partnershipRepository.completeOnboarding(input);
    _reload();
  }

  Future<void> _signOut() async {
    final refreshToken = await widget.tokenStore.readRefreshToken();
    if (refreshToken != null) {
      try {
        await widget.authRepository.logout(refreshToken);
      } on ApiException {
        // Local sign-out should still complete if the session is already invalid.
      }
    }
    await widget.realtimeClient.disconnect();
    await widget.tokenStore.clear();
    if (!mounted) return;
    widget.onSignedOut();
  }

  Future<void> _openPartnerSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PartnerSearchScreen(repository: widget.partnershipRepository),
      ),
    );
    _reload();
  }
}

class _WorldState {
  const _WorldState({required this.current, required this.requests});

  final CurrentPartnership? current;
  final List<PartnershipRequest> requests;
}

class _NoPartnerTab extends StatelessWidget {
  const _NoPartnerTab({
    required this.requests,
    required this.onRefresh,
    required this.onAddPartner,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
  });

  final List<PartnershipRequest> requests;
  final VoidCallback onRefresh;
  final VoidCallback onAddPartner;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onReject;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(
            icon: Icons.public_rounded,
            title: 'العالم لم يبدأ بعد',
            subtitle: 'أضف الشريك أو اقبل طلباً وارداً لبدء إعداد العلاقة.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddPartner,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('إضافة شريك'),
          ),
          const SizedBox(height: 24),
          Text('طلبات الارتباط', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (requests.isEmpty)
            _EmptyLine(
              color: scheme.onSurfaceVariant,
              text: 'لا توجد طلبات معلقة حالياً.',
            )
          else
            for (final request in requests)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline_rounded),
                  ),
                  title: Text(request.otherUser.displayName),
                  subtitle: Text('@${request.otherUser.username}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: request.incoming
                        ? [
                            IconButton(
                              tooltip: 'قبول',
                              onPressed: () => onAccept(request.id),
                              icon: const Icon(Icons.check_rounded),
                            ),
                            IconButton(
                              tooltip: 'رفض',
                              onPressed: () => onReject(request.id),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ]
                        : [
                            IconButton(
                              tooltip: 'إلغاء',
                              onPressed: () => onCancel(request.id),
                              icon: const Icon(Icons.undo_rounded),
                            ),
                          ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _PartnerRequiredTab extends StatelessWidget {
  const _PartnerRequiredTab({
    required this.icon,
    required this.title,
    required this.onAddPartner,
    this.message = 'هذا التبويب يبدأ بعد إضافة الشريك وقبول الطلب.',
    this.buttonLabel = 'إضافة شريك',
  });

  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onAddPartner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FadeSlideIn(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PopIn(
                  child: Icon(icon, size: 48, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onAddPartner,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(buttonLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingTab extends StatefulWidget {
  const _OnboardingTab({required this.partnership, required this.onComplete});

  final CurrentPartnership partnership;
  final ValueChanged<OnboardingInput> onComplete;

  @override
  State<_OnboardingTab> createState() => _OnboardingTabState();
}

class _OnboardingTabState extends State<_OnboardingTab> {
  final _worldName = TextEditingController(text: 'عالمنا');
  final _occasionTitle = TextEditingController();
  final _favoriteThings = TextEditingController();
  final _wishes = TextEditingController();
  final _places = TextEditingController();
  final _watchList = TextEditingController();
  final _favoriteSongs = TextEditingController();
  final _goals = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime _occasionDate = DateTime.now().add(const Duration(days: 30));
  String _themeColor = '#B96B7F';
  bool _busy = false;

  @override
  void dispose() {
    _worldName.dispose();
    _occasionTitle.dispose();
    _favoriteThings.dispose();
    _wishes.dispose();
    _places.dispose();
    _watchList.dispose();
    _favoriteSongs.dispose();
    _goals.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(
          icon: Icons.auto_awesome_rounded,
          title: 'إعداد عالم Smiley',
          subtitle:
              'حددوا اسم العالم وتاريخ البداية ليتم تفعيل التجربة المشتركة.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _worldName,
          decoration: const InputDecoration(
            labelText: 'اسم العالم',
            prefixIcon: Icon(Icons.favorite_border_rounded),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _themeColor,
          decoration: const InputDecoration(
            labelText: 'لون العالم',
            prefixIcon: Icon(Icons.palette_outlined),
          ),
          items: const [
            DropdownMenuItem(value: '#B96B7F', child: Text('وردي هادئ')),
            DropdownMenuItem(value: '#3E7C78', child: Text('أخضر مائي')),
            DropdownMenuItem(value: '#7A6A9E', child: Text('بنفسجي ناعم')),
            DropdownMenuItem(value: '#C18C5D', child: Text('ذهبي دافئ')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _themeColor = value);
          },
        ),
        const SizedBox(height: 14),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_available_outlined),
          title: const Text('تاريخ البداية'),
          subtitle: Text(_date(_startDate)),
          trailing: IconButton(
            tooltip: 'اختيار تاريخ',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _pickDate,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _occasionTitle,
          decoration: const InputDecoration(
            labelText: 'مناسبة مهمة اختيارية',
            prefixIcon: Icon(Icons.celebration_outlined),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('تاريخ المناسبة'),
          subtitle: Text(_date(_occasionDate)),
          trailing: IconButton(
            tooltip: 'اختيار التاريخ',
            icon: const Icon(Icons.event_rounded),
            onPressed: _pickOccasionDate,
          ),
        ),
        const SizedBox(height: 12),
        _OnboardingListField(
          controller: _favoriteThings,
          icon: Icons.favorite_border_rounded,
          label: 'أشياء تحبونها',
        ),
        const SizedBox(height: 12),
        _OnboardingListField(
          controller: _wishes,
          icon: Icons.local_florist_outlined,
          label: 'أمنيات البداية',
        ),
        const SizedBox(height: 12),
        _OnboardingListField(
          controller: _places,
          icon: Icons.place_outlined,
          label: 'أماكن تريدون زيارتها',
        ),
        const SizedBox(height: 12),
        _OnboardingListField(
          controller: _watchList,
          icon: Icons.movie_outlined,
          label: 'أفلام أو مسلسلات للمشاهدة',
        ),
        const SizedBox(height: 12),
        _OnboardingListField(
          controller: _favoriteSongs,
          icon: Icons.music_note_outlined,
          label: 'أغانٍ مفضلة',
        ),
        const SizedBox(height: 12),
        _OnboardingListField(
          controller: _goals,
          icon: Icons.flag_outlined,
          label: 'أهداف مشتركة',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('تفعيل العالم'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (value != null) setState(() => _startDate = value);
  }

  Future<void> _pickOccasionDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _occasionDate,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null) setState(() => _occasionDate = value);
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final occasionTitle = _occasionTitle.text.trim();
    widget.onComplete(
      OnboardingInput(
        partnershipId: widget.partnership.id,
        startDate: _startDate,
        worldName: _worldName.text.trim().isEmpty
            ? 'عالمنا'
            : _worldName.text.trim(),
        themeColor: _themeColor,
        favoriteThings: _listFrom(_favoriteThings),
        wishes: _listFrom(_wishes),
        places: _listFrom(_places),
        watchList: _listFrom(_watchList),
        favoriteSongs: _listFrom(_favoriteSongs),
        goals: _listFrom(_goals),
        occasions: occasionTitle.isEmpty
            ? const []
            : [
                OnboardingOccasionInput(
                  title: occasionTitle,
                  date: _occasionDate,
                  recurrence: 'yearly',
                ),
              ],
      ),
    );
  }

  List<String> _listFrom(TextEditingController controller) {
    return controller.text
        .split(RegExp(r'[\n,،]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(20)
        .toList();
  }
}

class _OnboardingListField extends StatelessWidget {
  const _OnboardingListField({
    required this.controller,
    required this.icon,
    required this.label,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}

// Live-refresh helper: rebuilds a tab's data when a matching realtime event
// arrives, without touching text controllers (so typing is never interrupted).
mixin _RealtimeRefreshMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<Map<String, dynamic>>? _realtimeRefreshSub;

  Stream<Map<String, dynamic>> get realtimeEvents;
  List<String> get refreshOnEventTypes;
  void onRealtimeRefresh();

  void startRealtimeRefresh() {
    _realtimeRefreshSub = realtimeEvents.listen((event) {
      final type = event['type']?.toString() ?? '';
      final matches = refreshOnEventTypes.any(
        (prefix) => type == prefix || type.startsWith(prefix),
      );
      if (matches && mounted) onRealtimeRefresh();
    });
  }

  void stopRealtimeRefresh() {
    _realtimeRefreshSub?.cancel();
    _realtimeRefreshSub = null;
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    required this.repository,
    required this.offlineOutbox,
    required this.events,
    required this.onOpenTab,
  });

  final SpaceRepository repository;
  final OfflineOutbox offlineOutbox;
  final Stream<Map<String, dynamic>> events;
  final void Function(int index) onOpenTab;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab>
    with _RealtimeRefreshMixin<_HomeTab> {
  late Future<SpaceSummary> _summary = _loadSummary();
  final _post = TextEditingController();
  final List<MediaAssetModel> _attachments = [];
  bool _posting = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    startRealtimeRefresh();
  }

  @override
  Stream<Map<String, dynamic>> get realtimeEvents => widget.events;

  @override
  List<String> get refreshOnEventTypes => const [
    'post.',
    'mood.',
    'message.',
    'tree.',
    'goal.',
    'occasion.',
  ];

  @override
  void onRealtimeRefresh() {
    setState(() => _summary = _loadSummary());
  }

  @override
  void dispose() {
    stopRealtimeRefresh();
    _post.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpaceSummary>(
      future: _summary,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final summary = snapshot.requireData;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _HomeHeroCard(
                worldName: summary.worldName ?? 'عالمنا',
                daysTogether: summary.daysTogether,
                nextEvent: summary.nextEvent,
              ),
              const SizedBox(height: 16),
              _HomeQuickActions(
                onHeart: _sendHeart,
                onMood: _quickMood,
                onChat: () => widget.onOpenTab(1),
                onWorld: () => widget.onOpenTab(2),
              ),
              const SizedBox(height: 16),
              if (summary.latestMood != null) ...[
                _MoodBanner(mood: summary.latestMood!),
                const SizedBox(height: 16),
              ],
              _PostComposer(
                controller: _post,
                busy: _posting,
                uploading: _uploading,
                attachmentCount: _attachments.length,
                onAttach: _attachMedia,
                onSubmit: _createPost,
              ),
              FutureBuilder<List<QueuedPost>>(
                future: widget.offlineOutbox.posts(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _InfoTile(
                      icon: Icons.sync_problem_rounded,
                      title: 'بانتظار المزامنة',
                      subtitle: '$count منشورات محفوظة محلياً',
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                'آخر الذكريات',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (summary.latestPosts.isEmpty)
                const _EmptyLine(
                  text: 'لا توجد ذكريات بعد.',
                  color: Colors.grey,
                )
              else
                for (final post in summary.latestPosts)
                  _PostTile(
                    post: post,
                    onReact: () => _reactToPost(post.id),
                    onComment: () => _commentOnPost(post.id),
                    onEdit: () => _editPost(post),
                    onDelete: () => _deletePost(post.id),
                  ),
            ],
          ),
        );
      },
    );
  }

  void _reload() {
    setState(() => _summary = _loadSummary());
  }

  Future<void> _sendHeart() async {
    try {
      await widget.repository.sendMessage(
        '❤️',
        clientMessageId: 'heart-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أرسلت قلبًا ❤️')));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _quickMood() async {
    const moods = <(String, String)>[
      ('happy', '😊'),
      ('love', '🥰'),
      ('calm', '😌'),
      ('excited', '🤩'),
      ('tired', '😴'),
      ('miss_you', '🥺'),
    ];
    final selected = await showModalBottomSheet<(String, String)>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'كيف مزاجك الآن؟',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final mood in moods)
                    ActionChip(
                      avatar: Text(
                        mood.$2,
                        style: const TextStyle(fontSize: 18),
                      ),
                      label: Text(_moodLabel(mood.$1)),
                      onPressed: () => Navigator.of(context).pop(mood),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    try {
      await widget.repository.createMood(kind: selected.$1, emoji: selected.$2);
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم تحديث مزاجك ${selected.$2}')));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String _moodLabel(String kind) => switch (kind) {
    'happy' => 'سعيد',
    'love' => 'عاشق',
    'calm' => 'هادئ',
    'excited' => 'متحمّس',
    'tired' => 'متعب',
    'miss_you' => 'مشتاق',
    _ => kind,
  };

  Future<SpaceSummary> _loadSummary() async {
    await _syncPendingPosts();
    return widget.repository.summary();
  }

  Future<void> _createPost() async {
    if (_post.text.trim().isEmpty && _attachments.isEmpty) return;
    setState(() => _posting = true);
    try {
      await widget.repository.createPost(
        body: _post.text.trim().isEmpty ? 'مرفق جديد' : _post.text,
        assetIds: _attachments.map((asset) => asset.id).toList(),
      );
      _post.clear();
      _attachments.clear();
      _reload();
    } on ApiException catch (error) {
      if (error.code != 'network_error') rethrow;
      await widget.offlineOutbox.enqueuePost(
        body: _post.text.trim().isEmpty ? 'مرفق جديد' : _post.text,
        assetIds: _attachments.map((asset) => asset.id).toList(),
      );
      _post.clear();
      _attachments.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المنشور محلياً للمزامنة.')),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _syncPendingPosts() async {
    final pending = await widget.offlineOutbox.posts();
    for (final post in pending) {
      try {
        await widget.repository.createPost(
          body: post.body,
          assetIds: post.assetIds,
        );
        await widget.offlineOutbox.removePost(post.id);
      } on ApiException catch (error) {
        if (error.code == 'network_error') return;
        await widget.offlineOutbox.removePost(post.id);
      }
    }
  }

  Future<void> _attachMedia() async {
    final result = await FilePicker.pickFiles(withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    setState(() => _uploading = true);
    try {
      final asset = await widget.repository.uploadMedia(
        fileName: file.name,
        mimeType: _mimeTypeFromName(file.name),
        bytes: bytes,
      );
      setState(() => _attachments.add(asset));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _reactToPost(String postId) async {
    await widget.repository.reactToPost(postId: postId);
    _reload();
  }

  Future<void> _commentOnPost(String postId) async {
    final body = await _promptText(context, 'تعليق جديد');
    if (body == null || body.trim().isEmpty) return;
    await widget.repository.commentOnPost(postId: postId, body: body);
    _reload();
  }

  Future<void> _editPost(SpacePost post) async {
    final body = await _promptText(
      context,
      'تعديل الذكرى',
      initial: post.body,
      label: 'نص الذكرى',
    );
    if (body == null || body.trim().isEmpty) return;
    await widget.repository.updatePost(postId: post.id, body: body);
    _reload();
  }

  Future<void> _deletePost(String postId) async {
    final confirmed = await _confirmDeletePost(context);
    if (confirmed != true) return;
    await widget.repository.deletePost(postId);
    _reload();
  }
}

class _WorldTab extends StatefulWidget {
  const _WorldTab({required this.repository, required this.events});

  final SpaceRepository repository;
  final Stream<Map<String, dynamic>> events;

  @override
  State<_WorldTab> createState() => _WorldTabState();
}

class _WorldTabState extends State<_WorldTab>
    with _RealtimeRefreshMixin<_WorldTab> {
  late Future<List<SpacePost>> _posts = widget.repository.posts();
  final _moodNote = TextEditingController();

  @override
  void initState() {
    super.initState();
    startRealtimeRefresh();
  }

  @override
  Stream<Map<String, dynamic>> get realtimeEvents => widget.events;

  @override
  List<String> get refreshOnEventTypes => const ['post.', 'mood.', 'tree.'];

  @override
  void onRealtimeRefresh() {
    setState(() => _posts = widget.repository.posts());
  }

  @override
  void dispose() {
    stopRealtimeRefresh();
    _moodNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(
          icon: Icons.auto_awesome_rounded,
          title: 'عالم Smiley',
          subtitle: 'المزاج والذكريات المشتركة تظهر هنا من البيانات الحقيقية.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _moodNote,
          decoration: const InputDecoration(
            labelText: 'ملاحظة المزاج',
            prefixIcon: Icon(Icons.mood_rounded),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MoodButton(label: 'هادئ', onTap: () => _setMood('calm')),
            _MoodButton(label: 'سعيد', onTap: () => _setMood('happy')),
            _MoodButton(label: 'مشتاق', onTap: () => _setMood('missing')),
            _MoodButton(label: 'متعب', onTap: () => _setMood('tired')),
          ],
        ),
        const SizedBox(height: 22),
        FutureBuilder<List<SpacePost>>(
          future: _posts,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = snapshot.requireData;
            if (posts.isEmpty) {
              return const _EmptyLine(
                text: 'أول ذكرى ستظهر هنا بعد إضافتها من الرئيسية.',
                color: Colors.grey,
              );
            }
            return Column(
              children: [
                for (final post in posts)
                  _PostTile(
                    post: post,
                    onReact: () => _reactToPost(post.id),
                    onComment: () => _commentOnPost(post.id),
                    onEdit: () => _editPost(post),
                    onDelete: () => _deletePost(post.id),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _setMood(String kind) async {
    await widget.repository.createMood(kind: kind, note: _moodNote.text);
    _moodNote.clear();
    setState(() => _posts = widget.repository.posts());
  }

  Future<void> _reactToPost(String postId) async {
    await widget.repository.reactToPost(postId: postId);
    setState(() => _posts = widget.repository.posts());
  }

  Future<void> _commentOnPost(String postId) async {
    final body = await _promptText(context, 'تعليق جديد');
    if (body == null || body.trim().isEmpty) return;
    await widget.repository.commentOnPost(postId: postId, body: body);
    setState(() => _posts = widget.repository.posts());
  }

  Future<void> _editPost(SpacePost post) async {
    final body = await _promptText(
      context,
      'تعديل الذكرى',
      initial: post.body,
      label: 'نص الذكرى',
    );
    if (body == null || body.trim().isEmpty) return;
    await widget.repository.updatePost(postId: post.id, body: body);
    setState(() => _posts = widget.repository.posts());
  }

  Future<void> _deletePost(String postId) async {
    final confirmed = await _confirmDeletePost(context);
    if (confirmed != true) return;
    await widget.repository.deletePost(postId);
    setState(() => _posts = widget.repository.posts());
  }
}

class _ChatTab extends StatefulWidget {
  const _ChatTab({
    required this.repository,
    required this.offlineOutbox,
    required this.events,
  });

  final SpaceRepository repository;
  final OfflineOutbox offlineOutbox;
  final Stream<Map<String, dynamic>> events;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab>
    with _RealtimeRefreshMixin<_ChatTab> {
  late Future<List<ChatMessage>> _messages = _loadMessages();
  late Future<List<ScheduledMessageModel>> _scheduled = _loadScheduled();
  final _message = TextEditingController();
  final List<MediaAssetModel> _attachments = [];
  bool _sending = false;
  bool _uploading = false;

  static const _chatColorPrefsKey = 'smiley.chat.bg_color';
  Color? _chatColor;

  final _search = TextEditingController();
  String _searchQuery = '';
  ChatMessage? _replyTo;

  @override
  void initState() {
    super.initState();
    startRealtimeRefresh();
    _loadChatColor();
  }

  Future<void> _loadChatColor() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_chatColorPrefsKey);
    if (!mounted || value == null) return;
    setState(() => _chatColor = Color(value));
  }

  Future<void> _setChatColor(Color? color) async {
    setState(() => _chatColor = color);
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_chatColorPrefsKey);
    } else {
      await prefs.setInt(_chatColorPrefsKey, color.toARGB32());
    }
  }

  Future<void> _pickChatColor() async {
    const options = <Color?>[
      null,
      Color(0xFFF3E9FF),
      Color(0xFFFFE9F3),
      Color(0xFFE9FFF4),
      Color(0xFFFFF3E0),
      Color(0xFFE9F1FF),
      Color(0xFFFDF6E3),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('لون خلفية المحادثة'),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: options.map((color) {
              final selected = _chatColor?.toARGB32() == color?.toARGB32();
              return InkResponse(
                onTap: () {
                  _setChatColor(color);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color ?? scheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: color == null
                      ? const Icon(Icons.format_color_reset_outlined, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Stream<Map<String, dynamic>> get realtimeEvents => widget.events;

  @override
  List<String> get refreshOnEventTypes => const ['message.'];

  @override
  void onRealtimeRefresh() {
    setState(() {
      _messages = _loadMessages();
      _scheduled = _loadScheduled();
    });
  }

  @override
  void dispose() {
    stopRealtimeRefresh();
    _search.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _chatColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'بحث في المحادثة…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ChatMessage>>(
              future: _messages,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.requireData;
                final query = _searchQuery.trim().toLowerCase();
                final items = query.isEmpty
                    ? all
                    : all
                          .where((m) => m.body.toLowerCase().contains(query))
                          .toList();
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty ? 'لا توجد رسائل بعد.' : 'لا نتائج للبحث.',
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final scheme = Theme.of(context).colorScheme;
                    return Align(
                      alignment: item.isMine
                          ? AlignmentDirectional.centerStart
                          : AlignmentDirectional.centerEnd,
                      child: Card(
                        color: item.isMine
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.replyTo != null) ...[
                                IntrinsicHeight(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 3,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              item.replyTo!.mine
                                                  ? 'أنت'
                                                  : item
                                                        .replyTo!
                                                        .senderUsername,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: scheme.primary,
                                              ),
                                            ),
                                            Text(
                                              item.replyTo!.body ?? 'مرفق',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              if (!item.isMine &&
                                  item.senderUsername != null) ...[
                                Text(
                                  item.senderUsername!,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              if (item.body.isNotEmpty) Text(item.body),
                              if (item.attachments.isNotEmpty)
                                _MediaGallery(attachments: item.attachments)
                              else if (item.assetIds.isNotEmpty) ...[
                                if (item.body.isNotEmpty)
                                  const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.attach_file_rounded,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text('مرفقات: ${item.assetIds.length}'),
                                  ],
                                ),
                              ],
                              if (item.pending) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'بانتظار المزامنة',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (!item.pending) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _reactToMessage(item.id),
                                      icon: Icon(
                                        item.myReaction == null
                                            ? Icons.favorite_border_rounded
                                            : Icons.favorite_rounded,
                                        size: 18,
                                      ),
                                      label: Text('${item.reactionCount}'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _pinMessage(item),
                                      icon: Icon(
                                        item.pinnedByMe
                                            ? Icons.push_pin
                                            : Icons.push_pin_outlined,
                                        size: 18,
                                      ),
                                      label: Text('${item.pinCount}'),
                                    ),
                                    IconButton(
                                      tooltip: 'رد',
                                      onPressed: () =>
                                          setState(() => _replyTo = item),
                                      icon: const Icon(
                                        Icons.reply_rounded,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'تعديل',
                                      onPressed: () => _editMessage(item),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'حذف',
                                      onPressed: () => _deleteMessage(item.id),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (item.editedAt != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'تم التعديل',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          FutureBuilder<List<ScheduledMessageModel>>(
            future: _scheduled,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <ScheduledMessageModel>[];
              if (items.isEmpty) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _InfoTile(
                  icon: Icons.schedule_send_rounded,
                  title: 'رسائل مجدولة',
                  subtitle:
                      '${items.length} قادمة - التالية ${_date(items.first.sendAt)}',
                ),
              );
            },
          ),
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyTo != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'رد على ${_replyTo!.isMine ? 'رسالتك' : (_replyTo!.senderUsername ?? 'شريكك')}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Text(
                                _replyTo!.body.isNotEmpty
                                    ? _replyTo!.body
                                    : 'مرفق',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() => _replyTo = null),
                        ),
                      ],
                    ),
                  ),
                _EmojiBar(onSelect: _insertEmoji),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded),
                        onSelected: (value) {
                          if (value == 'color') _pickChatColor();
                          if (value == 'schedule') _schedule();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'color',
                            child: Text('لون المحادثة'),
                          ),
                          PopupMenuItem(
                            value: 'schedule',
                            child: Text('جدولة رسالة'),
                          ),
                        ],
                      ),
                      IconButton.outlined(
                        tooltip: 'إرفاق ملف',
                        onPressed: (_sending || _uploading)
                            ? null
                            : _attachMedia,
                        icon: _uploading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Badge.count(
                                count: _attachments.length,
                                isLabelVisible: _attachments.isNotEmpty,
                                child: const Icon(Icons.attach_file_rounded),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _message,
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالة',
                            prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'إرسال',
                        onPressed: (_sending || _uploading) ? null : _send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _insertEmoji(String emoji) {
    final text = _message.text;
    final selection = _message.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final updated = text.replaceRange(start, end, emoji);
    _message.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _send() async {
    final body = _message.text;
    final assetIds = _attachments.map((asset) => asset.id).toList();
    if (body.trim().isEmpty && assetIds.isEmpty) return;
    setState(() => _sending = true);
    // Stable id shared between the live attempt and the offline retry so the
    // server de-duplicates if the first attempt actually reached it.
    final clientMessageId = 'm-${DateTime.now().microsecondsSinceEpoch}';
    final replyToId = _replyTo?.id;
    try {
      await widget.repository.sendMessage(
        body,
        assetIds: assetIds,
        clientMessageId: clientMessageId,
        replyToId: replyToId,
      );
      _message.clear();
      _attachments.clear();
      setState(() {
        _replyTo = null;
        _messages = _loadMessages();
      });
    } on ApiException catch (error) {
      if (error.code != 'network_error') rethrow;
      await widget.offlineOutbox.enqueueMessage(
        body,
        assetIds: assetIds,
        id: clientMessageId,
      );
      _message.clear();
      _attachments.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الرسالة محلياً للمزامنة.')),
      );
      setState(() => _messages = _loadMessages());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<List<ChatMessage>> _loadMessages() async {
    await _syncPendingMessages();
    List<ChatMessage> items = const [];
    try {
      items = await widget.repository.messages();
    } on ApiException catch (error) {
      if (error.code != 'network_error') rethrow;
    }
    if (items.isNotEmpty) {
      try {
        await widget.repository.readAllMessages();
      } on ApiException {
        // Reading receipts should not block the conversation view.
      }
    }
    final pending = await widget.offlineOutbox.messages();
    return [
      ...items,
      ...pending.map(
        (item) => ChatMessage(
          id: item.id,
          body: item.body,
          assetIds: item.assetIds,
          serverTimestamp: item.createdAt,
          pending: true,
          isMine: true,
        ),
      ),
    ];
  }

  Future<List<ScheduledMessageModel>> _loadScheduled() async {
    try {
      return widget.repository.scheduledMessages();
    } on ApiException catch (error) {
      if (error.code == 'network_error') return const [];
      rethrow;
    }
  }

  Future<void> _syncPendingMessages() async {
    final pending = await widget.offlineOutbox.messages();
    for (final message in pending) {
      try {
        await widget.repository.sendMessage(
          message.body,
          assetIds: message.assetIds,
          clientMessageId: message.id,
        );
        await widget.offlineOutbox.removeMessage(message.id);
      } on ApiException catch (error) {
        if (error.code == 'network_error') return;
        await widget.offlineOutbox.removeMessage(message.id);
      }
    }
  }

  Future<void> _schedule() async {
    final body = _message.text.trim();
    if (body.isEmpty) return;
    if (_attachments.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جدولة الرسائل النصية فقط حالياً.')),
      );
      return;
    }

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;

    final sendAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (sendAt.isBefore(now)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر وقتاً مستقبلياً للإرسال.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.repository.scheduleMessage(body: body, sendAt: sendAt);
      _message.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت جدولة الرسالة.')));
      setState(() => _scheduled = _loadScheduled());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reactToMessage(String messageId) async {
    await widget.repository.reactToMessage(messageId: messageId);
    setState(() => _messages = _loadMessages());
  }

  Future<void> _pinMessage(ChatMessage message) async {
    await widget.repository.pinMessage(
      messageId: message.id,
      pinned: !message.pinnedByMe,
    );
    setState(() => _messages = _loadMessages());
  }

  Future<void> _editMessage(ChatMessage message) async {
    final body = await _promptText(
      context,
      'تعديل الرسالة',
      initial: message.body,
    );
    if (body == null || body.trim().isEmpty || body.trim() == message.body) {
      return;
    }
    try {
      await widget.repository.editMessage(messageId: message.id, body: body);
      setState(() => _messages = _loadMessages());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الرسالة'),
        content: const Text('سيتم حذف الرسالة من المحادثة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteMessage(messageId);
      setState(() => _messages = _loadMessages());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _attachMedia() async {
    final result = await FilePicker.pickFiles(withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    setState(() => _uploading = true);
    try {
      final asset = await widget.repository.uploadMedia(
        fileName: file.name,
        mimeType: _mimeTypeFromName(file.name),
        bytes: bytes,
      );
      setState(() => _attachments.add(asset));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}

const _quickEmojis = [
  '❤️',
  '😘',
  '😍',
  '🥰',
  '😊',
  '😉',
  '😂',
  '🤣',
  '👍',
  '🙏',
  '🌹',
  '🎉',
  '🥺',
  '😭',
  '😅',
  '🔥',
  '💯',
  '😎',
  '🤗',
  '💕',
  '💖',
  '💗',
  '🌟',
  '✨',
  '🎶',
  '☕',
  '🌙',
  '🎁',
  '💐',
  '😴',
];

class _EmojiBar extends StatelessWidget {
  const _EmojiBar({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _quickEmojis.length,
        itemBuilder: (context, index) {
          final emoji = _quickEmojis[index];
          return InkResponse(
            onTap: () => onSelect(emoji),
            radius: 22,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CalendarTab extends StatefulWidget {
  const _CalendarTab({required this.repository, required this.events});

  final SpaceRepository repository;
  final Stream<Map<String, dynamic>> events;

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab>
    with _RealtimeRefreshMixin<_CalendarTab> {
  late Future<List<CalendarItem>> _events = widget.repository.calendarEvents();
  final _title = TextEditingController();
  DateTime _dateValue = DateTime.now();

  @override
  void initState() {
    super.initState();
    startRealtimeRefresh();
  }

  @override
  Stream<Map<String, dynamic>> get realtimeEvents => widget.events;

  @override
  List<String> get refreshOnEventTypes => const ['calendar.', 'occasion.'];

  @override
  void onRealtimeRefresh() {
    setState(() => _events = widget.repository.calendarEvents());
  }

  @override
  void dispose() {
    stopRealtimeRefresh();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(
          icon: Icons.calendar_month_rounded,
          title: 'التقويم',
          subtitle: 'مواعيدكما ومناسباتكما المشتركة.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'عنوان الموعد',
            prefixIcon: Icon(Icons.event_note_rounded),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.today_rounded),
          title: Text(_date(_dateValue)),
          trailing: IconButton(
            tooltip: 'اختيار تاريخ',
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ),
        FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة الموعد'),
        ),
        const SizedBox(height: 20),
        FutureBuilder<List<CalendarItem>>(
          future: _events,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final events = snapshot.requireData;
            if (events.isEmpty) {
              return const _EmptyLine(
                text: 'لا توجد مواعيد بعد.',
                color: Colors.grey,
              );
            }
            return Column(
              children: [
                for (final event in events)
                  _InfoTile(
                    icon: Icons.event_available_rounded,
                    title: event.title,
                    subtitle: _date(event.startsAt),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _dateValue,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _dateValue = value);
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    await widget.repository.createCalendarEvent(
      title: _title.text,
      startsAt: _dateValue,
    );
    _title.clear();
    setState(() => _events = widget.repository.calendarEvents());
  }
}

class PartnerSearchScreen extends StatefulWidget {
  const PartnerSearchScreen({required this.repository, super.key});

  final PartnershipRepository repository;

  @override
  State<PartnerSearchScreen> createState() => _PartnerSearchScreenState();
}

class _PartnerSearchScreenState extends State<PartnerSearchScreen> {
  final _username = TextEditingController();
  List<PartnerSearchResult> _results = const [];
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final results = await widget.repository.search(_username.text.trim());
      setState(() => _results = results);
    } on ApiException catch (error) {
      setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(String username) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.repository.requestPartnership(username);
      setState(() => _message = 'تم إرسال الطلب.');
    } on ApiException catch (error) {
      setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة شريك')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم الكامل',
              prefixIcon: Icon(Icons.person_search_rounded),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _search,
            icon: const Icon(Icons.search_rounded),
            label: const Text('بحث'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          for (final result in _results)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: result.avatarUrl == null
                      ? null
                      : NetworkImage(result.avatarUrl!),
                  child: result.avatarUrl == null
                      ? const Icon(Icons.person_outline_rounded)
                      : null,
                ),
                title: Text(result.displayName),
                subtitle: Text('@${result.username}'),
                trailing: IconButton(
                  tooltip: 'إرسال طلب',
                  onPressed: result.canReceiveRequests && !_busy
                      ? () => _request(result.username)
                      : null,
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.title, this.icon, this.builder);

  final String title;
  final IconData icon;
  final Widget Function() builder;
}

class _MoreHubTabV2 extends StatelessWidget {
  const _MoreHubTabV2({
    required this.repository,
    required this.partnershipRepository,
    required this.authRepository,
    required this.hasActivePartnership,
    required this.onPartnershipChanged,
    required this.onSignOut,
    this.events,
  });

  final SpaceRepository repository;
  final PartnershipRepository partnershipRepository;
  final AuthRepository authRepository;
  final bool hasActivePartnership;
  final VoidCallback onPartnershipChanged;
  final VoidCallback onSignOut;
  final Stream<Map<String, dynamic>>? events;

  @override
  Widget build(BuildContext context) {
    Widget guarded(String title, IconData icon, Widget Function() page) {
      if (hasActivePartnership) return page();
      return _PartnerRequiredScreen(title: title, icon: icon);
    }

    final items = [
      _MoreItem(
        'الموسيقى',
        Icons.music_note_rounded,
        () => guarded(
          'الموسيقى',
          Icons.music_note_rounded,
          () => _RoomScreen.music(repository: repository, events: events),
        ),
      ),
      _MoreItem(
        'السينما',
        Icons.movie_outlined,
        () => guarded(
          'السينما',
          Icons.movie_outlined,
          () => _RoomScreen.watch(repository: repository, events: events),
        ),
      ),
      _MoreItem(
        'الألبومات',
        Icons.photo_library_outlined,
        () => guarded(
          'الألبومات',
          Icons.photo_library_outlined,
          () => _AlbumsScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'الأمنيات والأهداف',
        Icons.flag_outlined,
        () => guarded(
          'الأمنيات والأهداف',
          Icons.flag_outlined,
          () => _WishesGoalsScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'خريطة الذكريات',
        Icons.map_outlined,
        () => guarded(
          'خريطة الذكريات',
          Icons.map_outlined,
          () => _PlacesScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'القوائم المشتركة',
        Icons.checklist_rounded,
        () => guarded(
          'القوائم المشتركة',
          Icons.checklist_rounded,
          () => _SharedListsScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'المناسبات',
        Icons.event_available_outlined,
        () => guarded(
          'المناسبات',
          Icons.event_available_outlined,
          () => _OccasionsScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'ملخصات العلاقة',
        Icons.insights_rounded,
        () => guarded(
          'ملخصات العلاقة',
          Icons.insights_rounded,
          () => _RelationshipSummaryScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'صباح ومساء',
        Icons.wb_twilight_rounded,
        () => guarded(
          'صباح ومساء',
          Icons.wb_twilight_rounded,
          () => _DailyRitualsScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'الشجرة اليومية',
        Icons.park_outlined,
        () => guarded(
          'الشجرة اليومية',
          Icons.park_outlined,
          () => _TreeScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'كبسولات الوقت',
        Icons.lock_clock_outlined,
        () => guarded(
          'كبسولات الوقت',
          Icons.lock_clock_outlined,
          () => _TimeCapsulesScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'الألعاب',
        Icons.grid_3x3_rounded,
        () => guarded(
          'الألعاب',
          Icons.grid_3x3_rounded,
          () => _GamesScreen(repository: repository),
        ),
      ),
      _MoreItem(
        'الأمان والدعم',
        Icons.shield_outlined,
        () => _SafetyScreen(repository: repository),
      ),
      _MoreItem(
        'الإشعارات',
        Icons.notifications_none_rounded,
        () => _NotificationsScreen(repository: repository),
      ),
      _MoreItem(
        'الملف الشخصي',
        Icons.person_outline_rounded,
        () => _ProfileScreen(repository: repository),
      ),
      _MoreItem(
        'الإعدادات',
        Icons.settings_outlined,
        () => _SettingsScreen(
          repository: repository,
          partnershipRepository: partnershipRepository,
          authRepository: authRepository,
          hasActivePartnership: hasActivePartnership,
          onPartnershipChanged: onPartnershipChanged,
        ),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final item in items)
          ListTile(
            leading: Icon(item.icon),
            title: Text(item.title),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => item.builder())),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout_rounded),
          title: const Text('تسجيل الخروج'),
          onTap: onSignOut,
        ),
      ],
    );
  }
}

class _PartnerRequiredScreen extends StatelessWidget {
  const _PartnerRequiredScreen({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _PartnerRequiredTab(
        icon: icon,
        title: title,
        message:
            'هذه الميزة تتطلب علاقة مفعلة. أضف الشريك ثم أكملا إعداد البداية.',
        onAddPartner: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _DailyRitualsScreen extends StatefulWidget {
  const _DailyRitualsScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_DailyRitualsScreen> createState() => _DailyRitualsScreenState();
}

class _DailyRitualsScreenState extends State<_DailyRitualsScreen> {
  static const _morningType = 'daily.good_morning';
  static const _nightType = 'daily.good_night';

  late Future<_DailyRitualData> _future = _load();
  final _morningMessage = TextEditingController();
  final _nightReflection = TextEditingController();
  bool _ready = false;
  bool _morningEnabled = true;
  bool _nightEnabled = true;
  TimeOfDay _morningTime = const TimeOfDay(hour: 7, minute: 30);
  TimeOfDay _nightTime = const TimeOfDay(hour: 22, minute: 30);
  bool _busy = false;

  @override
  void dispose() {
    _morningMessage.dispose();
    _nightReflection.dispose();
    super.dispose();
  }

  Future<_DailyRitualData> _load() async {
    final summary = await widget.repository.summary();
    final occasions = await widget.repository.occasions();
    final preferences = await widget.repository.notificationPreferences();
    return _DailyRitualData(
      summary: summary,
      nextOccasion: _nextOccasion(occasions),
      preferences: {
        for (final preference in preferences) preference.type: preference,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صباح ومساء')),
      body: FutureBuilder<_DailyRitualData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.requireData;
          if (!_ready) {
            final morning = data.preferences[_morningType];
            final night = data.preferences[_nightType];
            _morningEnabled = morning?.enabled ?? true;
            _nightEnabled = night?.enabled ?? true;
            _morningTime = _timeFromClock(morning?.quietFrom) ?? _morningTime;
            _nightTime = _timeFromClock(night?.quietFrom) ?? _nightTime;
            _ready = true;
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _SectionHeader(
                icon: Icons.wb_twilight_rounded,
                title: 'تجربة يومية اختيارية',
                subtitle: data.summary.daysTogether == null
                    ? 'ابدأا بعادة صغيرة مشتركة.'
                    : 'اليوم ${data.summary.daysTogether} معاً',
              ),
              if (data.nextOccasion != null) ...[
                const SizedBox(height: 12),
                _InfoTile(
                  icon: Icons.event_available_outlined,
                  title: 'المناسبة القادمة',
                  subtitle:
                      '${data.nextOccasion!.title} - ${_date(data.nextOccasion!.date)}',
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                value: _morningEnabled,
                onChanged: (value) => setState(() => _morningEnabled = value),
                title: const Text('تفعيل صباح الخير'),
                subtitle: Text('وقت التذكير ${_clockLabel(_morningTime)}'),
              ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('وقت الصباح'),
                trailing: Text(_clockLabel(_morningTime)),
                onTap: () => _pickTime(true),
              ),
              TextField(
                controller: _morningMessage,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'رسالة تظهر في الصباح',
                  prefixIcon: Icon(Icons.schedule_send_rounded),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _scheduleMorningMessage,
                icon: const Icon(Icons.send_time_extension_rounded),
                label: const Text('جدولة للصباح القادم'),
              ),
              const Divider(height: 32),
              SwitchListTile(
                value: _nightEnabled,
                onChanged: (value) => setState(() => _nightEnabled = value),
                title: const Text('تفعيل قبل النوم'),
                subtitle: Text('وقت التذكير ${_clockLabel(_nightTime)}'),
              ),
              ListTile(
                leading: const Icon(Icons.nightlight_round),
                title: const Text('وقت المساء'),
                trailing: Text(_clockLabel(_nightTime)),
                onTap: () => _pickTime(false),
              ),
              TextField(
                controller: _nightReflection,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'ما أجمل شيء حدث اليوم؟',
                  prefixIcon: Icon(Icons.park_outlined),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _saveNightReflection,
                icon: const Icon(Icons.eco_outlined),
                label: const Text('حفظ كورقة اليوم'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Text('🙂'),
                    label: const Text('هادئ'),
                    onPressed: _busy ? null : () => _setNightMood('calm', '🙂'),
                  ),
                  ActionChip(
                    avatar: const Text('😴'),
                    label: const Text('نعسان'),
                    onPressed: _busy
                        ? null
                        : () => _setNightMood('sleepy', '😴'),
                  ),
                  ActionChip(
                    avatar: const Text('💛'),
                    label: const Text('ممتن'),
                    onPressed: _busy
                        ? null
                        : () => _setNightMood('grateful', '💛'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _busy ? null : _savePreferences,
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ إعدادات التذكير'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickTime(bool morning) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: morning ? _morningTime : _nightTime,
    );
    if (picked == null) return;
    setState(() {
      if (morning) {
        _morningTime = picked;
      } else {
        _nightTime = picked;
      }
    });
  }

  Future<void> _savePreferences() async {
    setState(() => _busy = true);
    try {
      await widget.repository.updateNotificationPreference(
        type: _morningType,
        enabled: _morningEnabled,
        quietFrom: _clockValue(_morningTime),
        quietTo: _clockValue(_morningTime),
      );
      await widget.repository.updateNotificationPreference(
        type: _nightType,
        enabled: _nightEnabled,
        quietFrom: _clockValue(_nightTime),
        quietTo: _clockValue(_nightTime),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات الصباح والمساء.')),
      );
      setState(() {
        _ready = false;
        _future = _load();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scheduleMorningMessage() async {
    final body = _morningMessage.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.scheduleMessage(
        body: body,
        sendAt: _nextDateTime(_morningTime),
      );
      _morningMessage.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت جدولة الرسالة للصباح القادم.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNightReflection() async {
    final body = _nightReflection.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.createTreeLeaf(title: 'قبل النوم', body: body);
      _nightReflection.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ ورقة قبل النوم.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNightMood(String kind, String emoji) async {
    setState(() => _busy = true);
    try {
      await widget.repository.createMood(
        kind: kind,
        emoji: emoji,
        note: 'مزاج نهاية اليوم',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل مزاج نهاية اليوم.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DailyRitualData {
  const _DailyRitualData({
    required this.summary,
    required this.preferences,
    this.nextOccasion,
  });

  final SpaceSummary summary;
  final OccasionItem? nextOccasion;
  final Map<String, NotificationPreferenceModel> preferences;
}

OccasionItem? _nextOccasion(List<OccasionItem> occasions) {
  final now = DateTime.now();
  final upcoming = occasions.where((item) => item.date.isAfter(now)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return upcoming.isEmpty ? null : upcoming.first;
}

TimeOfDay? _timeFromClock(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String _clockValue(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _clockLabel(TimeOfDay value) => _clockValue(value);

DateTime _nextDateTime(TimeOfDay value) {
  final now = DateTime.now();
  var scheduled = DateTime(
    now.year,
    now.month,
    now.day,
    value.hour,
    value.minute,
  );
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

class _RelationshipSummaryScreen extends StatefulWidget {
  const _RelationshipSummaryScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_RelationshipSummaryScreen> createState() =>
      _RelationshipSummaryScreenState();
}

class _RelationshipSummaryScreenState
    extends State<_RelationshipSummaryScreen> {
  String _period = 'month';
  late Future<RelationshipSummaryModel> _future = _load();

  Future<RelationshipSummaryModel> _load() {
    return widget.repository.relationshipSummary(period: _period);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ملخصات العلاقة')),
      body: FutureBuilder<RelationshipSummaryModel>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snapshot.requireData;
          final counts = summary.counts;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SectionHeader(
                        icon: Icons.insights_rounded,
                        title: summary.title,
                        subtitle:
                            '${_date(summary.start)} - ${_date(summary.end)}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _period,
                      items: const [
                        DropdownMenuItem(value: 'week', child: Text('أسبوع')),
                        DropdownMenuItem(value: 'month', child: Text('شهر')),
                        DropdownMenuItem(value: 'year', child: Text('سنة')),
                        DropdownMenuItem(
                          value: 'anniversary',
                          child: Text('ذكرى'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _period = value;
                          _future = _load();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 2.1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _SummaryMetric('الرسائل', counts.messages),
                    _SummaryMetric('الصور', counts.photos),
                    _SummaryMetric('الفيديوهات', counts.videos),
                    _SummaryMetric('أوراق الشجرة', counts.treeLeaves),
                    _SummaryMetric('الأغاني', counts.songs),
                    _SummaryMetric('المشاهدة', counts.watchSessions),
                    _SummaryMetric('الأماكن', counts.places),
                    _SummaryMetric('الأهداف المكتملة', counts.completedGoals),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'المزاجات الأكثر تكراراً',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (summary.topMoods.isEmpty)
                  const _EmptyLine(
                    text: 'لا توجد مزاجات في هذه الفترة.',
                    color: Colors.grey,
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mood in summary.topMoods)
                        Chip(
                          avatar: Text(mood.emoji ?? '•'),
                          label: Text('${mood.kind} (${mood.count})'),
                        ),
                    ],
                  ),
                const SizedBox(height: 18),
                if (summary.importantOccasion != null)
                  _InfoTile(
                    icon: Icons.event_available_outlined,
                    title: 'المناسبة الأهم',
                    subtitle:
                        '${summary.importantOccasion!.title} - ${_date(summary.importantOccasion!.occurredAt)}',
                  ),
                if (summary.highlights.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'ذكريات بارزة',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final highlight in summary.highlights)
                    _InfoTile(
                      icon: Icons.auto_awesome_rounded,
                      title: highlight.title ?? 'ذكرى',
                      subtitle:
                          '${highlight.body ?? ''}  تفاعل: ${highlight.reactions + highlight.comments}',
                    ),
                ],
                const SizedBox(height: 18),
                Text(
                  'الخط الزمني',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (summary.timeline.isEmpty)
                  const _EmptyLine(
                    text: 'لا توجد أحداث في هذه الفترة.',
                    color: Colors.grey,
                  )
                else
                  for (final item in summary.timeline)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timeline_rounded),
                      title: Text(item.title),
                      subtitle: Text(
                        '${_summaryTypeLabel(item.type)} - ${_date(item.occurredAt)}',
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value.toString(),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _summaryTypeLabel(String type) {
  return switch (type) {
    'post' => 'ذكرى',
    'calendar_event' => 'تقويم',
    'mood' => 'مزاج',
    'tree_leaf' => 'ورقة',
    'goal_completed' => 'هدف',
    'place' => 'مكان',
    'time_capsule' => 'كبسولة',
    'occasion' => 'مناسبة',
    _ => type,
  };
}

// ignore: unused_element
class _MoreHubTab extends StatelessWidget {
  const _MoreHubTab({required this.repository, required this.onSignOut});

  final SpaceRepository repository;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MoreItem(
        'الموسيقى',
        Icons.music_note_rounded,
        () => _RoomScreen.music(repository: repository),
      ),
      _MoreItem(
        'السينما',
        Icons.movie_outlined,
        () => _RoomScreen.watch(repository: repository),
      ),
      _MoreItem(
        'الألبومات',
        Icons.photo_library_outlined,
        () => _AlbumsScreen(repository: repository),
      ),
      _MoreItem(
        'الأمنيات والأهداف',
        Icons.flag_outlined,
        () => _WishesGoalsScreen(repository: repository),
      ),
      _MoreItem(
        'خريطة الذكريات',
        Icons.map_outlined,
        () => _PlacesScreen(repository: repository),
      ),
      _MoreItem(
        'القوائم المشتركة',
        Icons.checklist_rounded,
        () => _SharedListsScreen(repository: repository),
      ),
      _MoreItem(
        'الإشعارات',
        Icons.notifications_none_rounded,
        () => _NotificationsScreen(repository: repository),
      ),
      _MoreItem(
        'الملف الشخصي',
        Icons.person_outline_rounded,
        () => _ProfileScreen(repository: repository),
      ),
      _MoreItem(
        'الإعدادات',
        Icons.settings_outlined,
        () =>
            _SettingsScreen(repository: repository, hasActivePartnership: true),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final item in items)
          ListTile(
            leading: Icon(item.icon),
            title: Text(item.title),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => item.builder())),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout_rounded),
          title: const Text('تسجيل الخروج'),
          onTap: onSignOut,
        ),
      ],
    );
  }
}

class _OccasionsScreen extends StatefulWidget {
  const _OccasionsScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_OccasionsScreen> createState() => _OccasionsScreenState();
}

class _OccasionsScreenState extends State<_OccasionsScreen> {
  late Future<List<OccasionItem>> _future = widget.repository.occasions();
  final _title = TextEditingController();
  DateTime _dateValue = DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المناسبات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionHeader(
            icon: Icons.event_available_outlined,
            title: 'المناسبات',
            subtitle: 'احفظوا التواريخ المهمة لتظهر في عالمكما.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'عنوان المناسبة'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.today_rounded),
            title: Text(_date(_dateValue)),
            trailing: IconButton(
              tooltip: 'اختيار تاريخ',
              icon: const Icon(Icons.calendar_month_rounded),
              onPressed: _pickDate,
            ),
          ),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة مناسبة'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<OccasionItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final items = snapshot.requireData;
              if (items.isEmpty) return const Text('لا توجد مناسبات بعد.');
              return Column(
                children: [
                  for (final item in items)
                    ListTile(
                      leading: const Icon(Icons.event_available_outlined),
                      title: Text(item.title),
                      subtitle: Text(_date(item.date)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _dateValue,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _dateValue = value);
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    await widget.repository.createOccasion(
      title: _title.text,
      date: _dateValue,
    );
    _title.clear();
    setState(() => _future = widget.repository.occasions());
  }
}

class _TreeScreen extends StatefulWidget {
  const _TreeScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<_TreeScreen> {
  late Future<List<TreeLeafItem>> _future = widget.repository.allTreeLeaves();
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  bool _writing = false;
  Avatar _avatar = const Avatar();
  String _treeName = 'شجرتنا';

  @override
  void initState() {
    super.initState();
    AvatarStore.load().then((a) {
      if (mounted) setState(() => _avatar = a);
    });
    SharedPreferences.getInstance().then((p) {
      final name = p.getString('tree_name');
      if (name != null && name.trim().isNotEmpty && mounted) {
        setState(() => _treeName = name);
      }
    });
  }

  Future<void> _editAvatar() async {
    final result = await Navigator.of(context).push<Avatar>(
      MaterialPageRoute(builder: (_) => AvatarBuilderScreen(initial: _avatar)),
    );
    if (result != null && mounted) setState(() => _avatar = result);
  }

  Future<void> _renameTree() async {
    final controller = TextEditingController(text: _treeName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم الشجرة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'مثال: شجرة حبّنا'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('tree_name', name);
    if (mounted) setState(() => _treeName = name);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _refresh() =>
      setState(() => _future = widget.repository.allTreeLeaves());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('عالمنا'),
      ),
      body: FutureBuilder<List<TreeLeafItem>>(
        future: _future,
        builder: (context, snapshot) {
          final leaves = snapshot.data ?? const <TreeLeafItem>[];
          return Stack(
            fit: StackFit.expand,
            children: [
              // Full-screen living scene (sky shader + tree + weather + grass).
              _MemoryTreeView(leaves: leaves, onTapLeaf: _showLeaf),

              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),

              // Tree name + memory count (tap the name to rename).
              Positioned(
                top: topPad + 54,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _renameTree,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _treeName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '🍃 ${leaves.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Your avatar living in the world.
              Positioned(
                left: 14,
                bottom: 92 + botPad,
                child: _TreePresence(
                  avatar: _avatar,
                  writing: _writing,
                  onEdit: _editAvatar,
                ),
              ),

              // Add-leaf button → compose sheet.
              Positioned(
                left: 20,
                right: 20,
                bottom: 20 + botPad,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _openCompose,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة ورقة'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: scheme.primary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openCompose() async {
    if (mounted) setState(() => _writing = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionHeader(
                icon: Icons.park_outlined,
                title: 'ورقة جديدة',
                subtitle: 'اكتبوا ذكرى تبقى على الشجرة للأبد.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'عنوان اختياري'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _body,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'نص الورقة'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await _create();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة الورقة'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (mounted) setState(() => _writing = false);
  }

  Future<void> _create() async {
    if (_body.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.createTreeLeaf(
        title: _title.text,
        body: _body.text,
      );
      _title.clear();
      _body.clear();
      _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addContribution(String leafId) async {
    final body = await _promptText(context, 'مساهمة جديدة');
    if (body == null || body.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.addTreeLeafContribution(
        leafId: leafId,
        body: body,
      );
      _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showLeaf(TreeLeafItem leaf) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Row(
                children: [
                  Icon(Icons.eco_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      leaf.title ?? 'ورقة ذكرى',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                leaf.body,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 16),
              if (leaf.contributions.isNotEmpty) ...[
                Text(
                  'المساهمات (${leaf.contributions.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final contribution in leaf.contributions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🍃 '),
                        Expanded(child: Text(contribution.body)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _addContribution(leaf.id);
                },
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('إضافة مساهمة'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// The user's avatar standing by the tree, with a status bubble. Tapping it
// opens the avatar editor.
class _TreePresence extends StatelessWidget {
  const _TreePresence({
    required this.avatar,
    required this.writing,
    required this.onEdit,
  });

  final Avatar avatar;
  final bool writing;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            writing ? 'يكتب ورقة ✍️' : 'أنت هنا 🌳',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A2A22),
            ),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onEdit,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AvatarView(
                avatar: avatar,
                size: 56,
                background: Colors.white,
                ringColor: scheme.primary,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, size: 11, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Interactive, animated memory tree. The trunk/branches are painted and grow
/// in, leaves are laid out with a golden-angle (phyllotaxis) spread so they
/// never overlap, sway gently, and each is tappable to reveal its memory.
class _MemoryTreeView extends StatefulWidget {
  const _MemoryTreeView({required this.leaves, required this.onTapLeaf});

  final List<TreeLeafItem> leaves;
  final void Function(TreeLeafItem leaf) onTapLeaf;

  @override
  State<_MemoryTreeView> createState() => _MemoryTreeViewState();
}

class _MemoryTreeViewState extends State<_MemoryTreeView>
    with TickerProviderStateMixin {
  // A single slow, continuously repeating clock drives the wind and all the
  // ambient motion; a one-shot controller grows the newest additions in.
  late final AnimationController _wind = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  _Forest? _forest;
  String? _forestKey;
  WeatherNow? _weather;
  Timer? _weatherTimer;
  ui.FragmentShader? _skyShader;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _loadShader();
    // Refresh the real weather periodically while the world is open.
    _weatherTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _loadWeather(),
    );
  }

  // Loads the procedural anime-sky shader; on any failure the painter falls
  // back to the gradient sky, so the world always renders.
  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/sky.frag');
      if (mounted) setState(() => _skyShader = program.fragmentShader());
    } catch (_) {
      // keep _skyShader null → gradient fallback
    }
  }

  Future<void> _loadWeather() async {
    final wx = await WeatherService.instance.current();
    if (mounted && wx != null) setState(() => _weather = wx);
  }

  @override
  void didUpdateWidget(covariant _MemoryTreeView old) {
    super.didUpdateWidget(old);
    if (old.leaves.length != widget.leaves.length) {
      _forestKey = null; // regenerate geometry when the memory count changes
      // Gently pulse the grow-in so new leaves/branches sprout without the
      // whole tree collapsing back to nothing.
      _grow.forward(from: 0.7);
    }
  }

  @override
  void dispose() {
    _weatherTimer?.cancel();
    _wind.dispose();
    _grow.dispose();
    super.dispose();
  }

  void _handleTap(Offset local) {
    final forest = _forest;
    if (forest == null) return;
    var best = 30.0; // hit radius (px)
    _LeafInst? hit;
    for (final tree in forest.trees) {
      for (final leaf in tree.memories) {
        final d = (leaf.pos - local).distance;
        if (d < best) {
          best = d;
          hit = leaf;
        }
      }
    }
    if (hit != null && hit.memoryIndex < widget.leaves.length) {
      widget.onTapLeaf(widget.leaves[hit.memoryIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fills whatever space the parent gives it — used full-screen in the world.
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final key =
            '${size.width.round()}x${size.height.round()}'
            '|${widget.leaves.length}';
        if (key != _forestKey) {
          _forest = _buildForest(size, widget.leaves.length);
          _forestKey = key;
        }
        final forest = _forest!;
        return GestureDetector(
          onTapUp: (d) => _handleTap(d.localPosition),
          child: AnimatedBuilder(
            animation: Listenable.merge([_wind, _grow]),
            builder: (context, _) {
              return CustomPaint(
                size: size,
                painter: _ScenePainter(
                  now: DateTime.now(),
                  grow: Curves.easeOutCubic.transform(_grow.value),
                  windPhase: _wind.value * math.pi * 2,
                  forest: forest,
                  weather: _weather,
                  skyShader: _skyShader,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Forest model. Each memory is a single leaf. Leaves fill a branch (50), branches
// fill a tree (20 → 1000 leaves), then a new tree sprouts into the grove. A tree
// grows taller and fuller as it gains branches, so the world grows with the
// couple's memories.
// ---------------------------------------------------------------------------

const int _kLeavesPerBranch = 50;
const int _kBranchesPerTree = 20;
const int _kLeavesPerTree = _kLeavesPerBranch * _kBranchesPerTree; // 1000
const int _kMaxTrees = 5;
const int _kMaxMemoryLeaves = 400; // per-tree cap on distinct memory leaves

class _Seg {
  const _Seg(this.a, this.ctrl, this.b, this.width);
  final Offset a;
  final Offset ctrl;
  final Offset b;
  final double width;
}

class _LeafInst {
  const _LeafInst(this.pos, this.angle, this.shade, this.memoryIndex);
  final Offset pos;
  final double angle;
  final int shade; // 0..2 green shade
  final int memoryIndex; // -1 for filler foliage
}

class _Blob {
  const _Blob(this.c, this.r);
  final Offset c;
  final double r;
}

class _TreeVisual {
  _TreeVisual(
    this.base,
    this.trunkTop,
    this.trunkWidth,
    this.scale,
    this.leafLen,
  );
  final Offset base;
  final Offset trunkTop;
  final double trunkWidth;
  final double scale;
  final double leafLen;
  final List<_Seg> wood = [];
  final List<_Blob> masses = []; // rounded canopy volume
  final List<_LeafInst> foliage = []; // lush filler, not tappable
  final List<_LeafInst> memories = []; // one per memory, tappable
}

class _Forest {
  const _Forest(this.trees, this.newestIndex);
  final List<_TreeVisual> trees;
  final int newestIndex; // memory index of the freshest leaf (-1 if none)
}

// Builds the grove. The last (growing) tree is big and centred; each completed
// tree (1000 memories) shrinks and lines up beside it.
_Forest _buildForest(Size size, int memories) {
  final w = size.width;
  final h = size.height;
  final trees = <_TreeVisual>[];
  final treeCount = memories <= 0
      ? 1
      : ((memories + _kLeavesPerTree - 1) ~/ _kLeavesPerTree).clamp(
          1,
          _kMaxTrees,
        );
  final growingIndex = treeCount - 1;

  for (var ti = 0; ti < treeCount; ti++) {
    final memThis = (memories - ti * _kLeavesPerTree).clamp(0, _kLeavesPerTree);
    final isGrowing = ti == growingIndex;
    Offset base;
    double trunkH;
    double scale;
    if (isGrowing) {
      base = Offset(w * 0.5, h * 0.985);
      trunkH = h * 0.30;
      scale = 1.0;
    } else {
      final c = ti;
      final n = growingIndex;
      final f = n <= 1 ? 0.5 : c / (n - 1);
      base = Offset(w * (0.16 + f * 0.68), h * 0.72);
      trunkH = h * 0.15;
      scale = 0.42;
    }
    trees.add(
      _makeTree(
        base: base,
        trunkH: trunkH,
        scale: scale,
        seed: ti * 9973 + 7,
        memStart: ti * _kLeavesPerTree,
        memCount: memThis,
        big: isGrowing,
      ),
    );
  }
  return _Forest(trees, memories - 1);
}

// A natural tree: a thick trunk splits into a few main boughs that fork
// recursively (curved and thinning), then a dense rounded crown of foliage
// fills the space the boughs reach into — so it reads as a full canopy rather
// than umbrella spokes.
_TreeVisual _makeTree({
  required Offset base,
  required double trunkH,
  required double scale,
  required int seed,
  required int memStart,
  required int memCount,
  required bool big,
}) {
  var s = seed;
  double rnd() {
    s++;
    final x = math.sin(s * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  final trunkTop = Offset(base.dx, base.dy - trunkH);
  final trunkWidth = (big ? 24.0 : 11.0) * scale;
  final leafLen = (big ? 12.0 : 8.0) * scale;
  final tree = _TreeVisual(base, trunkTop, trunkWidth, scale, leafLen);

  final tips = <Offset>[];
  void grow(Offset from, double angle, double length, double width, int depth) {
    final dir = Offset(math.sin(angle), -math.cos(angle));
    final perp = Offset(dir.dy, -dir.dx);
    final curve = (rnd() - 0.5) * 0.4;
    final to = from + dir * length;
    final ctrl = from + dir * (length * 0.5) + perp * (length * curve);
    tree.wood.add(_Seg(from, ctrl, to, width));
    if (depth == 0) {
      tips.add(to);
      return;
    }
    final spread = 0.34 + rnd() * 0.16;
    grow(
      to,
      angle - spread + (rnd() - 0.5) * 0.12,
      length * (0.72 + rnd() * 0.08),
      width * 0.7,
      depth - 1,
    );
    grow(
      to,
      angle + spread + (rnd() - 0.5) * 0.12,
      length * (0.72 + rnd() * 0.08),
      width * 0.7,
      depth - 1,
    );
    if (depth >= 2 && rnd() > 0.35) {
      grow(
        to,
        angle + (rnd() - 0.5) * 0.4,
        length * 0.62,
        width * 0.6,
        depth - 1,
      );
    }
  }

  final mains = big ? 4 : 3;
  final depth = big ? 4 : 3;
  for (var i = 0; i < mains; i++) {
    final f = mains == 1 ? 0.5 : i / (mains - 1);
    final a0 = (f - 0.5) * 1.5 + (rnd() - 0.5) * 0.25;
    grow(trunkTop, a0, trunkH * (0.62 + rnd() * 0.22), trunkWidth * 0.8, depth);
  }

  if (tips.isEmpty) return tree;

  // Crown metrics.
  var sx = 0.0, sy = 0.0, maxY = -1e9;
  for (final t in tips) {
    sx += t.dx;
    sy += t.dy;
    if (t.dy > maxY) maxY = t.dy;
  }
  final cc = Offset(sx / tips.length, sy / tips.length);
  var crownR = 0.0;
  for (final t in tips) {
    final d = (t - cc).distance;
    if (d > crownR) crownR = d;
  }
  crownR += leafLen * 2;
  // Anything below the lowest bough end would just hang over the grass.
  final cullY = maxY + leafLen * 1.4;

  // Directional light: top-left of the crown is brightest (backlit).
  int shadeFor(Offset p) {
    final l = ((cc.dy - p.dy) + (cc.dx - p.dx) * 0.5) / crownR;
    return (((l + 1) / 2) * 4).floor().clamp(0, 3);
  }

  // Soft base masses (blurred by the painter) so the crown reads as a
  // continuous volume rather than a cloud of hard circles.
  final stride = (tips.length / 22).ceil().clamp(1, 999);
  for (var i = 0; i < tips.length; i += stride) {
    tree.masses.add(
      _Blob(tips[i], (big ? 30.0 : 18.0) * scale * (0.8 + rnd() * 0.4)),
    );
  }
  for (var i = 0; i < (big ? 8 : 4); i++) {
    final ang = rnd() * math.pi * 2;
    final rr = math.sqrt(rnd()) * crownR * 0.6;
    final p = cc + Offset(math.cos(ang) * rr, math.sin(ang) * rr * 0.8);
    if (p.dy <= cullY) {
      tree.masses.add(_Blob(p, (big ? 34.0 : 20.0) * scale));
    }
  }

  // Dense leaves clustered around each bough end — tied to the branches, so
  // nothing floats free, and directionally shaded for depth.
  final per = big ? 8 : 5;
  for (final tip in tips) {
    for (var k = 0; k < per; k++) {
      final p =
          tip +
          Offset(
            (rnd() - 0.5) * leafLen * 2.6,
            (rnd() - 0.5) * leafLen * 2.6 - leafLen * 0.4,
          );
      if (p.dy > cullY) continue;
      final v = p - cc;
      final outward = math.atan2(v.dx, -v.dy) + (rnd() - 0.5) * 0.9;
      tree.foliage.add(_LeafInst(p, outward, shadeFor(p), -1));
    }
  }

  // Memory leaves spread evenly across the bough ends, on the canopy surface.
  final show = memCount.clamp(0, _kMaxMemoryLeaves);
  for (var i = 0; i < show; i++) {
    final tip = tips[(i * tips.length ~/ math.max(1, show)) % tips.length];
    final v = tip - cc;
    final vlen = v.distance == 0 ? 1.0 : v.distance;
    final out = v / vlen;
    final p =
        tip +
        out * (leafLen * 0.7) +
        Offset((rnd() - 0.5) * leafLen, (rnd() - 0.5) * leafLen);
    final w = p - cc;
    final outward = math.atan2(w.dx, -w.dy);
    tree.memories.add(_LeafInst(p, outward, i % 3, memStart + i));
  }

  return tree;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.now,
    required this.grow,
    required this.windPhase,
    required this.forest,
    required this.weather,
    required this.skyShader,
  });

  final DateTime now;
  final double grow;
  final double windPhase;
  final _Forest forest;
  final WeatherNow? weather;
  final ui.FragmentShader? skyShader;

  // Four foliage tones, dark → light, chosen per leaf by how much light it
  // catches (top-left of the crown is brightest) for painterly, shaded depth.
  static const _leafTones = [
    Color(0xFF10380F),
    Color(0xFF1B5E20),
    Color(0xFF2E7D32),
    Color(0xFF5AA02C),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizonY = h * 0.62;
    final hour = now.hour + now.minute / 60 + now.second / 3600;
    final t = now.millisecondsSinceEpoch / 1000.0;
    final isDay = hour >= 6 && hour < 18;
    final frac =
        (isDay ? (hour - 6) / 12 : ((hour < 6 ? hour + 24 : hour) - 18) / 12)
            .clamp(0.0, 1.0);
    final elevation = math.sin(frac * math.pi);
    final dayLight = isDay ? elevation : 0.0;
    final warm = (1 - elevation).clamp(0.0, 1.0); // 1 near sunrise/sunset

    // --- Real weather → scene parameters ---
    final wx = weather;
    final overcast = wx == null
        ? 0.12
        : switch (wx.condition) {
            WeatherCondition.clear => 0.0,
            WeatherCondition.partlyCloudy => 0.2 + wx.cloudCover * 0.25,
            WeatherCondition.overcast => 0.85,
            WeatherCondition.fog => 0.7,
            WeatherCondition.rain => 0.85,
            WeatherCondition.snow => 0.7,
            WeatherCondition.storm => 1.0,
          };
    final cloudCover = wx?.cloudCover ?? 0.18;
    final isRain =
        wx?.condition == WeatherCondition.rain ||
        wx?.condition == WeatherCondition.storm;
    final isSnow = wx?.condition == WeatherCondition.snow;
    final isFog = wx?.condition == WeatherCondition.fog;

    // Sun / moon centre along a real-time arc (the sky shader needs it too).
    final cx = w * 0.12 + (w * 0.76) * frac;
    final cy = horizonY - elevation * (horizonY - h * 0.10);

    // --- Sky colours (time gradient, greyed by cloud cover) ---
    final sky = _skyColors(hour);
    final grey = isDay ? const Color(0xFFAAB2BB) : const Color(0xFF39414B);
    var top = Color.lerp(sky.$1, grey, overcast * 0.72)!;
    var bot = Color.lerp(
      sky.$2,
      isDay ? const Color(0xFFC7CDD4) : const Color(0xFF2A303A),
      overcast * 0.68,
    )!;
    if (isSnow) {
      top = Color.lerp(top, const Color(0xFFD7DEE6), 0.4)!;
      bot = Color.lerp(bot, const Color(0xFFEDF1F5), 0.4)!;
    }
    final bloomColor = Color.lerp(
      const Color(0xFFFFF4CC),
      const Color(0xFFFF9248),
      warm,
    )!;

    final shader = skyShader;
    if (shader != null) {
      // Procedural anime sky (gradient + volumetric clouds + bloom + haze).
      final cloudParam = math.max(cloudCover, overcast).clamp(0.0, 1.0);
      shader
        ..setFloat(0, w)
        ..setFloat(1, h)
        ..setFloat(2, t % 100000.0)
        ..setFloat(3, cx)
        ..setFloat(4, cy)
        ..setFloat(5, isDay ? 0.0 : 1.0)
        ..setFloat(6, overcast.clamp(0.0, 1.0))
        ..setFloat(7, cloudParam)
        ..setFloat(8, top.r)
        ..setFloat(9, top.g)
        ..setFloat(10, top.b)
        ..setFloat(11, bot.r)
        ..setFloat(12, bot.g)
        ..setFloat(13, bot.b)
        ..setFloat(14, bloomColor.r)
        ..setFloat(15, bloomColor.g)
        ..setFloat(16, bloomColor.b)
        ..setFloat(17, horizonY);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = shader);
    } else {
      // Fallback: plain gradient sky + a warm horizon bloom.
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bot],
          ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
      final bloomAlpha =
          (isDay ? 0.42 + 0.5 * warm : 0.14) * (1 - overcast * 0.6);
      if (bloomAlpha > 0.02) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w, h),
          Paint()
            ..shader = RadialGradient(
              center: Alignment(0, (horizonY / h) * 2 - 1),
              radius: 0.95,
              colors: [
                bloomColor.withValues(alpha: bloomAlpha),
                bloomColor.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromLTWH(0, 0, w, h)),
        );
      }
    }

    // --- Stars (night, hidden by cloud) ---
    final starOpacity =
        (isDay ? 0.0 : (0.45 + 0.55 * elevation)) * (1 - overcast);
    if (starOpacity > 0.03) {
      final sp = Paint();
      for (var i = 0; i < 46; i++) {
        final sx = ((i * 71) % 100) / 100 * w;
        final sy = ((i * 137) % 58) / 100 * h;
        final twinkle = 0.5 + 0.5 * math.sin(t * 2 + i);
        sp.color = Colors.white.withValues(
          alpha: (starOpacity * (0.35 + 0.65 * twinkle)).clamp(0.0, 1.0),
        );
        canvas.drawCircle(Offset(sx, sy), 0.7 + (i % 3) * 0.5, sp);
      }
    }

    // --- Sun / Moon disk (drawn over the sky) ---
    if (isDay) {
      if (dayLight > 0.18 && overcast < 0.4) {
        canvas.save();
        canvas.translate(cx, cy);
        final ray = Paint()
          ..color = const Color(0xFFFFF3C4).withValues(alpha: 0.06 * dayLight);
        for (var i = 0; i < 7; i++) {
          final a = t * 0.05 + i * (math.pi * 2 / 7);
          final dir = Offset(math.sin(a), math.cos(a));
          final perp = Offset(dir.dy, -dir.dx);
          final far = dir * (h * 0.9);
          canvas.drawPath(
            Path()
              ..moveTo(-perp.dx * 6, -perp.dy * 6)
              ..lineTo(perp.dx * 6, perp.dy * 6)
              ..lineTo(far.dx + perp.dx * 26, far.dy + perp.dy * 26)
              ..lineTo(far.dx - perp.dx * 26, far.dy - perp.dy * 26)
              ..close(),
            ray,
          );
        }
        canvas.restore();
      }
      final sunA = (1 - overcast * 0.9).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(cx, cy),
        46,
        Paint()..color = const Color(0xFFFFF3B0).withValues(alpha: 0.14 * sunA),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        32,
        Paint()..color = const Color(0xFFFFE082).withValues(alpha: 0.28 * sunA),
      );
      if (overcast < 0.8) {
        canvas.drawCircle(
          Offset(cx, cy),
          21,
          Paint()
            ..color = Color.lerp(
              const Color(0xFFFFD54F),
              const Color(0xFFFF7043),
              warm * 0.5,
            )!.withValues(alpha: sunA),
        );
        canvas.drawCircle(
          Offset(cx - 5, cy - 6),
          13,
          Paint()
            ..color = const Color(0xFFFFF59D).withValues(alpha: 0.7 * sunA),
        );
      }
    } else {
      final moonA = (1 - overcast * 0.85).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(cx, cy),
        30,
        Paint()..color = Colors.white.withValues(alpha: 0.12 * moonA),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        18,
        Paint()..color = const Color(0xFFECEFF1).withValues(alpha: moonA),
      );
      final crater = Paint()
        ..color = const Color(0xFFB0BEC5).withValues(alpha: 0.6 * moonA);
      canvas.drawCircle(Offset(cx - 6, cy - 4), 3.5, crater);
      canvas.drawCircle(Offset(cx + 5, cy + 3), 2.5, crater);
      canvas.drawCircle(Offset(cx + 2, cy - 6), 2, crater);
    }

    // --- Clouds (fallback only; the shader draws its own volumetric clouds) ---
    if (skyShader == null) {
      final cloudN = overcast > 0.55 ? 7 : (2 + (cloudCover * 4).round());
      final cloudTint = overcast > 0.5
          ? Color.lerp(
              const Color(0xFFC9D0D8),
              const Color(0xFF8A93A0),
              overcast,
            )!
          : (isDay ? Colors.white : const Color(0xFFB9C4E0));
      final cloudBase = (isDay ? 0.9 : 0.3) * (0.5 + 0.5 * (overcast + 0.4));
      for (var i = 0; i < cloudN; i++) {
        final speed = 5.0 + i * 2.4;
        final span = w + 160;
        final x = ((t * (speed / 6) + i * 74) % span) - 80;
        final y = h * (0.08 + (i % 4) * 0.09);
        _cloud(
          canvas,
          Offset(x, y),
          (overcast > 0.55 ? 1.3 : 1.0) - (i % 4) * 0.14,
          cloudTint.withValues(
            alpha: (cloudBase * (0.9 - (i % 4) * 0.12)).clamp(0.0, 1.0),
          ),
        );
      }
    }

    // --- Birds (clear days only) ---
    if (dayLight > 0.15 && overcast < 0.5) {
      final birdPaint = Paint()
        ..color = const Color(0xFF37474F).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 4; i++) {
        final bx = ((t * 14 + i * 70) % (w + 80)) - 40;
        final by = h * (0.16 + (i % 2) * 0.05) + math.sin(t * 0.6 + i) * 4;
        final flap = 3 + 2.5 * math.sin(t * 6 + i);
        canvas.drawPath(
          Path()
            ..moveTo(bx - 6, by)
            ..quadraticBezierTo(bx - 3, by - flap, bx, by)
            ..quadraticBezierTo(bx + 3, by - flap, bx + 6, by),
          birdPaint,
        );
      }
    }

    // --- Atmospheric haze at the horizon (fallback only) ---
    if (skyShader == null) {
      canvas.drawRect(
        Rect.fromLTWH(0, horizonY - h * 0.10, w, h * 0.20),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              bloomColor.withValues(alpha: 0),
              bloomColor.withValues(
                alpha: (0.16 + overcast * 0.12) * (isDay ? 1 : 0.4),
              ),
              bloomColor.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(0, horizonY - h * 0.10, w, h * 0.20)),
      );
    }

    // --- Layered hills for depth ---
    Color hill(Color c) => Color.lerp(c, grey, overcast * 0.35)!;
    final farHill = Path()
      ..moveTo(0, horizonY + 6)
      ..quadraticBezierTo(w * 0.35, horizonY - 20, w * 0.7, horizonY)
      ..quadraticBezierTo(w * 0.9, horizonY + 10, w, horizonY - 6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(farHill, Paint()..color = hill(const Color(0xFF9CCC65)));
    final backHill = Path()
      ..moveTo(0, horizonY + 20)
      ..quadraticBezierTo(w * 0.3, horizonY - 6, w * 0.6, horizonY + 16)
      ..quadraticBezierTo(w * 0.85, horizonY + 30, w, horizonY + 6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(backHill, Paint()..color = hill(const Color(0xFF7CB342)));
    final frontHill = Path()
      ..moveTo(0, horizonY + 46)
      ..quadraticBezierTo(w * 0.25, horizonY + 18, w * 0.5, horizonY + 48)
      ..quadraticBezierTo(w * 0.8, horizonY + 76, w, horizonY + 42)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      frontHill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            hill(const Color(0xFF5C8F2E)),
            hill(const Color(0xFF33691E)),
          ],
        ).createShader(Rect.fromLTWH(0, horizonY + 42, w, h - horizonY - 42)),
    );

    // --- Trees (farthest first, front tree last), with backlit rim ---
    final rim = ((isDay ? 0.3 + 0.6 * warm : 0.14) * (1 - overcast * 0.6))
        .clamp(0.0, 1.0);
    final order = List<int>.generate(forest.trees.length, (i) => i)
      ..sort(
        (a, b) => forest.trees[a].base.dy.compareTo(forest.trees[b].base.dy),
      );
    Offset? newestPos;
    double newestAng = 0;
    for (final ti in order) {
      final tr = forest.trees[ti];
      final n = _paintTree(canvas, tr, t, rim, bloomColor);
      if (n != null) {
        newestPos = n.$1;
        newestAng = n.$2;
      }
    }
    if (newestPos != null) {
      canvas.drawCircle(
        newestPos,
        11,
        Paint()..color = const Color(0xFFFFF176).withValues(alpha: 0.5),
      );
      final leafPath = Path();
      _addLeaf(leafPath, newestPos, newestAng, 15 * grow);
      canvas.drawPath(leafPath, Paint()..color = const Color(0xFFD4E157));
      canvas.drawCircle(
        newestPos,
        2.4,
        Paint()..color = Colors.white.withValues(alpha: 0.95),
      );
    }

    // --- Dense meadow grass: filled tapered blades, drawn far→near, with
    // sunlit spines so it reads as real grass rather than flat strokes. ---
    final bandTop = horizonY + 40;
    const gPal = [
      Color(0xFF2E7D32),
      Color(0xFF388E3C),
      Color(0xFF43A047),
      Color(0xFF4E7A2E),
    ];
    const blades = 400;
    for (var i = 0; i < blades; i++) {
      final depth = i / blades; // 0 far (top) … 1 near (bottom)
      final gx =
          ((i * 71) % blades) / blades * (w + 24) - 12 + ((i * 37 % 13) - 6);
      final gy = bandTop + depth * (h - bandTop) + 4;
      final hgt = 7 + depth * depth * 32;
      final sway =
          math.sin(windPhase * 1.1 + i * 0.7 + depth * 2) * (2 + depth * 5);
      final wBlade = 0.8 + depth * 2.4;
      final tipX = gx + sway;
      final tipY = gy - hgt;
      final col = Color.lerp(
        const Color(0xFF1B5E20),
        gPal[i % gPal.length],
        0.25 + depth * 0.75,
      )!;
      canvas.drawPath(
        Path()
          ..moveTo(gx - wBlade, gy)
          ..quadraticBezierTo(
            gx + sway * 0.4 - wBlade * 0.3,
            gy - hgt * 0.55,
            tipX,
            tipY,
          )
          ..quadraticBezierTo(
            gx + sway * 0.4 + wBlade * 0.3,
            gy - hgt * 0.55,
            gx + wBlade,
            gy,
          )
          ..close(),
        Paint()..color = col,
      );
      if (i.isEven) {
        canvas.drawPath(
          Path()
            ..moveTo(gx, gy)
            ..quadraticBezierTo(gx + sway * 0.5, gy - hgt * 0.6, tipX, tipY),
          Paint()
            ..color = Color.lerp(
              col,
              const Color(0xFF9CCC65),
              0.5,
            )!.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // --- Red poppies, clustered to the left like a real meadow ---
    for (var i = 0; i < 16; i++) {
      final leftBias = i < 9
          ? 0.04 + (i / 9) * 0.42
          : 0.5 + ((i - 9) / 7) * 0.46;
      final fx = leftBias * w + ((i * 29 % 17) - 8);
      final depth = 0.45 + (i * 11 % 50) / 100;
      final fy = bandTop + depth * (h - bandTop);
      final s = math.sin(windPhase + i) * 2;
      final r = 2.6 + depth * 1.6;
      canvas.drawLine(
        Offset(fx, fy + 8),
        Offset(fx + s, fy),
        Paint()
          ..color = const Color(0xFF2E5E1E)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      final petal = Paint()..color = const Color(0xFFD32F2F);
      canvas.drawCircle(Offset(fx - r * 0.7 + s, fy - r * 0.5), r, petal);
      canvas.drawCircle(Offset(fx + r * 0.9 + s, fy - r * 0.5), r * 0.9, petal);
      canvas.drawCircle(Offset(fx + s, fy - r * 1.2), r * 0.9, petal);
      canvas.drawCircle(
        Offset(fx + s, fy),
        r * 1.05,
        Paint()..color = const Color(0xFFE53935),
      );
      canvas.drawCircle(
        Offset(fx + s, fy - r * 0.3),
        r * 0.35,
        Paint()..color = const Color(0xFF311B1B),
      );
    }

    // --- Things drifting on the breeze: leaves + a few flying pages ---
    if (!isSnow) {
      for (var i = 0; i < 8; i++) {
        final prog = (t * 0.05 + i * 0.13) % 1.0;
        final fx =
            w * (0.1 + 0.8 * ((i * 0.41) % 1.0)) +
            math.sin(t * 0.8 + i) * 26 * (0.4 + prog);
        final fy = -14 + prog * (h + 28);
        final fa = t * 1.3 + i;
        if (i % 3 == 0) {
          canvas.save();
          canvas.translate(fx, fy);
          canvas.rotate(fa * 0.5);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 9, height: 12),
              const Radius.circular(1.5),
            ),
            Paint()..color = const Color(0xFFF3ECD9).withValues(alpha: 0.9),
          );
          canvas.restore();
        } else {
          final path = Path();
          _addLeaf(path, Offset(fx, fy), fa, 9);
          canvas.drawPath(
            path,
            Paint()
              ..color =
                  (i.isEven ? const Color(0xFF7CB342) : const Color(0xFFC98A3A))
                      .withValues(alpha: 0.85),
          );
        }
      }
    }

    // --- Fireflies (clear nights) ---
    if (!isDay && overcast < 0.6) {
      final tr = forest.trees.isNotEmpty ? forest.trees.first : null;
      final cxT = tr?.trunkTop.dx ?? w / 2;
      final cyT = tr?.trunkTop.dy ?? h * 0.4;
      for (var i = 0; i < 16; i++) {
        final fx =
            cxT + math.sin(t * 0.5 + i * 1.3) * (w * 0.34) + (i % 5 - 2) * 8;
        final fy = cyT - 20 + math.cos(t * 0.4 + i) * 44 + (i % 3) * 12;
        final pulse = (0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 3 + i))).clamp(
          0.0,
          1.0,
        );
        canvas.drawCircle(
          Offset(fx, fy),
          4,
          Paint()
            ..color = const Color(0xFFFFF59D).withValues(alpha: 0.18 * pulse),
        );
        canvas.drawCircle(
          Offset(fx, fy),
          1.6,
          Paint()
            ..color = const Color(0xFFFFF176).withValues(alpha: 0.95 * pulse),
        );
      }
    }

    // --- Rain ---
    if (isRain) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF5B6B7A).withValues(alpha: 0.14),
      );
      final rainPaint = Paint()
        ..color = const Color(0xFFB3E5FC).withValues(alpha: 0.5)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      final drops = wx?.condition == WeatherCondition.storm ? 90 : 60;
      for (var i = 0; i < drops; i++) {
        final rx = (i * 53 % 100) / 100 * w + math.sin(t + i) * 2;
        final speed = 240 + (i % 5) * 50;
        final ry = ((t * speed + i * 37) % (h + 40)) - 20;
        canvas.drawLine(Offset(rx, ry), Offset(rx - 3, ry + 12), rainPaint);
      }
    }

    // --- Snow ---
    if (isSnow) {
      final snow = Paint()..color = Colors.white.withValues(alpha: 0.85);
      for (var i = 0; i < 70; i++) {
        final sx = (i * 53 % 100) / 100 * w + math.sin(t * 0.6 + i) * 10;
        final sy = ((t * 40 + i * 29) % (h + 20)) - 10;
        canvas.drawCircle(Offset(sx, sy), 1.2 + (i % 3) * 0.6, snow);
      }
    }

    // --- Fog veil ---
    if (isFog) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = Colors.white.withValues(alpha: 0.10),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, horizonY - 30, w, 90),
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
    }
  }

  // Draws one tree with wind sway; returns the swayed pos/angle of its freshest
  // leaf so the caller can glow it on top.
  (Offset, double)? _paintTree(
    Canvas canvas,
    _TreeVisual tr,
    double t,
    double rim,
    Color rimColor,
  ) {
    final trunkH = tr.base.dy - tr.trunkTop.dy;
    Offset sway(Offset p) {
      final hf = ((tr.base.dy - p.dy) / (trunkH <= 0 ? 1 : trunkH)).clamp(
        0.0,
        1.5,
      );
      final amp = 4.0 * tr.scale;
      final dx =
          amp * hf * math.sin(windPhase + p.dy * 0.02 + tr.base.dx * 0.01);
      return Offset(p.dx + dx, p.dy);
    }

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(tr.base.dx, tr.base.dy + 4),
        width: 120 * tr.scale * grow,
        height: 18 * tr.scale * grow,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    final top = sway(tr.trunkTop);
    final tw = tr.trunkWidth * grow;
    final ttw = tw * 0.35;
    final trunkPath = Path()
      ..moveTo(tr.base.dx - tw, tr.base.dy)
      ..quadraticBezierTo(
        tr.base.dx - tw * 0.4,
        (tr.base.dy + top.dy) / 2,
        top.dx - ttw,
        top.dy,
      )
      ..lineTo(top.dx + ttw, top.dy)
      ..quadraticBezierTo(
        tr.base.dx + tw * 0.4,
        (tr.base.dy + top.dy) / 2,
        tr.base.dx + tw,
        tr.base.dy,
      )
      ..close();
    // A backlit trunk is darker with a warm rim on the lit edge.
    canvas.drawPath(
      trunkPath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color.lerp(const Color(0xFF5D4433), rimColor, rim * 0.5)!,
                const Color(0xFF4A342A),
                const Color(0xFF3B2A22),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(
              Rect.fromLTRB(
                tr.base.dx - tw,
                top.dy,
                tr.base.dx + tw,
                tr.base.dy,
              ),
            ),
    );

    final branchDark = Paint()
      ..color = const Color(0xFF3B2A22)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final branchLight = Paint()
      ..color = Color.lerp(const Color(0xFF6D4C41), rimColor, rim * 0.6)!
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final seg in tr.wood) {
      final a = sway(seg.a);
      final ctrl = sway(seg.ctrl);
      final b = sway(seg.b);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);
      branchDark.strokeWidth = (seg.width * grow).clamp(0.6, 40);
      canvas.drawPath(path, branchDark);
      branchLight.strokeWidth = (seg.width * grow * 0.4).clamp(0.3, 20);
      canvas.drawPath(path, branchLight);
    }

    // Soft, blurred base masses → a continuous canopy volume (kills the flat
    // hard-circle "cartoon" look). Dark underside, lighter top-left.
    final blurBase = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * tr.scale + 2)
      ..color = const Color(0xFF123A12);
    final blurTop = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * tr.scale + 2)
      ..color = const Color(0xFF2E7D32).withValues(alpha: 0.85);
    for (final b in tr.masses) {
      final cc = sway(b.c);
      final r = b.r * grow;
      canvas.drawCircle(cc, r, blurBase);
      canvas.drawCircle(cc.translate(-r * 0.3, -r * 0.36), r * 0.6, blurTop);
    }

    final leafLen = tr.leafLen * grow;
    double flutter(Offset base) =>
        0.20 * math.sin(windPhase * 1.6 + base.dx * 0.06 + base.dy * 0.03);

    // Textured foliage: thousands of small leaves in four light-shaded tones so
    // the canopy reads as real, backlit leaves rather than solid blobs.
    final tonePaths = [Path(), Path(), Path(), Path()];
    final hiPath = Path();
    for (final leaf in tr.foliage) {
      final p = sway(leaf.pos);
      final a = leaf.angle + flutter(leaf.pos);
      _addLeaf(tonePaths[leaf.shade], p, a, leafLen);
      if (leaf.shade == 3) {
        final hp = Offset(
          p.dx + math.sin(a) * leafLen * 0.2,
          p.dy - math.cos(a) * leafLen * 0.2,
        );
        _addLeaf(hiPath, hp, a, leafLen * 0.5);
      }
    }
    for (var s = 0; s < 4; s++) {
      canvas.drawPath(tonePaths[s], Paint()..color = _leafTones[s]);
    }
    // Warm, backlit rim highlight on the brightest (top) leaves.
    canvas.drawPath(
      hiPath,
      Paint()
        ..color = Color.lerp(
          const Color(0xFFAED581),
          rimColor,
          rim * 0.8,
        )!.withValues(alpha: 0.9),
    );

    // Memory leaves — bright lime leaves on the surface, each marked by a small
    // gently-pulsing light so it clearly reads as tappable, without being noisy.
    const memShades = [Color(0xFF9CCC65), Color(0xFFAED581), Color(0xFFC5E1A5)];
    final memLen = leafLen * 1.3;
    final pulse = 0.5 + 0.5 * math.sin(windPhase + tr.base.dx * 0.01);
    final memPaths = [Path(), Path(), Path()];
    final dots = <Offset>[];
    (Offset, double)? newest;
    for (final m in tr.memories) {
      final p = sway(m.pos);
      final a = m.angle + flutter(m.pos);
      _addLeaf(memPaths[m.shade], p, a, memLen);
      // marker sits near the leaf tip
      dots.add(
        Offset(
          p.dx + math.sin(a) * memLen * 0.5,
          p.dy - math.cos(a) * memLen * 0.5,
        ),
      );
      if (m.memoryIndex == forest.newestIndex) newest = (p, a);
    }
    for (var s = 0; s < 3; s++) {
      canvas.drawPath(memPaths[s], Paint()..color = memShades[s]);
    }
    final glow = Paint()
      ..color = const Color(0xFFFFF59D).withValues(alpha: 0.20 + 0.18 * pulse);
    final core = Paint()
      ..color = Colors.white.withValues(alpha: 0.7 + 0.25 * pulse);
    for (final d in dots) {
      canvas.drawCircle(d, (memLen * 0.42) * (0.9 + 0.2 * pulse), glow);
      canvas.drawCircle(d, 1.8 * tr.scale + 0.6, core);
    }
    return newest;
  }

  // Appends one leaf polygon (points up from origin, rotated by [angle]) to a
  // shared [path] so many leaves fill in a single draw call.
  void _addLeaf(Path path, Offset pos, double angle, double len) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    final wid = len * 0.36;
    Offset p(double x, double y) =>
        Offset(pos.dx + x * c - y * s, pos.dy + x * s + y * c);
    final base = p(0, 0);
    final right = p(wid, -len * 0.45);
    final tip = p(0, -len);
    final left = p(-wid, -len * 0.45);
    path
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(right.dx, right.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(left.dx, left.dy, base.dx, base.dy)
      ..close();
  }

  void _cloud(Canvas canvas, Offset c, double scale, Color color) {
    final p = Paint()..color = color;
    canvas.drawCircle(c, 16 * scale, p);
    canvas.drawCircle(c.translate(16 * scale, 4 * scale), 13 * scale, p);
    canvas.drawCircle(c.translate(-16 * scale, 5 * scale), 12 * scale, p);
    canvas.drawCircle(c.translate(6 * scale, -6 * scale), 12 * scale, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          c.dx - 22 * scale,
          c.dy + 2 * scale,
          44 * scale,
          12 * scale,
        ),
        Radius.circular(8 * scale),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) => true;
}

// Sky top/bottom colours interpolated across the day by hour (0..24).
(Color, Color) _skyColors(double hour) {
  const keys = <(double, Color, Color)>[
    (0.0, Color(0xFF0A0E23), Color(0xFF15233F)),
    (5.0, Color(0xFF243B6B), Color(0xFF7C6A86)),
    (7.0, Color(0xFF8FC5F0), Color(0xFFFBE2B0)),
    (12.0, Color(0xFF4AA0E6), Color(0xFFCDEBFF)),
    (17.0, Color(0xFF6FB2E6), Color(0xFFFBD9A0)),
    (19.0, Color(0xFFE86A48), Color(0xFFF4A66E)),
    (21.0, Color(0xFF0A0E23), Color(0xFF15233F)),
    (24.0, Color(0xFF0A0E23), Color(0xFF15233F)),
  ];
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i];
    final b = keys[i + 1];
    if (hour >= a.$1 && hour <= b.$1) {
      final t = (hour - a.$1) / (b.$1 - a.$1);
      return (Color.lerp(a.$2, b.$2, t)!, Color.lerp(a.$3, b.$3, t)!);
    }
  }
  return (keys.first.$2, keys.first.$3);
}

class _TimeCapsulesScreen extends StatefulWidget {
  const _TimeCapsulesScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_TimeCapsulesScreen> createState() => _TimeCapsulesScreenState();
}

class _TimeCapsulesScreenState extends State<_TimeCapsulesScreen> {
  late Future<List<TimeCapsuleItem>> _future = widget.repository.timeCapsules();
  final _title = TextEditingController();
  final _body = TextEditingController();
  DateTime _opensAt = DateTime.now().add(const Duration(days: 30));

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كبسولات الوقت')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionHeader(
            icon: Icons.lock_clock_outlined,
            title: 'كبسولة جديدة',
            subtitle: 'رسالة محفوظة لا تفتح إلا في تاريخ تختارانه.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'العنوان'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'المحتوى'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_open_outlined),
            title: Text('تفتح في ${_date(_opensAt)}'),
            trailing: IconButton(
              tooltip: 'اختيار تاريخ',
              icon: const Icon(Icons.calendar_month_rounded),
              onPressed: _pickDate,
            ),
          ),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
            label: const Text('حفظ كبسولة'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<TimeCapsuleItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final items = snapshot.requireData;
              if (items.isEmpty) return const Text('لا توجد كبسولات بعد.');
              return Column(
                children: [
                  for (final item in items)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          item.opened
                              ? Icons.lock_open_rounded
                              : Icons.lock_clock_outlined,
                        ),
                        title: Text(item.title),
                        subtitle: Text(
                          item.body?.isNotEmpty == true
                              ? item.body!
                              : item.locked
                              ? 'تفتح في ${_date(item.opensAt)}'
                              : 'جاهزة للفتح',
                        ),
                        trailing: item.opened
                            ? null
                            : FilledButton.tonalIcon(
                                onPressed: item.canOpen
                                    ? () => _openCapsule(item.id)
                                    : null,
                                icon: const Icon(Icons.lock_open_outlined),
                                label: const Text('فتح'),
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _opensAt,
      firstDate: DateTime.now(),
      lastDate: DateTime(2200),
    );
    if (value != null) setState(() => _opensAt = value);
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    await widget.repository.createTimeCapsule(
      title: _title.text,
      body: _body.text,
      opensAt: _opensAt,
    );
    _title.clear();
    _body.clear();
    setState(() => _future = widget.repository.timeCapsules());
  }

  Future<void> _openCapsule(String id) async {
    try {
      await widget.repository.openTimeCapsule(id);
      setState(() => _future = widget.repository.timeCapsules());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _SafetyScreen extends StatefulWidget {
  const _SafetyScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<_SafetyScreen> {
  final _reason = TextEditingController();
  final _details = TextEditingController();
  final _blockReason = TextEditingController();
  late final Future<StorageUsageSummary> _storageFuture = widget.repository
      .storageUsage();
  late Future<List<BlockedUserModel>> _blockedFuture = widget.repository
      .blockedUsers();
  String? _message;
  bool _blocking = false;

  @override
  void dispose() {
    _reason.dispose();
    _details.dispose();
    _blockReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأمان والدعم')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionHeader(
            icon: Icons.shield_outlined,
            title: 'الأمان والدعم',
            subtitle: 'تصدير بياناتك، إرسال بلاغ، أو حذف الحساب.',
          ),
          const SizedBox(height: 16),
          FutureBuilder<StorageUsageSummary>(
            future: _storageFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              final usage = snapshot.requireData;
              return _InfoTile(
                icon: Icons.storage_outlined,
                title: 'مساحة التخزين المستخدمة',
                subtitle:
                    'الحساب ${_formatBytes(usage.user?.usedBytes ?? 0)} - العالم ${_formatBytes(usage.partnership?.usedBytes ?? 0)}',
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'سبب البلاغ'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _details,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'تفاصيل اختيارية'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _report,
            icon: const Icon(Icons.report_outlined),
            label: const Text('إرسال بلاغ'),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(
            icon: Icons.block,
            title: 'الحظر',
            subtitle:
                'احظر الشريك الحالي لمنع طلبات الارتباط المستقبلية بينكما.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _blockReason,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'سبب الحظر اختياري'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _blocking ? null : _blockPartner,
            icon: const Icon(Icons.block),
            label: Text(_blocking ? 'جار الحظر...' : 'حظر الشريك الحالي'),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<BlockedUserModel>>(
            future: _blockedFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return const Text(
                  'لا توجد حسابات محظورة.',
                  textAlign: TextAlign.center,
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_off_outlined),
                      title: Text(item.user?.displayName ?? item.blockedId),
                      subtitle: Text(
                        [
                          if (item.user?.username.isNotEmpty == true)
                            '@${item.user!.username}',
                          if (item.reason?.isNotEmpty == true) item.reason!,
                        ].join(' - '),
                      ),
                      trailing: IconButton(
                        tooltip: 'فك الحظر',
                        onPressed: () => _unblock(item.blockedId),
                        icon: const Icon(Icons.lock_open_outlined),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.download_outlined),
            label: const Text('تصدير بيانات الحساب'),
          ),
          OutlinedButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('حذف الحساب'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Future<void> _report() async {
    if (_reason.text.trim().isEmpty) return;
    await widget.repository.report(
      reason: _reason.text,
      details: _details.text,
    );
    setState(() => _message = 'تم إرسال البلاغ.');
  }

  Future<void> _blockPartner() async {
    setState(() => _blocking = true);
    try {
      await widget.repository.blockPartner(reason: _blockReason.text);
      if (!mounted) return;
      setState(() {
        _blocking = false;
        _message = 'تم حظر الشريك الحالي.';
        _blockReason.clear();
        _blockedFuture = widget.repository.blockedUsers();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _blocking = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _unblock(String blockedUserId) async {
    await widget.repository.unblockUser(blockedUserId);
    if (!mounted) return;
    setState(() {
      _message = 'تم فك الحظر.';
      _blockedFuture = widget.repository.blockedUsers();
    });
  }

  Future<void> _export() async {
    final data = await widget.repository.exportAccount();
    setState(() => _message = 'تم تجهيز التصدير: ${data.keys.length} أقسام.');
  }

  Future<void> _delete() async {
    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف الحساب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سيتم تعطيل الحساب وإبطال الجلسات. أدخل كلمة المرور للتأكيد.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final value = passwordController.text.trim();
                if (value.isEmpty) return;
                Navigator.of(context).pop(value);
              },
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );
    passwordController.dispose();
    if (password == null) return;
    try {
      await widget.repository.deleteAccount(password);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _NotificationsScreen extends StatefulWidget {
  const _NotificationsScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<_NotificationsScreen> {
  late Future<List<NotificationItem>> _future = widget.repository
      .notifications();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          IconButton(
            tooltip: 'قراءة الكل',
            onPressed: _readAll,
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            tooltip: 'إعدادات الإشعارات',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _NotificationPreferencesScreen(
                  repository: widget.repository,
                ),
              ),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<NotificationItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData;
          if (items.isEmpty) {
            return const Center(child: Text('لا توجد إشعارات بعد.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final item in items)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_none_rounded),
                    title: Text(item.title),
                    subtitle: item.body == null ? null : Text(item.body!),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _readAll() async {
    await widget.repository.readAllNotifications();
    setState(() => _future = widget.repository.notifications());
  }
}

class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  late Future<UserProfile> _future = widget.repository.me();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _avatarUrl = TextEditingController();
  final _bio = TextEditingController();
  final _emailCode = TextEditingController();
  final _phoneCode = TextEditingController();
  final _favoriteColor = TextEditingController();
  final _favoriteFood = TextEditingController();
  final _favoriteSong = TextEditingController();
  final _favoriteMovie = TextEditingController();
  final _favoritePlace = TextEditingController();
  final _favoriteNote = TextEditingController();
  DateTime? _birthDate;
  String? _gender;
  String _language = 'ar';
  bool _searchable = true;
  bool _requests = true;
  bool _ready = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _avatarUrl.dispose();
    _bio.dispose();
    _emailCode.dispose();
    _phoneCode.dispose();
    _favoriteColor.dispose();
    _favoriteFood.dispose();
    _favoriteSong.dispose();
    _favoriteMovie.dispose();
    _favoritePlace.dispose();
    _favoriteNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: FutureBuilder<UserProfile>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.requireData;
          if (!_ready) {
            _username.text = profile.username;
            _displayName.text = profile.displayName;
            _avatarUrl.text = profile.avatarUrl ?? '';
            _bio.text = profile.bio ?? '';
            _birthDate = profile.birthDate;
            _gender = profile.gender;
            _language = profile.language ?? 'ar';
            final favorites = profile.favorites;
            _favoriteColor.text = favorites?.color ?? '';
            _favoriteFood.text = favorites?.food ?? '';
            _favoriteSong.text = favorites?.song ?? '';
            _favoriteMovie.text = favorites?.movie ?? '';
            _favoritePlace.text = favorites?.place ?? '';
            _favoriteNote.text = favorites?.note ?? '';
            _searchable = profile.searchable;
            _requests = profile.canReceiveRequests;
            _ready = true;
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _SectionHeader(
                icon: Icons.person_outline_rounded,
                title: profile.username,
                subtitle: profile.email ?? profile.phone ?? 'حساب Smiley',
              ),
              if (profile.email != null) ...[
                const SizedBox(height: 12),
                _InfoTile(
                  icon: profile.emailVerified
                      ? Icons.verified_rounded
                      : Icons.mark_email_unread_outlined,
                  title: profile.emailVerified
                      ? 'البريد موثق'
                      : 'البريد غير موثق',
                  subtitle: profile.email!,
                ),
                if (!profile.emailVerified) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailCode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'رمز تحقق البريد',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _requestEmailVerification,
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('إرسال الرمز'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _confirmEmailVerification,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('تأكيد'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              if (profile.phone != null) ...[
                const SizedBox(height: 12),
                _InfoTile(
                  icon: profile.phoneVerified
                      ? Icons.verified_rounded
                      : Icons.sms_outlined,
                  title: profile.phoneVerified
                      ? 'الهاتف موثق'
                      : 'الهاتف غير موثق',
                  subtitle: profile.phone!,
                ),
                if (!profile.phoneVerified) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneCode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'رمز تحقق الهاتف',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _requestPhoneVerification,
                          icon: const Icon(Icons.sms_outlined),
                          label: const Text('إرسال الرمز'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _confirmPhoneVerification,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('تأكيد'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(labelText: 'اسم العرض'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _avatarUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'رابط الصورة الشخصية',
                  prefixIcon: Icon(Icons.image_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bio,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'نبذة قصيرة'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickBirthDate,
                icon: const Icon(Icons.cake_outlined),
                label: Text(
                  _birthDate == null
                      ? 'اختر تاريخ الميلاد'
                      : '${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'الجنس اختياري',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'female', child: Text('أنثى')),
                  DropdownMenuItem(value: 'male', child: Text('ذكر')),
                  DropdownMenuItem(
                    value: 'prefer_not_to_say',
                    child: Text('أفضل عدم القول'),
                  ),
                ],
                onChanged: (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(
                  labelText: 'اللغة',
                  prefixIcon: Icon(Icons.language_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'ar', child: Text('العربية')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _language = value);
                },
              ),
              if (profile.timezone != null) ...[
                const SizedBox(height: 8),
                _InfoTile(
                  icon: Icons.schedule_outlined,
                  title: 'المنطقة الزمنية',
                  subtitle: profile.timezone!,
                ),
              ],
              const SizedBox(height: 16),
              const _SectionHeader(
                icon: Icons.favorite_border_rounded,
                title: 'المفضلات',
                subtitle: 'أشياء يحبها صاحب الحساب وتظهر ضمن ملفه الشخصي.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _favoriteColor,
                decoration: const InputDecoration(
                  labelText: 'اللون المفضل',
                  prefixIcon: Icon(Icons.palette_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _favoriteFood,
                decoration: const InputDecoration(
                  labelText: 'الأكلة المفضلة',
                  prefixIcon: Icon(Icons.restaurant_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _favoriteSong,
                decoration: const InputDecoration(
                  labelText: 'الأغنية المفضلة',
                  prefixIcon: Icon(Icons.music_note_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _favoriteMovie,
                decoration: const InputDecoration(
                  labelText: 'الفيلم أو المسلسل المفضل',
                  prefixIcon: Icon(Icons.movie_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _favoritePlace,
                decoration: const InputDecoration(
                  labelText: 'المكان المفضل',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _favoriteNote,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة مفضلة',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                value: _searchable,
                onChanged: (value) => setState(() => _searchable = value),
                title: const Text('ظهور الحساب في البحث'),
              ),
              SwitchListTile(
                value: _requests,
                onChanged: (value) => setState(() => _requests = value),
                title: const Text('استقبال طلبات الارتباط'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ الملف'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 13, now.month, now.day),
    );
    if (value != null) {
      setState(() => _birthDate = value);
    }
  }

  Future<void> _requestEmailVerification() async {
    await widget.repository.requestEmailVerification();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم إرسال رمز التحقق.')));
  }

  Future<void> _confirmEmailVerification() async {
    if (_emailCode.text.trim().length != 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل رمزاً من 6 أرقام.')));
      return;
    }
    await widget.repository.confirmEmailVerification(_emailCode.text);
    _emailCode.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم توثيق البريد.')));
    setState(() {
      _ready = false;
      _future = widget.repository.me();
    });
  }

  Future<void> _requestPhoneVerification() async {
    await widget.repository.requestPhoneVerification();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم إرسال رمز تحقق الهاتف.')));
  }

  Future<void> _confirmPhoneVerification() async {
    if (_phoneCode.text.trim().length != 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل رمزاً من 6 أرقام.')));
      return;
    }
    await widget.repository.confirmPhoneVerification(_phoneCode.text);
    _phoneCode.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم توثيق الهاتف.')));
    setState(() {
      _ready = false;
      _future = widget.repository.me();
    });
  }

  Future<void> _save() async {
    await widget.repository.updateUsername(_username.text);
    await widget.repository.updateProfile(
      displayName: _displayName.text,
      avatarUrl: _avatarUrl.text,
      bio: _bio.text,
      birthDate: _birthDate,
      gender: _gender,
      timezone: DateTime.now().timeZoneName,
      language: _language,
      favorites: ProfileFavorites(
        color: _favoriteColor.text,
        food: _favoriteFood.text,
        song: _favoriteSong.text,
        movie: _favoriteMovie.text,
        place: _favoritePlace.text,
        note: _favoriteNote.text,
      ),
      searchable: _searchable,
      canReceiveRequests: _requests,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ الملف الشخصي')));
    setState(() {
      _ready = false;
      _future = widget.repository.me();
    });
  }
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({
    required this.repository,
    required this.hasActivePartnership,
    this.partnershipRepository,
    this.onPartnershipChanged,
    this.authRepository,
  });

  final SpaceRepository repository;
  final PartnershipRepository? partnershipRepository;
  final AuthRepository? authRepository;
  final bool hasActivePartnership;
  final VoidCallback? onPartnershipChanged;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  final _worldName = TextEditingController();
  final _themeColor = TextEditingController(text: '#B96B7F');

  @override
  void dispose() {
    _worldName.dispose();
    _themeColor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(
            icon: Icons.settings_outlined,
            title: 'إعدادات العالم',
            subtitle: 'تغيير الاسم واللون الأساسي للعلاقة.',
          ),
          const SizedBox(height: 16),
          if (!widget.hasActivePartnership) ...[
            const _EmptyLine(
              text: 'أضف الشريك وأكمل إعداد البداية لتعديل إعدادات العالم.',
              color: Colors.grey,
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _worldName,
            decoration: const InputDecoration(labelText: 'اسم العالم'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _themeColor,
            decoration: const InputDecoration(labelText: 'لون العالم'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.hasActivePartnership ? _save : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ الإعدادات'),
          ),
          if (widget.hasActivePartnership &&
              widget.partnershipRepository != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _leavePartnership,
              icon: const Icon(Icons.heart_broken_outlined),
              label: const Text('إنهاء الارتباط الحالي'),
            ),
          ],
          if (widget.authRepository != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _SessionsScreen(repository: widget.authRepository!),
                ),
              ),
              icon: const Icon(Icons.devices_outlined),
              label: const Text('الأجهزة والجلسات'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _leavePartnership() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنهاء الارتباط'),
        content: const Text(
          'سيتم إيقاف العلاقة الحالية مع حفظ الذكريات والبيانات السابقة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('إنهاء'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.partnershipRepository?.leaveCurrentPartnership();
    if (!mounted) return;
    widget.onPartnershipChanged?.call();
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    await widget.repository.updateSettings(
      worldName: _worldName.text,
      themeColor: _themeColor.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
  }
}

class _SessionsScreen extends StatefulWidget {
  const _SessionsScreen({required this.repository});

  final AuthRepository repository;

  @override
  State<_SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<_SessionsScreen> {
  late Future<List<LoginSessionModel>> _future = widget.repository.sessions();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأجهزة والجلسات')),
      body: FutureBuilder<List<LoginSessionModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData;
          if (items.isEmpty) {
            return const Center(child: Text('لا توجد جلسات مسجلة.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionHeader(
                icon: Icons.devices_outlined,
                title: 'الأجهزة والجلسات',
                subtitle:
                    'راجع الأجهزة المسجلة وألغِ أي جلسة لا تريد استمرارها.',
              ),
              const SizedBox(height: 16),
              for (final item in items)
                Card(
                  child: ListTile(
                    leading: Icon(
                      item.active
                          ? Icons.devices_outlined
                          : Icons.block_outlined,
                    ),
                    title: Text(
                      item.deviceName?.isNotEmpty == true
                          ? item.deviceName!
                          : item.platform ?? 'جهاز',
                    ),
                    subtitle: Text(
                      item.current
                          ? 'الجلسة الحالية'
                          : item.active
                          ? 'آخر تحديث ${_date(item.updatedAt)}'
                          : 'ملغاة',
                    ),
                    trailing: item.active
                        ? IconButton(
                            tooltip: 'إلغاء الجلسة',
                            onPressed: _busy
                                ? null
                                : () => _revokeSession(item.id),
                            icon: const Icon(Icons.logout_rounded),
                          )
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _revokeSession(String id) async {
    setState(() => _busy = true);
    try {
      await widget.repository.revokeSession(id);
      setState(() => _future = widget.repository.sessions());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _NotificationPreferencesScreen extends StatefulWidget {
  const _NotificationPreferencesScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<_NotificationPreferencesScreen> {
  late Future<List<NotificationPreferenceModel>> _future = widget.repository
      .notificationPreferences();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الإشعارات')),
      body: FutureBuilder<List<NotificationPreferenceModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionHeader(
                icon: Icons.tune_rounded,
                title: 'إعدادات الإشعارات',
                subtitle: 'تحكم في التنبيهات الخارجية وفترة الهدوء.',
              ),
              const SizedBox(height: 16),
              for (final item in items)
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: Text(_notificationTypeLabel(item.type)),
                    subtitle: Text(
                      item.quietFrom == null || item.quietTo == null
                          ? 'بدون فترة هدوء'
                          : 'هدوء ${item.quietFrom} - ${item.quietTo}',
                    ),
                    value: item.enabled,
                    onChanged: _busy
                        ? null
                        : (value) => _updatePreference(item, value),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _setNightQuietHours,
                icon: const Icon(Icons.bedtime_outlined),
                label: const Text('تفعيل الهدوء الليلي 22:00 - 08:00'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updatePreference(
    NotificationPreferenceModel item,
    bool enabled,
  ) async {
    setState(() => _busy = true);
    try {
      await widget.repository.updateNotificationPreference(
        type: item.type,
        enabled: enabled,
        quietFrom: item.quietFrom,
        quietTo: item.quietTo,
      );
      setState(() => _future = widget.repository.notificationPreferences());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNightQuietHours() async {
    final items = await _future;
    setState(() => _busy = true);
    try {
      for (final item in items) {
        await widget.repository.updateNotificationPreference(
          type: item.type,
          enabled: item.enabled,
          quietFrom: '22:00',
          quietTo: '08:00',
        );
      }
      setState(() => _future = widget.repository.notificationPreferences());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _WishesGoalsScreen extends StatefulWidget {
  const _WishesGoalsScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_WishesGoalsScreen> createState() => _WishesGoalsScreenState();
}

class _WishesGoalsScreenState extends State<_WishesGoalsScreen> {
  late Future<List<WishItem>> _wishes = widget.repository.wishes();
  late Future<List<GoalItem>> _goals = widget.repository.goals();
  final _wish = TextEditingController();
  final _goal = TextEditingController();
  final _steps = TextEditingController();

  @override
  void dispose() {
    _wish.dispose();
    _goal.dispose();
    _steps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأمنيات والأهداف')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            icon: Icons.star_rounded,
            title: 'حديقة الأمنيات',
            subtitle: 'اكتبا أمنياتكما وحقّقاها معًا.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _wish,
                  decoration: const InputDecoration(
                    hintText: 'أمنية جديدة…',
                    prefixIcon: Icon(Icons.star_border_rounded),
                  ),
                  onSubmitted: (_) => _createWish(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _createWish,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<WishItem>>(
            future: _wishes,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final wishes = snapshot.requireData;
              if (wishes.isEmpty) {
                return const _EmptyLine(
                  text: 'لا أمنيات بعد.',
                  color: Colors.grey,
                );
              }
              return Column(
                children: [
                  for (final wish in wishes)
                    FadeSlideIn(
                      child: _WishCard(
                        wish: wish,
                        onToggle: () => _toggleWish(wish.id),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.flag_rounded,
            title: 'الأهداف المشتركة',
            subtitle: 'خطوة بخطوة نحو أحلامنا.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _goal,
            decoration: const InputDecoration(
              hintText: 'هدف جديد…',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _steps,
                  decoration: const InputDecoration(
                    hintText: 'خطوات مفصولة بفواصل',
                    prefixIcon: Icon(Icons.playlist_add_check_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _createGoal,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<GoalItem>>(
            future: _goals,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final goals = snapshot.requireData;
              if (goals.isEmpty) {
                return const _EmptyLine(
                  text: 'لا أهداف بعد.',
                  color: Colors.grey,
                );
              }
              return Column(
                children: [
                  for (final goal in goals)
                    FadeSlideIn(
                      child: _GoalCard(
                        goal: goal,
                        onToggleGoal: () => _toggleGoal(goal.id),
                        onToggleStep: _toggleStep,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createWish() async {
    if (_wish.text.trim().isEmpty) return;
    await widget.repository.createWish(_wish.text);
    _wish.clear();
    setState(() => _wishes = widget.repository.wishes());
  }

  Future<void> _toggleWish(String id) async {
    await widget.repository.toggleWish(id);
    setState(() => _wishes = widget.repository.wishes());
  }

  Future<void> _createGoal() async {
    if (_goal.text.trim().isEmpty) return;
    final steps = _steps.text.split(',');
    await widget.repository.createGoal(title: _goal.text, steps: steps);
    _goal.clear();
    _steps.clear();
    setState(() => _goals = widget.repository.goals());
  }

  Future<void> _toggleGoal(String id) async {
    await widget.repository.toggleGoal(id);
    setState(() => _goals = widget.repository.goals());
  }

  Future<void> _toggleStep(String id) async {
    await widget.repository.toggleGoalStep(id);
    setState(() => _goals = widget.repository.goals());
  }
}

class _WishCard extends StatelessWidget {
  const _WishCard({required this.wish, required this.onToggle});

  final WishItem wish;
  final VoidCallback onToggle;

  static const _gold = Color(0xFFFFB300);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = wish.completed;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: done
              ? _gold.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: done ? _gold : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 1, end: done ? 1.15 : 1),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Icon(
                done ? Icons.star_rounded : Icons.star_border_rounded,
                color: _gold,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: 15,
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
                child: Text(wish.title),
              ),
            ),
            if (done) const Text('🌟', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatefulWidget {
  const _GoalCard({
    required this.goal,
    required this.onToggleGoal,
    required this.onToggleStep,
  });

  final GoalItem goal;
  final VoidCallback onToggleGoal;
  final ValueChanged<String> onToggleStep;

  @override
  State<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<_GoalCard> {
  bool _expanded = false;

  static const _teal = Color(0xFF4B9A8D);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final goal = widget.goal;
    final total = goal.steps.length;
    final doneSteps = goal.steps.where((step) => step.completed).length;
    final progress = goal.completed
        ? 1.0
        : (total == 0 ? 0.0 : doneSteps / total);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onToggleGoal,
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: value,
                            strokeWidth: 5,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: goal.completed ? _teal : scheme.primary,
                          ),
                        ),
                      ),
                      if (goal.completed)
                        const Icon(Icons.check_rounded, color: _teal)
                      else
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: goal.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? (goal.completed ? 'مكتمل 🎉' : 'بلا خطوات')
                          : '$doneSteps / $total خطوات',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (total > 0)
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              children: [
                const SizedBox(height: 6),
                for (final step in goal.steps)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: step.completed,
                    onChanged: (_) => widget.onToggleStep(step.id),
                    title: Text(
                      step.title,
                      style: TextStyle(
                        decoration: step.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }
}

class _SharedListsScreen extends StatefulWidget {
  const _SharedListsScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_SharedListsScreen> createState() => _SharedListsScreenState();
}

class _SharedListsScreenState extends State<_SharedListsScreen> {
  late Future<List<SharedListModel>> _future = widget.repository.sharedLists();
  final _title = TextEditingController();
  final _kind = TextEditingController(text: 'general');

  @override
  void dispose() {
    _title.dispose();
    _kind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('القوائم المشتركة')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'اسم القائمة'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _kind,
            decoration: const InputDecoration(labelText: 'نوع القائمة'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _createList,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إنشاء قائمة'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<SharedListModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return Column(
                children: [
                  for (final list in snapshot.requireData)
                    Card(
                      child: ExpansionTile(
                        title: Text(list.title),
                        subtitle: Text(list.kind),
                        trailing: IconButton(
                          tooltip: 'إضافة عنصر',
                          onPressed: () => _addItem(list.id),
                          icon: const Icon(Icons.add_rounded),
                        ),
                        children: [
                          for (final item in list.items)
                            CheckboxListTile(
                              value: item.completed,
                              onChanged: (_) => _toggleItem(item.id),
                              title: Text(item.title),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createList() async {
    if (_title.text.trim().isEmpty) return;
    await widget.repository.createSharedList(
      title: _title.text,
      kind: _kind.text,
    );
    _title.clear();
    setState(() => _future = widget.repository.sharedLists());
  }

  Future<void> _addItem(String listId) async {
    final title = await _promptText(context, 'عنصر جديد');
    if (title == null || title.trim().isEmpty) return;
    await widget.repository.addSharedListItem(listId: listId, title: title);
    setState(() => _future = widget.repository.sharedLists());
  }

  Future<void> _toggleItem(String id) async {
    await widget.repository.toggleSharedListItem(id);
    setState(() => _future = widget.repository.sharedLists());
  }
}

class _GamesScreen extends StatefulWidget {
  const _GamesScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<_GamesScreen> {
  late Future<List<GameSessionModel>> _future = widget.repository.games();
  final _promptAnswer = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _promptAnswer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الألعاب')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _createGame,
        icon: const Icon(Icons.add_rounded),
        label: const Text('لعبة جديدة'),
      ),
      body: FutureBuilder<List<GameSessionModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final games = snapshot.requireData;
          final promptGames = games.where((game) => game.isPrompt).toList();
          final xGames = games.where((game) => !game.isPrompt).toList();
          final game = xGames.isEmpty ? null : xGames.first;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionHeader(
                icon: Icons.sports_esports_rounded,
                title: 'ألعاب سريعة',
                subtitle: 'العبا سويًا على جهاز واحد — بدون إنترنت.',
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  _MiniGameCard(
                    icon: Icons.style_rounded,
                    title: 'بطاقات الحب',
                    subtitle: 'طابِق الأزواج',
                    colors: const [Color(0xFF7C4DFF), Color(0xFFB388FF)],
                    onTap: () => _open(const _MemoryMatchScreen()),
                  ),
                  _MiniGameCard(
                    icon: Icons.alt_route_rounded,
                    title: 'لو خيّروك',
                    subtitle: 'هذا أم ذاك؟',
                    colors: const [Color(0xFFFF5FA2), Color(0xFFFF9E80)],
                    onTap: () => _open(const _WouldYouRatherScreen()),
                  ),
                  _MiniGameCard(
                    icon: Icons.local_fire_department_rounded,
                    title: 'صراحة وجرأة',
                    subtitle: 'اسحبا بطاقة',
                    colors: const [Color(0xFFFFB300), Color(0xFFFF7043)],
                    onTap: () => _open(const _TruthOrDareScreen()),
                  ),
                  _MiniGameCard(
                    icon: Icons.bolt_rounded,
                    title: 'سرعة البديهة',
                    subtitle: 'من أسرع؟',
                    colors: const [Color(0xFF26C6DA), Color(0xFF4B9A8D)],
                    onTap: () => _open(const _ReactionGameScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionHeader(
                icon: Icons.wifi_rounded,
                title: 'ألعاب مع الشريك',
                subtitle: 'تُلعب أونلاين ومتزامنة بينكما.',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _createPromptGame,
                      icon: const Icon(Icons.question_answer_outlined),
                      label: const Text('سؤال يومي'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _createGame,
                      icon: const Icon(Icons.grid_3x3_rounded),
                      label: const Text('X/O'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (games.isEmpty) ...[
                const _EmptyLine(
                  text: 'ابدأ لعبة X/O أو سؤال يومي مشترك.',
                  color: Colors.grey,
                ),
              ],
              for (final promptGame in promptGames) ...[
                _PromptGameCard(
                  game: promptGame,
                  answerController: _promptAnswer,
                  busy: _busy,
                  onPick: (answer) => _promptAnswer.text = answer,
                  onAnswer: () => _answerPrompt(promptGame.id),
                  onSkip: () => _skipPrompt(promptGame.id),
                ),
                const SizedBox(height: 16),
              ],
              if (game != null) ...[
                _SectionHeader(
                  icon: Icons.grid_3x3_rounded,
                  title: 'X/O',
                  subtitle: game.finished ? 'انتهت اللعبة' : 'اللعبة مستمرة',
                ),
                const SizedBox(height: 16),
                AspectRatio(
                  aspectRatio: 1,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: 9,
                    itemBuilder: (context, index) {
                      final value = game.board[index];
                      return FilledButton.tonal(
                        onPressed: _busy || game.finished || value != null
                            ? null
                            : () => _play(game.id, index),
                        child: Text(
                          value?.toUpperCase() ?? '',
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (game.winnerUserId != null)
                  const _EmptyLine(
                    text: 'هناك فائز في هذه الجولة.',
                    color: Colors.green,
                  )
                else if (game.finished)
                  const _EmptyLine(
                    text: 'انتهت الجولة بالتعادل.',
                    color: Colors.grey,
                  )
                else
                  const _EmptyLine(
                    text: 'اضغط على خانة عندما يكون الدور لك.',
                    color: Colors.grey,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _createGame() async {
    setState(() => _busy = true);
    try {
      await widget.repository.createGame();
      setState(() => _future = widget.repository.games());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createPromptGame() async {
    setState(() => _busy = true);
    try {
      await widget.repository.createGame(gameType: 'daily_prompt');
      setState(() => _future = widget.repository.games());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(String gameId, int position) async {
    setState(() => _busy = true);
    try {
      await widget.repository.playGameMove(gameId: gameId, position: position);
      setState(() => _future = widget.repository.games());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answerPrompt(String gameId) async {
    final answer = _promptAnswer.text.trim();
    if (answer.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.answerPromptGame(gameId: gameId, answer: answer);
      _promptAnswer.clear();
      setState(() => _future = widget.repository.games());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skipPrompt(String gameId) async {
    setState(() => _busy = true);
    try {
      await widget.repository.skipPromptGame(gameId: gameId);
      _promptAnswer.clear();
      setState(() => _future = widget.repository.games());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ===========================================================================
// Quick offline couple games (fully playable on one device, no backend).
// ===========================================================================

class _MiniGameCard extends StatelessWidget {
  const _MiniGameCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: Colors.white, size: 30),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Memory match --------------------------------------------------------

class _MemoryMatchScreen extends StatefulWidget {
  const _MemoryMatchScreen();

  @override
  State<_MemoryMatchScreen> createState() => _MemoryMatchScreenState();
}

class _MemoryMatchScreenState extends State<_MemoryMatchScreen> {
  static const _faces = ['❤️', '😍', '🌹', '🐻', '🍫', '⭐', '🎈', '🌙'];
  late List<String> _cards;
  final Set<int> _revealed = {};
  final Set<int> _matched = {};
  int? _first;
  bool _busy = false;
  int _moves = 0;
  int? _best;
  final Stopwatch _watch = Stopwatch();
  Timer? _flipTimer;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _deal();
    _loadBest();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _best = prefs.getInt('game_memory_best'));
  }

  void _deal() {
    _cards = [..._faces, ..._faces]..shuffle(math.Random());
    _revealed.clear();
    _matched.clear();
    _first = null;
    _busy = false;
    _moves = 0;
    _watch
      ..reset()
      ..start();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _tap(int i) {
    if (_busy || _revealed.contains(i) || _matched.contains(i)) return;
    setState(() => _revealed.add(i));
    if (_first == null) {
      _first = i;
      return;
    }
    _moves++;
    final a = _first!;
    final b = i;
    _first = null;
    if (_cards[a] == _cards[b]) {
      setState(
        () => _matched
          ..add(a)
          ..add(b),
      );
      if (_matched.length == _cards.length) _finish();
    } else {
      _busy = true;
      _flipTimer = Timer(const Duration(milliseconds: 750), () {
        if (!mounted) return;
        setState(() {
          _revealed
            ..remove(a)
            ..remove(b);
          _busy = false;
        });
      });
    }
  }

  Future<void> _finish() async {
    _watch.stop();
    _tick?.cancel();
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt('game_memory_best');
    if (prev == null || _moves < prev) {
      await prefs.setInt('game_memory_best', _moves);
      if (mounted) setState(() => _best = _moves);
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أحسنتما! 🎉'),
        content: Text(
          'أتممتما اللعبة في $_moves محاولة و${_watch.elapsed.inSeconds} ثانية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسنًا'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(_deal);
            },
            child: const Text('العب مجددًا'),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بطاقات الحب'),
        actions: [
          IconButton(
            tooltip: 'توزيع جديد',
            onPressed: () => setState(_deal),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat(Icons.touch_app_rounded, 'محاولات', '$_moves'),
                _stat(
                  Icons.timer_outlined,
                  'الوقت',
                  '${_watch.elapsed.inSeconds}ث',
                ),
                _stat(
                  Icons.emoji_events_outlined,
                  'أفضل',
                  _best?.toString() ?? '—',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (var i = 0; i < _cards.length; i++)
                    _MemoryCard(
                      face: _cards[i],
                      revealed: _revealed.contains(i) || _matched.contains(i),
                      matched: _matched.contains(i),
                      onTap: () => _tap(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.face,
    required this.revealed,
    required this.matched,
    required this.onTap,
  });

  final String face;
  final bool revealed;
  final bool matched;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: revealed ? 1 : 0),
        duration: const Duration(milliseconds: 280),
        builder: (context, v, _) {
          final showFront = v > 0.5;
          final child = showFront
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _face(),
                )
              : _back();
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(v * math.pi),
            child: child,
          );
        },
      ),
    );
  }

  Widget _back() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7C4DFF), Color(0xFF5E35B1)],
      ),
    ),
    child: const Center(
      child: Icon(Icons.favorite_rounded, color: Colors.white24, size: 26),
    ),
  );

  Widget _face() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: matched ? const Color(0xFFE8F5E9) : Colors.white,
      border: Border.all(
        color: matched ? const Color(0xFF66BB6A) : const Color(0xFFE0E0E0),
        width: 2,
      ),
    ),
    child: Center(child: Text(face, style: const TextStyle(fontSize: 26))),
  );
}

// --- Would you rather -----------------------------------------------------

class _WouldYouRatherScreen extends StatefulWidget {
  const _WouldYouRatherScreen();

  @override
  State<_WouldYouRatherScreen> createState() => _WouldYouRatherScreenState();
}

class _WouldYouRatherScreenState extends State<_WouldYouRatherScreen> {
  static const _dilemmas = <List<String>>[
    ['نسافر إلى البحر', 'نسافر إلى الجبل'],
    ['سهرة أفلام في البيت', 'عشاء في مطعم فاخر'],
    ['نتقاسم طبقًا واحدًا', 'لكلٍّ طبقه الخاص'],
    ['قهوة الصباح', 'شاي المساء'],
    ['رحلة مفاجئة', 'رحلة مخطط لها بدقّة'],
    ['نرقص تحت المطر', 'نتأمل النجوم'],
    ['نطبخ سويًا', 'نطلب توصيلًا ونرتاح'],
    ['صيف دائم', 'شتاء دائم'],
    ['نوثّق كل لحظة بالصور', 'نعيش اللحظة بلا كاميرا'],
    ['نسهر للفجر نتكلم', 'ننام مبكرًا متعانقين'],
    ['هدية غالية', 'رسالة بخط اليد'],
    ['نتعلم لغة جديدة معًا', 'نتعلم الطبخ معًا'],
    ['بيت صغير دافئ', 'بيت واسع كبير'],
    ['نربّي قطة', 'نربّي كلبًا'],
    ['نعيش قرب الأهل', 'نخوض مغامرة في مدينة جديدة'],
    ['نحتفل بصخب مع الجميع', 'نحتفل بهدوء بيننا'],
    ['نكتب مذكرات مشتركة', 'نصوّر فيديو لكل ذكرى'],
    ['فطور في السرير', 'نزهة صباحية'],
  ];

  late List<int> _order;
  int _pos = 0;
  int? _choice;

  @override
  void initState() {
    super.initState();
    _order = List<int>.generate(_dilemmas.length, (i) => i)
      ..shuffle(math.Random());
  }

  void _next() {
    setState(() {
      _choice = null;
      _pos++;
      if (_pos >= _dilemmas.length) {
        _pos = 0;
        _order.shuffle(math.Random());
      }
    });
  }

  Widget _option(int index, String text, List<Color> colors) {
    final selected = _choice == index;
    final dim = _choice != null && !selected;
    return GestureDetector(
      onTap: () => setState(() => _choice = index),
      child: AnimatedOpacity(
        opacity: dim ? 0.4 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: selected ? Border.all(color: Colors.white, width: 3) : null,
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = _dilemmas[_order[_pos]];
    return Scaffold(
      appBar: AppBar(title: const Text('لو خيّروك')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '${_pos + 1} / ${_dilemmas.length}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _option(0, d[0], const [
                Color(0xFF7C4DFF),
                Color(0xFF9575CD),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'أو',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: _option(1, d[1], const [
                Color(0xFFFF5FA2),
                Color(0xFFFF8A65),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _next,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('التالي'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Truth or dare --------------------------------------------------------

class _TruthOrDareScreen extends StatefulWidget {
  const _TruthOrDareScreen();

  @override
  State<_TruthOrDareScreen> createState() => _TruthOrDareScreenState();
}

class _TruthOrDareScreenState extends State<_TruthOrDareScreen> {
  static const _truths = <String>[
    'ما أول شيء لاحظته فيّ؟',
    'ما أكثر لحظة تتمنى تكرارها معي؟',
    'ما الشيء الذي أفعله ويُسعدك دائمًا؟',
    'متى شعرت أنك محظوظ بي؟',
    'لو وصفتني بكلمة واحدة، ماذا تقول؟',
    'ما الحلم الذي تتمنى أن نحققه معًا؟',
    'ما أطرف موقف جمعنا؟',
    'ما الأغنية التي تذكّرك بي؟',
    'ما الشيء الذي تريد أن نجرّبه معًا ولم نجرّبه بعد؟',
    'ما أجمل هدية شعرت بها مني؟',
    'ما الذي يجعلك تبتسم حتى في يوم سيّئ؟',
    'ما أكثر مكان تتمنى أن نزوره سويًا؟',
    'ما الشيء الصغير الذي تفتقده حين أغيب؟',
    'ما اللحظة التي عرفت فيها أنك تحبني؟',
    'لو رجع بنا الزمن، أي يوم نعيشه ثانية؟',
    'ما العادة التي بدأناها معًا وتحبها؟',
    'ما الكلمة التي تحب أن أناديك بها؟',
    'ما الذي تتمنى أن أعرفه عنك أكثر؟',
    'ما أكثر صفة تفخر بها فيّ؟',
    'ما أجمل مفاجأة تتمنى أن أعملها لك؟',
  ];

  static const _dares = <String>[
    'أرسل لي رسالة صوتية تقول فيها أجمل صفة فيّ.',
    'قلّد طريقتي في الضحك.',
    'غنِّ مقطعًا من أغنية نحبها.',
    'امنحني عناقًا لمدة 20 ثانية.',
    'التقط سيلفي مضحكًا معي الآن.',
    'اكتب لي جملة حب على ورقة وأرِني إياها.',
    'صف يومنا المثالي في ثلاث جمل.',
    'اختر لي لقبًا جديدًا لطيفًا.',
    'قل ثلاثة أشياء تشكرني عليها.',
    'حضّر لي كوب ماء أو قهوة الآن.',
    'أخبرني بذكرى تُضحكك كلما تذكرتها.',
    'قل "أحبك" بثلاث لهجات مختلفة.',
    'اعمل رقصة قصيرة لمدة 10 ثوانٍ.',
    'أغمض عينيك وصِف ملامح وجهي.',
    'ابتسم لي دون أن تتكلم لمدة 15 ثانية.',
    'أخبرني بأمنية تتمناها لنا هذا العام.',
    'اختر أغنية وشغّلها لنا الآن.',
    'قل أجمل جملة سمعتها عني من أحد.',
    'ارسم قلبًا صغيرًا وأهدِه لي.',
    'صِف شعورك بأول لقاء جمعنا.',
  ];

  final math.Random _rand = math.Random();
  String? _card;
  bool _isDare = false;

  void _draw(bool dare) {
    final deck = dare ? _dares : _truths;
    String pick;
    do {
      pick = deck[_rand.nextInt(deck.length)];
    } while (deck.length > 1 && pick == _card);
    setState(() {
      _card = pick;
      _isDare = dare;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCard = _card != null;
    return Scaffold(
      appBar: AppBar(title: const Text('صراحة وجرأة')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: hasCard
                    ? Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _isDare
                                ? const [Color(0xFFFF7043), Color(0xFFFFB300)]
                                : const [Color(0xFF5C6BC0), Color(0xFF26C6DA)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                _isDare ? 'جرأة 🔥' : 'صراحة 💬',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _card!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        'اختر صراحة أو جرأة لسحب بطاقة 💌',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _draw(false),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('صراحة'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5C6BC0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _draw(true),
                    icon: const Icon(Icons.local_fire_department_rounded),
                    label: const Text('جرأة'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7043),
                    ),
                  ),
                ),
              ],
            ),
            if (hasCard) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _draw(_isDare),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('بطاقة أخرى'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Reaction speed -------------------------------------------------------

class _ReactionGameScreen extends StatefulWidget {
  const _ReactionGameScreen();

  @override
  State<_ReactionGameScreen> createState() => _ReactionGameScreenState();
}

class _ReactionGameScreenState extends State<_ReactionGameScreen> {
  String _phase = 'idle'; // idle | wait | go | early | result
  int? _ms;
  int? _best;
  Timer? _timer;
  final Stopwatch _sw = Stopwatch();
  final math.Random _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _loadBest();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _best = prefs.getInt('game_reaction_best'));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _phase = 'wait');
    final delay = 1200 + _rand.nextInt(2600);
    _timer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      _sw
        ..reset()
        ..start();
      setState(() => _phase = 'go');
    });
  }

  Future<void> _saveBest(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt('game_reaction_best');
    if (prev == null || ms < prev) {
      await prefs.setInt('game_reaction_best', ms);
      if (mounted) setState(() => _best = ms);
    }
  }

  void _onTap() {
    switch (_phase) {
      case 'wait':
        _timer?.cancel();
        setState(() => _phase = 'early');
      case 'go':
        _sw.stop();
        final ms = _sw.elapsedMilliseconds;
        setState(() {
          _ms = ms;
          _phase = 'result';
        });
        _saveBest(ms);
      default:
        _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xFF4B9A8D);
    String title = 'اختبر سرعتك';
    String sub = 'انقر في أي مكان للبدء';
    if (_phase == 'wait') {
      bg = const Color(0xFFE53935);
      title = 'انتظر الأخضر...';
      sub = 'لا تستعجل';
    } else if (_phase == 'go') {
      bg = const Color(0xFF43A047);
      title = 'انقر الآن!';
      sub = '';
    } else if (_phase == 'early') {
      bg = const Color(0xFFFB8C00);
      title = 'بدري! 😅';
      sub = 'انقر للمحاولة من جديد';
    } else if (_phase == 'result') {
      bg = const Color(0xFF5C6BC0);
      title = '$_ms مللي ثانية ⚡';
      sub = 'انقر للعب مجددًا';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('سرعة البديهة')),
      body: GestureDetector(
        onTap: _onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: bg,
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _phase == 'go' ? Icons.touch_app_rounded : Icons.bolt_rounded,
                color: Colors.white,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  sub,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15,
                  ),
                ),
              ],
              if (_best != null) ...[
                const SizedBox(height: 24),
                Text(
                  'أفضل زمن: $_best مللي ثانية',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptGameCard extends StatelessWidget {
  const _PromptGameCard({
    required this.game,
    required this.answerController,
    required this.busy,
    required this.onPick,
    required this.onAnswer,
    required this.onSkip,
  });

  final GameSessionModel game;
  final TextEditingController answerController;
  final bool busy;
  final ValueChanged<String> onPick;
  final VoidCallback onAnswer;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final completed = game.answers.length + game.skipped.length;
    final total = game.players.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              icon: Icons.question_answer_outlined,
              title: 'سؤال يومي',
              subtitle: game.finished
                  ? 'اكتمل السؤال'
                  : 'إجابات $completed من $total',
            ),
            const SizedBox(height: 12),
            Text(
              game.prompt ?? 'اختارا إجابة مشتركة لهذا اليوم.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (game.options.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in game.options)
                    ActionChip(
                      label: Text(option),
                      onPressed: busy || game.finished
                          ? null
                          : () => onPick(option),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: answerController,
              enabled: !busy && !game.finished,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'إجابتك',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy || game.finished ? null : onSkip,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('تخطي'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy || game.finished ? null : onAnswer,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('إرسال'),
                  ),
                ),
              ],
            ),
            if (game.answers.isNotEmpty || game.skipped.isNotEmpty) ...[
              const SizedBox(height: 12),
              _EmptyLine(
                text:
                    '${game.answers.length} إجابة، ${game.skipped.length} تخطي.',
                color: Colors.grey,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlacesScreen extends StatefulWidget {
  const _PlacesScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<_PlacesScreen> {
  late Future<List<PlaceItem>> _future = widget.repository.places();
  final _title = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خريطة الذكريات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionHeader(
            icon: Icons.map_outlined,
            title: 'خريطة الذكريات',
            subtitle: 'احفظوا الأماكن المهمة وسجلوا زياراتكم لها.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'اسم المكان',
              prefixIcon: Icon(Icons.place_outlined),
            ),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latitude,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'خط العرض'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _longitude,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'خط الطول'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('إضافة مكان'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<PlaceItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final items = snapshot.requireData;
              if (items.isEmpty) {
                return const _EmptyLine(
                  text: 'لا توجد أماكن محفوظة بعد.',
                  color: Colors.grey,
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(item.title),
                        subtitle: Text(_placeSubtitle(item)),
                        trailing: IconButton(
                          tooltip: 'تسجيل زيارة',
                          onPressed: _busy ? null : () => _visit(item.id),
                          icon: const Icon(Icons.add_task_rounded),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    final latitude = _parseOptionalDouble(_latitude.text);
    final longitude = _parseOptionalDouble(_longitude.text);
    if ((_latitude.text.trim().isNotEmpty && latitude == null) ||
        (_longitude.text.trim().isNotEmpty && longitude == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل الإحداثيات كأرقام صحيحة.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.repository.createPlace(
        _title.text,
        latitude: latitude,
        longitude: longitude,
      );
      _title.clear();
      _latitude.clear();
      _longitude.clear();
      setState(() => _future = widget.repository.places());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _visit(String placeId) async {
    setState(() => _busy = true);
    try {
      await widget.repository.recordPlaceVisit(placeId);
      setState(() => _future = widget.repository.places());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double? _parseOptionalDouble(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : double.tryParse(trimmed);
  }

  String _placeSubtitle(PlaceItem item) {
    final parts = <String>[];
    if (item.latitude != null && item.longitude != null) {
      parts.add('${item.latitude}, ${item.longitude}');
    }
    parts.add('${item.visitCount} زيارة');
    if (item.lastVisitedAt != null) {
      parts.add('آخر زيارة ${_date(item.lastVisitedAt!)}');
    }
    return parts.join(' - ');
  }
}

class _AlbumsScreen extends StatefulWidget {
  const _AlbumsScreen({required this.repository});

  final SpaceRepository repository;

  @override
  State<_AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<_AlbumsScreen> {
  late Future<List<AlbumModel>> _future = widget.repository.albums();
  final _title = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الألبومات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionHeader(
            icon: Icons.photo_library_outlined,
            title: 'الألبومات',
            subtitle: 'اجمعوا الصور والملفات في ألبومات مشتركة.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'اسم الألبوم',
              prefixIcon: Icon(Icons.photo_album_outlined),
            ),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إنشاء ألبوم'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<AlbumModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final items = snapshot.requireData;
              if (items.isEmpty) {
                return const _EmptyLine(
                  text: 'لا توجد ألبومات بعد.',
                  color: Colors.grey,
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.photo_library_outlined),
                        title: Text(item.title),
                        subtitle: Text('${item.itemCount} عناصر'),
                        trailing: IconButton(
                          tooltip: 'إضافة ملف',
                          onPressed: _busy ? null : () => _addItem(item.id),
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.repository.createAlbum(_title.text);
      _title.clear();
      setState(() => _future = widget.repository.albums());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addItem(String albumId) async {
    final result = await FilePicker.pickFiles(withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    if (!mounted) return;
    final caption = await _promptText(context, 'وصف اختياري');
    setState(() => _busy = true);
    try {
      final asset = await widget.repository.uploadMedia(
        fileName: file.name,
        mimeType: _mimeTypeFromName(file.name),
        bytes: bytes,
      );
      await widget.repository.addAlbumItem(
        albumId: albumId,
        assetId: asset.id,
        caption: caption,
      );
      setState(() => _future = widget.repository.albums());
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _RoomScreen extends StatefulWidget {
  const _RoomScreen.music({required this.repository, this.events})
    : title = 'الموسيقى',
      icon = Icons.music_note_rounded,
      isAudio = true,
      eventType = 'music.playback.updated',
      load = repositoryMusicRoom,
      add = repositoryAddMusicItem,
      playback = repositoryUpdateMusicPlayback;

  const _RoomScreen.watch({required this.repository, this.events})
    : title = 'السينما',
      icon = Icons.movie_outlined,
      isAudio = false,
      eventType = 'watch.playback.updated',
      load = repositoryWatchRoom,
      add = repositoryAddWatchItem,
      playback = repositoryUpdateWatchPlayback;

  final SpaceRepository repository;
  final Stream<Map<String, dynamic>>? events;
  final String title;
  final IconData icon;
  final bool isAudio;
  final String eventType;
  final Future<RoomModel> Function(SpaceRepository repository) load;
  final Future<void> Function(
    SpaceRepository repository,
    String title,
    String? sourceUrl,
  )
  add;
  final Future<RoomModel> Function(
    SpaceRepository repository,
    String eventType,
    int? positionMs,
    RoomItem? item,
  )
  playback;

  @override
  State<_RoomScreen> createState() => _RoomScreenState();

  static Future<RoomModel> repositoryMusicRoom(SpaceRepository repository) {
    return repository.musicRoom();
  }

  static Future<void> repositoryAddMusicItem(
    SpaceRepository repository,
    String title,
    String? sourceUrl,
  ) {
    return repository.addMusicItem(title, sourceUrl: sourceUrl);
  }

  static Future<RoomModel> repositoryUpdateMusicPlayback(
    SpaceRepository repository,
    String eventType,
    int? positionMs,
    RoomItem? item,
  ) {
    return repository.updateMusicPlayback(
      eventType: eventType,
      positionMs: positionMs,
      itemId: item?.id,
      sourceUrl: item?.sourceUrl,
      title: item?.title,
    );
  }

  static Future<RoomModel> repositoryWatchRoom(SpaceRepository repository) {
    return repository.watchRoom();
  }

  static Future<void> repositoryAddWatchItem(
    SpaceRepository repository,
    String title,
    String? sourceUrl,
  ) {
    return repository.addWatchItem(title, sourceUrl: sourceUrl);
  }

  static Future<RoomModel> repositoryUpdateWatchPlayback(
    SpaceRepository repository,
    String eventType,
    int? positionMs,
    RoomItem? item,
  ) {
    return repository.updateWatchPlayback(
      eventType: eventType,
      positionMs: positionMs,
      itemId: item?.id,
      sourceUrl: item?.sourceUrl,
      title: item?.title,
    );
  }
}

class _RoomScreenState extends State<_RoomScreen> {
  late Future<RoomModel> _future = widget.load(widget.repository);
  final _title = TextEditingController();
  final _sourceUrl = TextEditingController();
  bool _busy = false;
  bool _uploading = false;

  final AudioPlayer _player = AudioPlayer();
  VideoPlayerController? _video;
  YoutubePlayerController? _youtube;
  RoomItem? _current;
  StreamSubscription<Map<String, dynamic>>? _sync;
  bool _applyingRemote = false;

  @override
  void initState() {
    super.initState();
    final events = widget.events;
    if (events != null) {
      _sync = events.listen(_onRemotePlayback);
    }
  }

  // Applies the partner's play/pause/seek to the local player so both sides stay
  // in sync. Applied directly (never re-broadcast) to avoid feedback loops.
  void _onRemotePlayback(Map<String, dynamic> event) {
    if (event['type']?.toString() != widget.eventType) return;
    final payload = event['payload'];
    if (payload is! Map) return;
    final type = payload['eventType']?.toString();
    final rawPosition = payload['positionMs'];
    final position = rawPosition is int
        ? Duration(milliseconds: rawPosition)
        : null;
    _applyRemote(
      type,
      position,
      itemId: payload['itemId']?.toString(),
      sourceUrl: payload['sourceUrl']?.toString(),
      title: payload['title']?.toString(),
    );
  }

  Future<void> _applyRemote(
    String? type,
    Duration? position, {
    String? itemId,
    String? sourceUrl,
    String? title,
  }) async {
    _applyingRemote = true;
    try {
      // Switch to the partner's track first if it differs from ours.
      if (sourceUrl != null &&
          sourceUrl.isNotEmpty &&
          sourceUrl != _current?.sourceUrl) {
        final remoteItem = RoomItem(
          id: itemId ?? sourceUrl,
          title: title ?? 'مقطع',
          source: 'manual',
          sourceUrl: sourceUrl,
        );
        if (widget.isAudio) {
          setState(() => _current = remoteItem);
          await _player.setUrl(sourceUrl);
        } else {
          final youtubeId = YoutubePlayer.convertUrlToId(sourceUrl);
          if (youtubeId != null) {
            await _video?.dispose();
            _video = null;
            _youtube?.dispose();
            final controller = YoutubePlayerController(
              initialVideoId: youtubeId,
              flags: const YoutubePlayerFlags(autoPlay: true),
            )..addListener(_onYoutubeChanged);
            setState(() {
              _current = remoteItem;
              _youtube = controller;
            });
          } else {
            _youtube?.dispose();
            _youtube = null;
            await _video?.dispose();
            final controller = VideoPlayerController.networkUrl(
              Uri.parse(sourceUrl),
            );
            await controller.initialize();
            if (!mounted) {
              await controller.dispose();
              _applyingRemote = false;
              return;
            }
            setState(() {
              _current = remoteItem;
              _video = controller;
            });
          }
        }
      }
      if (widget.isAudio) {
        if (_current == null) return;
        if (position != null) await _player.seek(position);
        if (type == 'play') {
          await _player.play();
        } else if (type == 'pause') {
          await _player.pause();
        } else if (type == 'stop') {
          await _player.pause();
          await _player.seek(Duration.zero);
        }
      } else if (_youtube != null) {
        final controller = _youtube!;
        if (position != null) controller.seekTo(position);
        if (type == 'play') {
          controller.play();
        } else if (type == 'pause') {
          controller.pause();
        } else if (type == 'stop') {
          controller.pause();
          controller.seekTo(Duration.zero);
        }
      } else {
        final controller = _video;
        if (controller == null) return;
        if (position != null) await controller.seekTo(position);
        if (type == 'play') {
          await controller.play();
        } else if (type == 'pause') {
          await controller.pause();
        } else if (type == 'stop') {
          await controller.pause();
          await controller.seekTo(Duration.zero);
        }
      }
    } catch (_) {
      // Best-effort sync; ignore transient errors.
    } finally {
      _applyingRemote = false;
    }
  }

  @override
  void dispose() {
    _sync?.cancel();
    _title.dispose();
    _sourceUrl.dispose();
    _player.dispose();
    _video?.dispose();
    _youtube?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(
            icon: widget.icon,
            title: widget.title,
            subtitle: widget.isAudio
                ? 'ارفعا أغنية أو أضيفا رابطًا، واستمعا معًا.'
                : 'مساحة مشتركة تحفظ ما تريدان مشاهدته.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'عنوان جديد'),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sourceUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'رابط اختياري',
              prefixIcon: Icon(Icons.link_rounded),
            ),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_busy || _uploading) ? null : _uploadMedia,
                icon: _uploading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_rounded),
                label: Text(widget.isAudio ? 'رفع أغنية' : 'رفع فيديو'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.isAudio && _current != null)
            _AudioPlayerBar(
              player: _player,
              title: _current!.title,
              onToggle: _togglePlay,
              onSeek: (position) {
                _player.seek(position);
                widget.playback(
                  widget.repository,
                  'seek',
                  position.inMilliseconds,
                  _current,
                );
              },
            )
          else if (!widget.isAudio && _youtube != null && _current != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: YoutubePlayer(
                controller: _youtube!,
                showVideoProgressIndicator: true,
              ),
            )
          else if (!widget.isAudio && _video != null && _current != null)
            _VideoPlayerBar(
              controller: _video!,
              title: _current!.title,
              onToggle: _toggleVideo,
            ),
          const SizedBox(height: 12),
          FutureBuilder<RoomModel>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final room = snapshot.requireData;
              final items = room.items;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    const Text('لا توجد عناصر بعد.')
                  else
                    for (final item in items)
                      ListTile(
                        leading: Icon(
                          _current?.id == item.id
                              ? Icons.graphic_eq_rounded
                              : widget.icon,
                          color: _current?.id == item.id
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(item.title),
                        subtitle: Text(item.sourceUrl ?? item.source),
                        trailing: item.sourceUrl != null
                            ? IconButton(
                                icon: const Icon(
                                  Icons.play_circle_fill_rounded,
                                ),
                                onPressed: () => _playItem(item),
                              )
                            : null,
                        onTap: item.sourceUrl != null
                            ? () => _playItem(item)
                            : null,
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _playItem(RoomItem item) async {
    final url = item.sourceUrl;
    if (url == null || url.isEmpty) return;
    try {
      if (widget.isAudio) {
        if (_current?.id != item.id) {
          setState(() => _current = item);
          await _player.setUrl(url);
        }
        await _player.play();
        await widget.playback(
          widget.repository,
          'play',
          _player.position.inMilliseconds,
          _current,
        );
      } else {
        final youtubeId = YoutubePlayer.convertUrlToId(url);
        if (youtubeId != null) {
          if (_current?.id != item.id || _youtube == null) {
            await _video?.dispose();
            _video = null;
            _youtube?.dispose();
            final controller = YoutubePlayerController(
              initialVideoId: youtubeId,
              flags: const YoutubePlayerFlags(autoPlay: true),
            )..addListener(_onYoutubeChanged);
            setState(() {
              _current = item;
              _youtube = controller;
            });
          } else {
            _youtube?.play();
          }
          await widget.playback(widget.repository, 'play', 0, _current);
        } else {
          _youtube?.dispose();
          _youtube = null;
          if (_current?.id != item.id || _video == null) {
            await _video?.dispose();
            final controller = VideoPlayerController.networkUrl(Uri.parse(url));
            await controller.initialize();
            if (!mounted) {
              await controller.dispose();
              return;
            }
            setState(() {
              _current = item;
              _video = controller;
            });
          }
          await _video?.play();
          await widget.playback(
            widget.repository,
            'play',
            _video?.value.position.inMilliseconds ?? 0,
            _current,
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر تشغيل هذا المقطع.')));
    }
  }

  // Broadcasts YouTube play/pause when the user interacts with the built-in
  // controls. Fires only on play/pause transitions (not position ticks) and is
  // guarded so remote-applied changes don't echo back.
  bool? _lastYoutubePlaying;
  void _onYoutubeChanged() {
    final controller = _youtube;
    if (controller == null || _applyingRemote) return;
    final playing = controller.value.isPlaying;
    if (playing == _lastYoutubePlaying) return;
    _lastYoutubePlaying = playing;
    widget.playback(
      widget.repository,
      playing ? 'play' : 'pause',
      controller.value.position.inMilliseconds,
      _current,
    );
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
      await widget.playback(
        widget.repository,
        'pause',
        _player.position.inMilliseconds,
        _current,
      );
    } else {
      await _player.play();
      await widget.playback(
        widget.repository,
        'play',
        _player.position.inMilliseconds,
        _current,
      );
    }
  }

  Future<void> _toggleVideo() async {
    final controller = _video;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      await widget.playback(
        widget.repository,
        'pause',
        controller.value.position.inMilliseconds,
        _current,
      );
    } else {
      await controller.play();
      await widget.playback(
        widget.repository,
        'play',
        controller.value.position.inMilliseconds,
        _current,
      );
    }
  }

  Future<void> _uploadMedia() async {
    final result = await FilePicker.pickFiles(
      withData: true,
      type: widget.isAudio ? FileType.audio : FileType.video,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    setState(() => _uploading = true);
    try {
      final asset = await widget.repository.uploadMedia(
        fileName: file.name,
        mimeType: _mimeTypeFromName(file.name),
        bytes: bytes,
      );
      final url = asset.url;
      if (url == null) {
        throw const ApiException(
          code: 'no_public_url',
          message: 'تعذر الحصول على رابط الملف. تأكد من إعداد التخزين العام.',
        );
      }
      await widget.add(widget.repository, file.name, url);
      if (!mounted) return;
      setState(() => _future = widget.load(widget.repository));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.add(widget.repository, _title.text, _sourceUrl.text);
      _title.clear();
      _sourceUrl.clear();
      setState(() => _future = widget.load(widget.repository));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AudioPlayerBar extends StatelessWidget {
  const _AudioPlayerBar({
    required this.player,
    required this.title,
    required this.onToggle,
    required this.onSeek,
  });

  final AudioPlayer player;
  final String title;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_note_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          StreamBuilder<Duration?>(
            stream: player.durationStream,
            builder: (context, durationSnapshot) {
              final duration = durationSnapshot.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, positionSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;
                  final maxMs = duration.inMilliseconds.toDouble();
                  final value = position.inMilliseconds
                      .clamp(0, duration.inMilliseconds)
                      .toDouble();
                  return Column(
                    children: [
                      Slider(
                        value: maxMs == 0 ? 0 : value,
                        max: maxMs == 0 ? 1 : maxMs,
                        onChanged: maxMs == 0
                            ? null
                            : (v) => onSeek(Duration(milliseconds: v.round())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmt(position),
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            _fmt(duration),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              final processing = snapshot.data?.processingState;
              final loading =
                  processing == ProcessingState.loading ||
                  processing == ProcessingState.buffering;
              return Center(
                child: IconButton.filled(
                  iconSize: 34,
                  onPressed: loading ? null : onToggle,
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _VideoPlayerBar extends StatelessWidget {
  const _VideoPlayerBar({
    required this.controller,
    required this.title,
    required this.onToggle,
  });

  final VideoPlayerController controller;
  final String title;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: ratio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => GestureDetector(
                    onTap: onToggle,
                    child: AnimatedOpacity(
                      opacity: value.isPlaying ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        color: Colors.black26,
                        child: const Center(
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 56,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) => IconButton.filled(
                onPressed: onToggle,
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: VideoProgressColors(playedColor: scheme.primary),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _RoomPlaybackPanel extends StatelessWidget {
  const _RoomPlaybackPanel({
    required this.room,
    required this.busy,
    required this.onPlayback,
  });

  final RoomModel room;
  final bool busy;
  final ValueChanged<String> onPlayback;

  @override
  Widget build(BuildContext context) {
    final event = room.latestEvent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              icon: Icons.sensors_rounded,
              title: _statusLabel(room.status),
              subtitle: event == null
                  ? 'لا يوجد تشغيل مسجل بعد.'
                  : 'آخر حدث: ${_eventLabel(event.eventType)}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => onPlayback('play'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('تشغيل'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => onPlayback('pause'),
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('إيقاف مؤقت'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : () => onPlayback('stop'),
              icon: const Icon(Icons.stop_rounded),
              label: const Text('إيقاف'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'playing' => 'قيد التشغيل',
      'paused' => 'متوقف مؤقتاً',
      _ => 'جاهز للتشغيل',
    };
  }

  String _eventLabel(String eventType) {
    return switch (eventType) {
      'play' => 'تشغيل',
      'pause' => 'إيقاف مؤقت',
      'seek' => 'انتقال',
      'stop' => 'إيقاف',
      _ => eventType,
    };
  }
}

Future<String?> _promptText(
  BuildContext context,
  String title, {
  String? initial,
  String label = 'العنوان',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );
}

Future<bool?> _confirmDeletePost(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('حذف الذكرى'),
        content: const Text('سيتم إخفاء هذه الذكرى من العالم المشترك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      );
    },
  );
}

// ignore: unused_element
class _MoreTab extends StatelessWidget {
  const _MoreTab({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('الموسيقى', Icons.music_note_rounded),
      ('السينما', Icons.movie_outlined),
      ('الألبومات', Icons.photo_library_outlined),
      ('الأمنيات والأهداف', Icons.flag_outlined),
      ('خريطة الذكريات', Icons.map_outlined),
      ('الإشعارات', Icons.notifications_none_rounded),
      ('الملف الشخصي', Icons.person_outline_rounded),
      ('الإعدادات', Icons.settings_outlined),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final item in items)
          ListTile(
            leading: Icon(item.$2),
            title: Text(item.$1),
            trailing: const Icon(Icons.chevron_left_rounded),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout_rounded),
          title: const Text('تسجيل الخروج'),
          onTap: onSignOut,
        ),
      ],
    );
  }
}

class _HomeHeroCard extends StatelessWidget {
  const _HomeHeroCard({
    required this.worldName,
    required this.daysTogether,
    required this.nextEvent,
  });

  final String worldName;
  final int? daysTogether;
  final CalendarItem? nextEvent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final event = nextEvent;
    final daysToEvent = event?.startsAt.difference(DateTime.now()).inDays;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [scheme.primary, scheme.secondary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  worldName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (daysTogether != null)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: daysTogether!.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Text(
                    '${value.round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                const Text(
                  '—',
                  style: TextStyle(color: Colors.white, fontSize: 40),
                ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'يومًا معًا',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ],
          ),
          if (event != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.title,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (daysToEvent != null)
                    Text(
                      daysToEvent <= 0 ? 'اليوم!' : 'بعد $daysToEvent يوم',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({
    required this.onHeart,
    required this.onMood,
    required this.onChat,
    required this.onWorld,
  });

  final VoidCallback onHeart;
  final VoidCallback onMood;
  final VoidCallback onChat;
  final VoidCallback onWorld;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.favorite_rounded,
            label: 'قلب',
            color: const Color(0xFFFF5FA2),
            onTap: onHeart,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.mood_rounded,
            label: 'مزاجي',
            color: const Color(0xFFFFB300),
            onTap: onMood,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.chat_bubble_rounded,
            label: 'محادثة',
            color: const Color(0xFF7C4DFF),
            onTap: onChat,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.auto_awesome_rounded,
            label: 'العالم',
            color: const Color(0xFF4B9A8D),
            onTap: onWorld,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodBanner extends StatelessWidget {
  const _MoodBanner({required this.mood});

  final SpaceMood mood;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(mood.emoji ?? '🙂', style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'آخر مزاج',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  mood.note ?? mood.kind,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaGallery extends StatelessWidget {
  const _MediaGallery({required this.attachments});

  final List<MediaRef> attachments;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final media in attachments)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: media.isImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 240,
                        maxHeight: 260,
                      ),
                      child: Image.network(
                        media.url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const SizedBox(
                                width: 240,
                                height: 140,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                        errorBuilder: (context, error, stack) =>
                            _chip(context, media, 'تعذر تحميل الصورة'),
                      ),
                    ),
                  )
                : media.isAudio
                ? _AudioAttachment(url: media.url)
                : _chip(context, media, media.isVideo ? 'فيديو' : 'ملف'),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, MediaRef media, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            media.isVideo
                ? Icons.videocam_rounded
                : media.isAudio
                ? Icons.audiotrack_rounded
                : Icons.insert_drive_file_rounded,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _AudioAttachment extends StatefulWidget {
  const _AudioAttachment({required this.url});

  final String url;

  @override
  State<_AudioAttachment> createState() => _AudioAttachmentState();
}

class _AudioAttachmentState extends State<_AudioAttachment> {
  AudioPlayer? _player;
  bool _loading = false;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    var player = _player;
    if (player == null) {
      setState(() => _loading = true);
      player = AudioPlayer();
      _player = player;
      player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(
          () => _playing =
              state.playing &&
              state.processingState != ProcessingState.completed,
        );
      });
      try {
        await player.setUrl(widget.url);
      } catch (_) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (mounted) setState(() => _loading = false);
    }
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      await player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _loading
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: scheme.primary,
                    size: 24,
                  ),
            const SizedBox(width: 8),
            const Icon(Icons.graphic_eq_rounded, size: 18),
            const SizedBox(width: 6),
            const Text('رسالة صوتية'),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 36, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PostComposer extends StatelessWidget {
  const _PostComposer({
    required this.controller,
    required this.busy,
    required this.uploading,
    required this.attachmentCount,
    required this.onAttach,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final bool uploading;
  final int attachmentCount;
  final VoidCallback onAttach;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'اكتب ذكرى',
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy || uploading ? null : onAttach,
          icon: uploading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.attach_file_rounded),
          label: Text(
            attachmentCount == 0 ? 'إرفاق ملف' : 'المرفقات: $attachmentCount',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: busy || uploading ? null : onSubmit,
          icon: const Icon(Icons.add_rounded),
          label: const Text('حفظ الذكرى'),
        ),
      ],
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.post,
    this.onReact,
    this.onComment,
    this.onEdit,
    this.onDelete,
  });

  final SpacePost post;
  final VoidCallback? onReact;
  final VoidCallback? onComment;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                post.myReaction == null
                    ? Icons.favorite_border_rounded
                    : Icons.favorite_rounded,
              ),
              title: Text(post.title ?? post.body),
              subtitle: post.title == null
                  ? Text(_date(post.createdAt))
                  : Text(post.body),
              trailing: onEdit == null && onDelete == null
                  ? null
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) {
                        if (value == 'edit') onEdit?.call();
                        if (value == 'delete') onDelete?.call();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('تعديل')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
            ),
            if (post.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _MediaGallery(attachments: post.attachments),
                ),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 12,
                end: 12,
                bottom: 8,
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: onReact,
                    icon: Icon(
                      post.myReaction == null
                          ? Icons.favorite_border_rounded
                          : Icons.favorite_rounded,
                    ),
                    label: Text('${post.reactionCount}'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onComment,
                    icon: const Icon(Icons.mode_comment_outlined),
                    label: Text('${post.commentCount}'),
                  ),
                  const Spacer(),
                  if (post.assetIds.isNotEmpty)
                    Text(
                      '${post.assetIds.length} مرفق',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _MoodButton extends StatelessWidget {
  const _MoodButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.mood_rounded, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final text = unitIndex == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unitIndex]}';
}

String _mimeTypeFromName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return 'application/octet-stream';
}

String _notificationTypeLabel(String type) {
  return switch (type) {
    'message.created' => 'الرسائل',
    'partnership.requested' => 'طلبات الارتباط',
    'post.created' => 'الذكريات والمنشورات',
    'mood.updated' => 'المزاج',
    'calendar.event.created' => 'التقويم',
    'occasion.created' => 'المناسبات',
    'wish.created' => 'الأمنيات',
    'goal.created' => 'الأهداف',
    'shared_list.created' => 'القوائم المشتركة',
    'game.updated' => 'الألعاب',
    'music.queue.updated' => 'الموسيقى',
    'watch.playback.updated' => 'السينما',
    _ => type,
  };
}

String _two(int value) => value.toString().padLeft(2, '0');
