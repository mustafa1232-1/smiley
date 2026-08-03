import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/offline_outbox.dart';
import '../../core/realtime_client.dart';
import '../../core/secure_stores.dart';
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
      if (type.startsWith('partnership.') || type == 'notification.created') {
        _reload();
      }
    });
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
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
              : _pageFor(state!),
          floatingActionButton: active
              ? null
              : FloatingActionButton(
                  onPressed: _openPartnerSearch,
                  tooltip: 'إضافة شريك',
                  child: const Icon(Icons.person_add_alt_1_rounded),
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
          authRepository: widget.authRepository,
          hasActivePartnership: false,
          onSignOut: _signOut,
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
          authRepository: widget.authRepository,
          hasActivePartnership: false,
          onSignOut: _signOut,
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
      ),
      1 => _ChatTab(
        repository: widget.spaceRepository,
        offlineOutbox: widget.offlineOutbox,
      ),
      2 => _WorldTab(repository: widget.spaceRepository),
      3 => _CalendarTab(repository: widget.spaceRepository),
      _ => _MoreHubTabV2(
        repository: widget.spaceRepository,
        authRepository: widget.authRepository,
        hasActivePartnership: true,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
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
  DateTime _startDate = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _worldName.dispose();
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

  Future<void> _submit() async {
    setState(() => _busy = true);
    widget.onComplete(
      OnboardingInput(
        partnershipId: widget.partnership.id,
        startDate: _startDate,
        worldName: _worldName.text.trim().isEmpty
            ? 'عالمنا'
            : _worldName.text.trim(),
        themeColor: '#B96B7F',
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({required this.repository, required this.offlineOutbox});

  final SpaceRepository repository;
  final OfflineOutbox offlineOutbox;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  late Future<SpaceSummary> _summary = _loadSummary();
  final _post = TextEditingController();
  final List<MediaAssetModel> _attachments = [];
  bool _posting = false;
  bool _uploading = false;

  @override
  void dispose() {
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
              _SectionHeader(
                icon: Icons.favorite_rounded,
                title: summary.worldName ?? 'عالمنا',
                subtitle: summary.daysTogether == null
                    ? 'العلاقة مفعلة'
                    : 'اليوم ${summary.daysTogether} معاً',
              ),
              const SizedBox(height: 16),
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
              if (summary.latestMood != null)
                _InfoTile(
                  icon: Icons.mood_rounded,
                  title: 'آخر مزاج',
                  subtitle:
                      summary.latestMood!.note ?? summary.latestMood!.kind,
                ),
              if (summary.nextEvent != null)
                _InfoTile(
                  icon: Icons.event_rounded,
                  title: 'الموعد القادم',
                  subtitle:
                      '${summary.nextEvent!.title} - ${_date(summary.nextEvent!.startsAt)}',
                ),
              const SizedBox(height: 10),
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
}

class _WorldTab extends StatefulWidget {
  const _WorldTab({required this.repository});

  final SpaceRepository repository;

  @override
  State<_WorldTab> createState() => _WorldTabState();
}

class _WorldTabState extends State<_WorldTab> {
  late Future<List<SpacePost>> _posts = widget.repository.posts();
  final _moodNote = TextEditingController();

  @override
  void dispose() {
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
}

class _ChatTab extends StatefulWidget {
  const _ChatTab({required this.repository, required this.offlineOutbox});

  final SpaceRepository repository;
  final OfflineOutbox offlineOutbox;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  late Future<List<ChatMessage>> _messages = _loadMessages();
  late Future<List<ScheduledMessageModel>> _scheduled = _loadScheduled();
  final _message = TextEditingController();
  final List<MediaAssetModel> _attachments = [];
  bool _sending = false;
  bool _uploading = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<ChatMessage>>(
            future: _messages,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.requireData;
              if (items.isEmpty) {
                return const Center(child: Text('لا توجد رسائل بعد.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.body.isNotEmpty) Text(item.body),
                            if (item.assetIds.isNotEmpty) ...[
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
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton.outlined(
                  tooltip: 'إرفاق ملف',
                  onPressed: (_sending || _uploading) ? null : _attachMedia,
                  icon: _uploading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالة',
                      prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'جدولة الرسالة',
                  onPressed: (_sending || _uploading) ? null : _schedule,
                  icon: const Icon(Icons.schedule_send_rounded),
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
        ),
      ],
    );
  }

  Future<void> _send() async {
    final body = _message.text;
    final assetIds = _attachments.map((asset) => asset.id).toList();
    if (body.trim().isEmpty && assetIds.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.repository.sendMessage(body, assetIds: assetIds);
      _message.clear();
      _attachments.clear();
      setState(() => _messages = _loadMessages());
    } on ApiException catch (error) {
      if (error.code != 'network_error') rethrow;
      await widget.offlineOutbox.enqueueMessage(body, assetIds: assetIds);
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

class _CalendarTab extends StatefulWidget {
  const _CalendarTab({required this.repository});

  final SpaceRepository repository;

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  late Future<List<CalendarItem>> _events = widget.repository.calendarEvents();
  final _title = TextEditingController();
  DateTime _dateValue = DateTime.now();

  @override
  void dispose() {
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
    required this.authRepository,
    required this.hasActivePartnership,
    required this.onSignOut,
  });

  final SpaceRepository repository;
  final AuthRepository authRepository;
  final bool hasActivePartnership;
  final VoidCallback onSignOut;

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
          () => _RoomScreen.music(repository: repository),
        ),
      ),
      _MoreItem(
        'السينما',
        Icons.movie_outlined,
        () => guarded(
          'السينما',
          Icons.movie_outlined,
          () => _RoomScreen.watch(repository: repository),
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
        'Ø§Ù„Ø£Ù„Ø¹Ø§Ø¨',
        Icons.grid_3x3_rounded,
        () => guarded(
          'Ø§Ù„Ø£Ù„Ø¹Ø§Ø¨',
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
          authRepository: authRepository,
          hasActivePartnership: hasActivePartnership,
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
                  childAspectRatio: 2.6,
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value.toString(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
  late Future<TreeDayModel> _future = widget.repository.todayTree();
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الشجرة اليومية')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SectionHeader(
            icon: Icons.park_outlined,
            title: 'ورقة اليوم',
            subtitle: 'اكتبوا ورقة يومية تنمو بها شجرة الذكريات.',
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
            decoration: const InputDecoration(labelText: 'نص الورقة'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة ورقة'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<TreeDayModel>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final leaves = snapshot.requireData.leaves;
              if (leaves.isEmpty) return const Text('لا توجد أوراق اليوم بعد.');
              return Column(
                children: [
                  for (final leaf in leaves)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.eco_outlined),
                        title: Text(leaf.title ?? 'ورقة'),
                        subtitle: Text(leaf.body),
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
    if (_body.text.trim().isEmpty) return;
    await widget.repository.createTreeLeaf(
      title: _title.text,
      body: _body.text,
    );
    _title.clear();
    _body.clear();
    setState(() => _future = widget.repository.todayTree());
  }
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
                        leading: const Icon(Icons.lock_clock_outlined),
                        title: Text(item.title),
                        subtitle: Text('تفتح في ${_date(item.opensAt)}'),
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
  String? _message;

  @override
  void dispose() {
    _reason.dispose();
    _details.dispose();
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

  Future<void> _export() async {
    final data = await widget.repository.exportAccount();
    setState(() => _message = 'تم تجهيز التصدير: ${data.keys.length} أقسام.');
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: const Text('سيتم تعطيل الحساب وإبطال الجلسات.'),
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
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteAccount();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
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
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _emailCode = TextEditingController();
  bool _searchable = true;
  bool _requests = true;
  bool _ready = false;

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _emailCode.dispose();
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
            _displayName.text = profile.displayName;
            _bio.text = profile.bio ?? '';
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
                subtitle: profile.email ?? 'حساب Smiley',
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
              const SizedBox(height: 16),
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(labelText: 'اسم العرض'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bio,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'نبذة قصيرة'),
              ),
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

  Future<void> _save() async {
    await widget.repository.updateProfile(
      displayName: _displayName.text,
      bio: _bio.text,
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
    this.authRepository,
  });

  final SpaceRepository repository;
  final AuthRepository? authRepository;
  final bool hasActivePartnership;

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
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _wish,
            decoration: const InputDecoration(
              labelText: 'أمنية جديدة',
              prefixIcon: Icon(Icons.star_border_rounded),
            ),
            onSubmitted: (_) => _createWish(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _createWish,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة أمنية'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<WishItem>>(
            future: _wishes,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return Column(
                children: [
                  for (final wish in snapshot.requireData)
                    CheckboxListTile(
                      value: wish.completed,
                      onChanged: (_) => _toggleWish(wish.id),
                      title: Text(wish.title),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 32),
          TextField(
            controller: _goal,
            decoration: const InputDecoration(
              labelText: 'هدف جديد',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _steps,
            decoration: const InputDecoration(
              labelText: 'خطوات الهدف مفصولة بفواصل',
              prefixIcon: Icon(Icons.playlist_add_check_rounded),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _createGoal,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة هدف'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<GoalItem>>(
            future: _goals,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return Column(
                children: [
                  for (final goal in snapshot.requireData)
                    Card(
                      child: ExpansionTile(
                        leading: Checkbox(
                          value: goal.completed,
                          onChanged: (_) => _toggleGoal(goal.id),
                        ),
                        title: Text(goal.title),
                        children: [
                          for (final step in goal.steps)
                            CheckboxListTile(
                              value: step.completed,
                              onChanged: (_) => _toggleStep(step.id),
                              title: Text(step.title),
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

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NamedListScreen<AlbumModel>(
      title: 'الألبومات',
      icon: Icons.photo_library_outlined,
      controller: _title,
      future: _future,
      itemTitle: (item) => item.title,
      itemSubtitle: (item) => '${item.itemCount} عناصر',
      onCreate: _create,
    );
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    await widget.repository.createAlbum(_title.text);
    _title.clear();
    setState(() => _future = widget.repository.albums());
  }
}

class _RoomScreen extends StatefulWidget {
  const _RoomScreen.music({required this.repository})
    : title = 'الموسيقى',
      icon = Icons.music_note_rounded,
      load = repositoryMusicRoom,
      add = repositoryAddMusicItem,
      playback = repositoryUpdateMusicPlayback;

  const _RoomScreen.watch({required this.repository})
    : title = 'السينما',
      icon = Icons.movie_outlined,
      load = repositoryWatchRoom,
      add = repositoryAddWatchItem,
      playback = repositoryUpdateWatchPlayback;

  final SpaceRepository repository;
  final String title;
  final IconData icon;
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
  ) {
    return repository.updateMusicPlayback(
      eventType: eventType,
      positionMs: positionMs,
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
  ) {
    return repository.updateWatchPlayback(
      eventType: eventType,
      positionMs: positionMs,
    );
  }
}

class _RoomScreenState extends State<_RoomScreen> {
  late Future<RoomModel> _future = widget.load(widget.repository);
  final _title = TextEditingController();
  final _sourceUrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _sourceUrl.dispose();
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
            subtitle: 'مساحة مشتركة تحفظ ما تريدان سماعه أو مشاهدته.',
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
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<RoomModel>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final room = snapshot.requireData;
              final items = room.items;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RoomPlaybackPanel(
                    room: room,
                    busy: _busy,
                    onPlayback: _playback,
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const Text('لا توجد عناصر بعد.')
                  else
                    for (final item in items)
                      ListTile(
                        leading: Icon(widget.icon),
                        title: Text(item.title),
                        subtitle: Text(item.sourceUrl ?? item.source),
                        trailing: item.sourceUrl == null
                            ? null
                            : const Icon(Icons.open_in_new_rounded),
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

  Future<void> _playback(String eventType) async {
    setState(() => _busy = true);
    try {
      await widget.playback(widget.repository, eventType, null);
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

class _NamedListScreen<T> extends StatelessWidget {
  const _NamedListScreen({
    required this.title,
    required this.icon,
    required this.controller,
    required this.future,
    required this.itemTitle,
    required this.onCreate,
    this.itemSubtitle,
  });

  final String title;
  final IconData icon;
  final TextEditingController controller;
  final Future<List<T>> future;
  final String Function(T item) itemTitle;
  final String Function(T item)? itemSubtitle;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(
            icon: icon,
            title: title,
            subtitle: 'أضفوا العناصر واحفظوها في مساحة العلاقة.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'عنوان جديد'),
            onSubmitted: (_) => onCreate(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<T>>(
            future: future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final items = snapshot.requireData;
              if (items.isEmpty) return const Text('لا توجد عناصر بعد.');
              return Column(
                children: [
                  for (final item in items)
                    ListTile(
                      leading: Icon(icon),
                      title: Text(itemTitle(item)),
                      subtitle: itemSubtitle == null
                          ? null
                          : Text(itemSubtitle!(item)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<String?> _promptText(
  BuildContext context,
  String title, {
  String? initial,
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
          decoration: const InputDecoration(labelText: 'العنوان'),
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
            attachmentCount == 0
                ? 'Ø¥Ø±ÙØ§Ù‚ Ù…Ù„Ù'
                : 'Ø§Ù„Ù…Ø±ÙÙ‚Ø§Øª: $attachmentCount',
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
  const _PostTile({required this.post, this.onReact, this.onComment});

  final SpacePost post;
  final VoidCallback? onReact;
  final VoidCallback? onComment;

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
