import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/secure_stores.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.repository,
    required this.tokenStore,
    required this.onAuthenticated,
    super.key,
  });

  final AuthRepository repository;
  final AuthTokenStore tokenStore;
  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );
  final _loginId = TextEditingController();
  final _loginPassword = TextEditingController();
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _resetId = TextEditingController();
  bool _acceptedTerms = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _tabController.dispose();
    _loginId.dispose();
    _loginPassword.dispose();
    _displayName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _resetId.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    await _run(() {
      return widget.repository.login(
        identifier: _loginId.text.trim(),
        password: _loginPassword.text,
      );
    });
  }

  Future<void> _submitRegister() async {
    await _run(() {
      return widget.repository.register(
        RegisterRequest(
          displayName: _displayName.text.trim(),
          username: _username.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          birthDate: DateTime(2000),
          timezone: DateTime.now().timeZoneName,
          language: 'ar',
          acceptedTerms: _acceptedTerms,
        ),
      );
    });
  }

  Future<void> _submitReset() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.repository.requestPasswordReset(_resetId.text.trim());
      setState(
        () => _message = 'إذا كان الحساب موجودًا ستصل تعليمات الاستعادة.',
      );
    } on ApiException catch (error) {
      setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<AuthSession> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final session = await action();
      await widget.tokenStore.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      if (!mounted) return;
      widget.onAuthenticated(session);
    } on ApiException catch (error) {
      setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Smiley',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'الدخول'),
                      Tab(text: 'حساب جديد'),
                      Tab(text: 'استعادة'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 430,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _LoginForm(
                          identifier: _loginId,
                          password: _loginPassword,
                          busy: _busy,
                          onSubmit: _submitLogin,
                        ),
                        _RegisterForm(
                          displayName: _displayName,
                          username: _username,
                          email: _email,
                          password: _password,
                          acceptedTerms: _acceptedTerms,
                          busy: _busy,
                          onTermsChanged: (value) {
                            setState(() => _acceptedTerms = value);
                          },
                          onSubmit: _submitRegister,
                        ),
                        _ResetForm(
                          identifier: _resetId,
                          busy: _busy,
                          onSubmit: _submitReset,
                        ),
                      ],
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.identifier,
    required this.password,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController identifier;
  final TextEditingController password;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: identifier,
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم أو البريد',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة المرور',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : onSubmit,
          icon: const Icon(Icons.login_rounded),
          label: const Text('تسجيل الدخول'),
        ),
      ],
    );
  }
}

class _RegisterForm extends StatelessWidget {
  const _RegisterForm({
    required this.displayName,
    required this.username,
    required this.email,
    required this.password,
    required this.acceptedTerms,
    required this.busy,
    required this.onTermsChanged,
    required this.onSubmit,
  });

  final TextEditingController displayName;
  final TextEditingController username;
  final TextEditingController email;
  final TextEditingController password;
  final bool acceptedTerms;
  final bool busy;
  final ValueChanged<bool> onTermsChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: displayName,
          decoration: const InputDecoration(
            labelText: 'اسم العرض',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: username,
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم',
            prefixIcon: Icon(Icons.person_search_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'البريد الإلكتروني',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة المرور',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        CheckboxListTile(
          value: acceptedTerms,
          onChanged: (value) => onTermsChanged(value ?? false),
          title: const Text('أوافق على الشروط وسياسة الخصوصية'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: busy ? null : onSubmit,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('إنشاء الحساب'),
        ),
      ],
    );
  }
}

class _ResetForm extends StatelessWidget {
  const _ResetForm({
    required this.identifier,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController identifier;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: identifier,
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم أو البريد',
            prefixIcon: Icon(Icons.mark_email_unread_outlined),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : onSubmit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('إرسال تعليمات الاستعادة'),
        ),
      ],
    );
  }
}
