import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/secure_stores.dart';
import 'features/auth/auth_models.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/auth_screen.dart';
import 'features/gate/date_gate_screen.dart';
import 'features/gate/gate_validator.dart';
import 'features/home/empty_world_screen.dart';
import 'features/partnerships/partnership_repository.dart';

void main() {
  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  final tokenStore = SecureAuthTokenStore();
  final apiClient = ApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: tokenStore.readAccessToken,
  );

  runApp(
    SmileyApp(
      gateStore: const SecureGateStore(),
      tokenStore: tokenStore,
      authRepository: HttpAuthRepository(apiClient),
      partnershipRepository: HttpPartnershipRepository(apiClient),
    ),
  );
}

class SmileyApp extends StatelessWidget {
  const SmileyApp({
    required this.gateStore,
    required this.tokenStore,
    required this.authRepository,
    required this.partnershipRepository,
    super.key,
  });

  final GateStore gateStore;
  final AuthTokenStore tokenStore;
  final AuthRepository authRepository;
  final PartnershipRepository partnershipRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smiley',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _Bootstrap(
        gateStore: gateStore,
        tokenStore: tokenStore,
        authRepository: authRepository,
        partnershipRepository: partnershipRepository,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFB96B7F),
          brightness: brightness,
        ).copyWith(
          primary: const Color(0xFFB96B7F),
          secondary: const Color(0xFF4B9A8D),
          tertiary: const Color(0xFFD5A021),
          surface: isDark ? const Color(0xFF181416) : const Color(0xFFFFFBFB),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF120F11)
          : const Color(0xFFFFF8F8),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap({
    required this.gateStore,
    required this.tokenStore,
    required this.authRepository,
    required this.partnershipRepository,
  });

  final GateStore gateStore;
  final AuthTokenStore tokenStore;
  final AuthRepository authRepository;
  final PartnershipRepository partnershipRepository;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<_BootstrapStateModel> _stateFuture = _load();

  Future<_BootstrapStateModel> _load() async {
    final gateUnlocked = await widget.gateStore.isUnlocked();
    final accessToken = await widget.tokenStore.readAccessToken();
    return _BootstrapStateModel(gateUnlocked, accessToken != null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapStateModel>(
      future: _stateFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _BootScreen();
        }

        final state = snapshot.requireData;
        if (!state.gateUnlocked) {
          return DateGateScreen(
            store: widget.gateStore,
            validator: const GateValidator(),
            onUnlocked: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => AuthScreen(
                  repository: widget.authRepository,
                  tokenStore: widget.tokenStore,
                  onAuthenticated: _openWorld,
                ),
              ),
            ),
          );
        }

        if (!state.authenticated) {
          return AuthScreen(
            repository: widget.authRepository,
            tokenStore: widget.tokenStore,
            onAuthenticated: _openWorld,
          );
        }

        return EmptyWorldScreen(
          partnershipRepository: widget.partnershipRepository,
          tokenStore: widget.tokenStore,
          onSignedOut: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => AuthScreen(
                repository: widget.authRepository,
                tokenStore: widget.tokenStore,
                onAuthenticated: _openWorld,
              ),
            ),
          ),
        );
      },
    );
  }

  void _openWorld(AuthSession session) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EmptyWorldScreen(
          partnershipRepository: widget.partnershipRepository,
          tokenStore: widget.tokenStore,
          onSignedOut: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => AuthScreen(
                repository: widget.authRepository,
                tokenStore: widget.tokenStore,
                onAuthenticated: _openWorld,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapStateModel {
  const _BootstrapStateModel(this.gateUnlocked, this.authenticated);

  final bool gateUnlocked;
  final bool authenticated;
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
