import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/realtime_client.dart';
import '../../core/secure_stores.dart';
import '../auth/auth_repository.dart';
import '../partnerships/partnership_repository.dart';
import '../space/space_repository.dart';

class EmptyWorldScreen extends StatefulWidget {
  const EmptyWorldScreen({
    required this.partnershipRepository,
    required this.spaceRepository,
    required this.authRepository,
    required this.realtimeClient,
    required this.tokenStore,
    required this.onSignedOut,
    super.key,
  });

  final PartnershipRepository partnershipRepository;
  final SpaceRepository spaceRepository;
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
          onAddPartner: _openPartnerSearch,
          onAccept: _acceptRequest,
          onReject: _rejectRequest,
          onCancel: _cancelRequest,
        ),
        1 => _PartnerRequiredTab(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'المحادثة',
          onAddPartner: _openPartnerSearch,
        ),
        2 => _PartnerRequiredTab(
          icon: Icons.favorite_border_rounded,
          title: 'عالم Smiley',
          onAddPartner: _openPartnerSearch,
        ),
        3 => _PartnerRequiredTab(
          icon: Icons.calendar_month_rounded,
          title: 'التقويم',
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
          onAddPartner: _reload,
        ),
      };
    }

    return switch (_index) {
      0 => _HomeTab(repository: widget.spaceRepository),
      1 => _ChatTab(repository: widget.spaceRepository),
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
    required this.onAddPartner,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
  });

  final List<PartnershipRequest> requests;
  final VoidCallback onAddPartner;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onReject;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: () async => onAddPartner,
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
  });

  final IconData icon;
  final String title;
  final String message;
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
                label: const Text('إضافة شريك'),
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
  const _HomeTab({required this.repository});

  final SpaceRepository repository;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  late Future<SpaceSummary> _summary = widget.repository.summary();
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
                for (final post in summary.latestPosts) _PostTile(post: post),
            ],
          ),
        );
      },
    );
  }

  void _reload() {
    setState(() => _summary = widget.repository.summary());
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
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _attachMedia() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
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
              children: [for (final post in posts) _PostTile(post: post)],
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
}

class _ChatTab extends StatefulWidget {
  const _ChatTab({required this.repository});

  final SpaceRepository repository;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  late Future<List<ChatMessage>> _messages = _loadMessages();
  final _message = TextEditingController();
  bool _sending = false;

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
                        child: Text(item.body),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
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
                  onPressed: _sending ? null : _send,
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
    if (_message.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.repository.sendMessage(_message.text);
      _message.clear();
      setState(() => _messages = _loadMessages());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<List<ChatMessage>> _loadMessages() async {
    final items = await widget.repository.messages();
    if (items.isNotEmpty) {
      try {
        await widget.repository.readAllMessages();
      } on ApiException {
        // Reading receipts should not block the conversation view.
      }
    }
    return items;
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
  bool _searchable = true;
  bool _requests = true;
  bool _ready = false;

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
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
  bool _busy = false;

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
          if (games.isEmpty) {
            return const Center(child: Text('لا توجد ألعاب بعد.'));
          }
          final game = games.first;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NamedListScreen<PlaceItem>(
      title: 'خريطة الذكريات',
      icon: Icons.map_outlined,
      controller: _title,
      future: _future,
      itemTitle: (item) => item.title,
      onCreate: _create,
    );
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    await widget.repository.createPlace(_title.text);
    _title.clear();
    setState(() => _future = widget.repository.places());
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
      add = repositoryAddMusicItem;

  const _RoomScreen.watch({required this.repository})
    : title = 'السينما',
      icon = Icons.movie_outlined,
      load = repositoryWatchRoom,
      add = repositoryAddWatchItem;

  final SpaceRepository repository;
  final String title;
  final IconData icon;
  final Future<RoomModel> Function(SpaceRepository repository) load;
  final Future<void> Function(SpaceRepository repository, String title) add;

  @override
  State<_RoomScreen> createState() => _RoomScreenState();

  static Future<RoomModel> repositoryMusicRoom(SpaceRepository repository) {
    return repository.musicRoom();
  }

  static Future<void> repositoryAddMusicItem(
    SpaceRepository repository,
    String title,
  ) {
    return repository.addMusicItem(title);
  }

  static Future<RoomModel> repositoryWatchRoom(SpaceRepository repository) {
    return repository.watchRoom();
  }

  static Future<void> repositoryAddWatchItem(
    SpaceRepository repository,
    String title,
  ) {
    return repository.addWatchItem(title);
  }
}

class _RoomScreenState extends State<_RoomScreen> {
  late Future<RoomModel> _future = widget.load(widget.repository);
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
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
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة'),
          ),
          const SizedBox(height: 16),
          FutureBuilder<RoomModel>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final items = snapshot.requireData.items;
              if (items.isEmpty) return const Text('لا توجد عناصر بعد.');
              return Column(
                children: [
                  for (final item in items)
                    ListTile(
                      leading: Icon(widget.icon),
                      title: Text(item.title),
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
    await widget.add(widget.repository, _title.text);
    _title.clear();
    setState(() => _future = widget.load(widget.repository));
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

Future<String?> _promptText(BuildContext context, String title) {
  final controller = TextEditingController();
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
  const _PostTile({required this.post});

  final SpacePost post;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.favorite_border_rounded),
        title: Text(post.title ?? post.body),
        subtitle: post.title == null
            ? Text(_date(post.createdAt))
            : Text(post.body),
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

String _two(int value) => value.toString().padLeft(2, '0');
