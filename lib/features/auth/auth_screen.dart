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
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _resetId = TextEditingController();
  final _resetToken = TextEditingController();
  final _resetPassword = TextEditingController();
  DateTime? _birthDate;
  String? _gender;
  String _language = 'ar';
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
    _phone.dispose();
    _password.dispose();
    _resetId.dispose();
    _resetToken.dispose();
    _resetPassword.dispose();
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
    final validationMessage = _validateRegister();
    if (validationMessage != null) {
      setState(() => _message = validationMessage);
      return;
    }

    await _run(() {
      return widget.repository.register(
        RegisterRequest(
          displayName: _displayName.text.trim(),
          username: _username.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text,
          birthDate: _birthDate!,
          gender: _gender,
          timezone: DateTime.now().timeZoneName,
          language: _language,
          acceptedTerms: _acceptedTerms,
        ),
      );
    });
  }

  String? _validateRegister() {
    if (_displayName.text.trim().isEmpty ||
        _username.text.trim().isEmpty ||
        (_email.text.trim().isEmpty && _phone.text.trim().isEmpty) ||
        _password.text.isEmpty ||
        _birthDate == null) {
      return 'أكمل بيانات الحساب أولاً.';
    }
    if (_password.text.length < 10) {
      return 'كلمة المرور يجب أن تكون 10 أحرف على الأقل.';
    }
    if (!_acceptedTerms) {
      return 'يجب الموافقة على الشروط وسياسة الخصوصية.';
    }
    return null;
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

  Future<void> _confirmReset() async {
    if (_resetToken.text.trim().isEmpty || _resetPassword.text.length < 10) {
      setState(() => _message = 'أدخل رمز الاستعادة وكلمة مرور جديدة قوية.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.repository.confirmPasswordReset(
        token: _resetToken.text.trim(),
        password: _resetPassword.text,
      );
      _resetToken.clear();
      _resetPassword.clear();
      setState(
        () => _message = 'تم تحديث كلمة المرور. يمكنك تسجيل الدخول الآن.',
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
                    height: 560,
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
                          phone: _phone,
                          password: _password,
                          birthDate: _birthDate,
                          gender: _gender,
                          language: _language,
                          acceptedTerms: _acceptedTerms,
                          busy: _busy,
                          onBirthDatePressed: _pickBirthDate,
                          onGenderChanged: (value) {
                            setState(() => _gender = value);
                          },
                          onLanguageChanged: (value) {
                            if (value == null) return;
                            setState(() => _language = value);
                          },
                          onTermsChanged: (value) {
                            setState(() => _acceptedTerms = value);
                          },
                          onSubmit: _submitRegister,
                        ),
                        _ResetForm(
                          identifier: _resetId,
                          token: _resetToken,
                          password: _resetPassword,
                          busy: _busy,
                          onSubmit: _submitReset,
                          onConfirm: _confirmReset,
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
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(
          controller: identifier,
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم أو البريد أو الهاتف',
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
    required this.phone,
    required this.password,
    required this.birthDate,
    required this.gender,
    required this.language,
    required this.acceptedTerms,
    required this.busy,
    required this.onBirthDatePressed,
    required this.onGenderChanged,
    required this.onLanguageChanged,
    required this.onTermsChanged,
    required this.onSubmit,
  });

  final TextEditingController displayName;
  final TextEditingController username;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController password;
  final DateTime? birthDate;
  final String? gender;
  final String language;
  final bool acceptedTerms;
  final bool busy;
  final VoidCallback onBirthDatePressed;
  final ValueChanged<String?> onGenderChanged;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<bool> onTermsChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
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
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف اختياري',
            prefixIcon: Icon(Icons.phone_outlined),
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : onBirthDatePressed,
          icon: const Icon(Icons.cake_outlined),
          label: Text(
            birthDate == null
                ? 'اختر تاريخ الميلاد'
                : '${birthDate!.year}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: gender,
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
          onChanged: busy ? null : onGenderChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: language,
          decoration: const InputDecoration(
            labelText: 'اللغة',
            prefixIcon: Icon(Icons.language_rounded),
          ),
          items: const [
            DropdownMenuItem(value: 'ar', child: Text('العربية')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: busy ? null : onLanguageChanged,
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
    required this.token,
    required this.password,
    required this.busy,
    required this.onSubmit,
    required this.onConfirm,
  });

  final TextEditingController identifier;
  final TextEditingController token;
  final TextEditingController password;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: identifier,
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم أو البريد أو الهاتف',
            prefixIcon: Icon(Icons.mark_email_unread_outlined),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : onSubmit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('إرسال تعليمات الاستعادة'),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: token,
          decoration: const InputDecoration(
            labelText: 'رمز الاستعادة',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة المرور الجديدة',
            prefixIcon: Icon(Icons.lock_reset_rounded),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : onConfirm,
          icon: const Icon(Icons.check_rounded),
          label: const Text('تحديث كلمة المرور'),
        ),
      ],
    );
  }
}
