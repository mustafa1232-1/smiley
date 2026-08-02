import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/secure_stores.dart';
import '../partnerships/partnership_repository.dart';
import '../space/space_repository.dart';

class EmptyWorldScreen extends StatefulWidget {
  const EmptyWorldScreen({
    required this.partnershipRepository,
    required this.spaceRepository,
    required this.tokenStore,
    required this.onSignedOut,
    super.key,
  });

  final PartnershipRepository partnershipRepository;
  final SpaceRepository spaceRepository;
  final AuthTokenStore tokenStore;
  final VoidCallback onSignedOut;

  @override
  State<EmptyWorldScreen> createState() => _EmptyWorldScreenState();
}

class _EmptyWorldScreenState extends State<EmptyWorldScreen> {
  int _index = 0;
  late Future<_WorldState> _state = _load();

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
              ? _ErrorState(message: snapshot.error.toString(), onRetry: _reload)
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
      return _NoPartnerTab(
        requests: state.requests,
        onAddPartner: _openPartnerSearch,
        onAccept: _acceptRequest,
        onReject: _rejectRequest,
        onCancel: _cancelRequest,
      );
    }

    if (current.needsOnboarding) {
      return _OnboardingTab(
        partnership: current,
        onComplete: _completeOnboarding,
      );
    }

    return switch (_index) {
      0 => _HomeTab(repository: widget.spaceRepository),
      1 => _ChatTab(repository: widget.spaceRepository),
      2 => _WorldTab(repository: widget.spaceRepository),
      3 => _CalendarTab(repository: widget.spaceRepository),
      _ => _MoreTab(onSignOut: _signOut),
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

class _OnboardingTab extends StatefulWidget {
  const _OnboardingTab({
    required this.partnership,
    required this.onComplete,
  });

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
          subtitle: 'حددوا اسم العالم وتاريخ البداية ليتم تفعيل التجربة المشتركة.',
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
  bool _posting = false;

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
          return _ErrorState(message: snapshot.error.toString(), onRetry: _reload);
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
                onSubmit: _createPost,
              ),
              const SizedBox(height: 20),
              if (summary.latestMood != null)
                _InfoTile(
                  icon: Icons.mood_rounded,
                  title: 'آخر مزاج',
                  subtitle: summary.latestMood!.note ?? summary.latestMood!.kind,
                ),
              if (summary.nextEvent != null)
                _InfoTile(
                  icon: Icons.event_rounded,
                  title: 'الموعد القادم',
                  subtitle:
                      '${summary.nextEvent!.title} - ${_date(summary.nextEvent!.startsAt)}',
                ),
              const SizedBox(height: 10),
              Text('آخر الذكريات', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (summary.latestPosts.isEmpty)
                const _EmptyLine(text: 'لا توجد ذكريات بعد.', color: Colors.grey)
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
    if (_post.text.trim().isEmpty) return;
    setState(() => _posting = true);
    try {
      await widget.repository.createPost(body: _post.text);
      _post.clear();
      _reload();
    } finally {
      if (mounted) setState(() => _posting = false);
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
  late Future<List<ChatMessage>> _messages = widget.repository.messages();
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
      setState(() => _messages = widget.repository.messages());
    } finally {
      if (mounted) setState(() => _sending = false);
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
              return const _EmptyLine(text: 'لا توجد مواعيد بعد.', color: Colors.grey);
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
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
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
        FilledButton.icon(
          onPressed: busy ? null : onSubmit,
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
        subtitle: post.title == null ? Text(_date(post.createdAt)) : Text(post.body),
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

String _two(int value) => value.toString().padLeft(2, '0');
