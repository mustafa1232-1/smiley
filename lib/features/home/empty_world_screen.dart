import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/secure_stores.dart';
import '../partnerships/partnership_repository.dart';

class EmptyWorldScreen extends StatefulWidget {
  const EmptyWorldScreen({
    required this.partnershipRepository,
    required this.tokenStore,
    required this.onSignedOut,
    super.key,
  });

  final PartnershipRepository partnershipRepository;
  final AuthTokenStore tokenStore;
  final VoidCallback onSignedOut;

  @override
  State<EmptyWorldScreen> createState() => _EmptyWorldScreenState();
}

class _EmptyWorldScreenState extends State<EmptyWorldScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeTab(onAddPartner: _openPartnerSearch),
      const _PlaceholderTab(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'المحادثة',
      ),
      const _PlaceholderTab(
        icon: Icons.auto_awesome_rounded,
        title: 'عالم Smiley',
      ),
      const _PlaceholderTab(
        icon: Icons.calendar_month_rounded,
        title: 'التقويم',
      ),
      _MoreTab(onSignOut: _signOut),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Smiley')),
      body: pages[_index],
      floatingActionButton: FloatingActionButton(
        onPressed: _openPartnerSearch,
        tooltip: 'إضافة',
        child: const Icon(Icons.add_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
  }

  Future<void> _signOut() async {
    await widget.tokenStore.clear();
    if (!mounted) return;
    widget.onSignedOut();
  }

  void _openPartnerSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PartnerSearchScreen(repository: widget.partnershipRepository),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.onAddPartner});

  final VoidCallback onAddPartner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.public_rounded,
                        size: 52,
                        color: scheme.secondary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'العالم لم يبدأ بعد',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'أضف الشريك عندما يكون الحسابان جاهزين. لن تظهر ذكريات أو عدادات قبل قبول الطلب وإكمال الإعداد المشترك.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: onAddPartner,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('إضافة شريك'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            ListTile(
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
        ],
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: scheme.secondary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
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
      ('المناسبات', Icons.event_available_outlined),
      ('الألعاب', Icons.extension_outlined),
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
