import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/offline_outbox.dart';
import 'core/push_service.dart';
import 'core/realtime_client.dart';
import 'core/secure_stores.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/auth_screen.dart';
import 'features/gate/date_gate_screen.dart';
import 'features/gate/gate_validator.dart';
import 'features/home/empty_world_screen.dart';
import 'features/partnerships/partnership_repository.dart';
import 'features/space/space_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://smiley-smiley.up.railway.app/api/v1',
  );

  final tokenStore = SecureAuthTokenStore();
  final realtimeUrl = apiBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
  final apiClient = ApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: tokenStore.readAccessToken,
    refreshTokenProvider: tokenStore.readRefreshToken,
    tokenSaver: tokenStore.saveTokens,
    onAuthFailed: tokenStore.clear,
  );
  final realtimeClient = RealtimeClient(
    serverUrl: realtimeUrl,
    tokenProvider: tokenStore.readAccessToken,
  );
  final spaceRepository = HttpSpaceRepository(apiClient);

  await initializeFirebaseForPush();
  final pushService = PushService(
    registerToken: (token, platform) async {
      // Only register once the user is signed in (endpoint is authenticated).
      if (await tokenStore.readAccessToken() == null) return;
      await spaceRepository.registerPushToken(token: token, platform: platform);
    },
  );

  runApp(
    SmileyApp(
      gateStore: const SecureGateStore(),
      tokenStore: tokenStore,
      authRepository: HttpAuthRepository(apiClient),
      partnershipRepository: HttpPartnershipRepository(apiClient),
      spaceRepository: spaceRepository,
      offlineOutbox: const SharedPreferencesOfflineOutbox(),
      realtimeClient: realtimeClient,
      pushService: pushService,
    ),
  );
}

class SmileyApp extends StatelessWidget {
  const SmileyApp({
    required this.gateStore,
    required this.tokenStore,
    required this.authRepository,
    required this.partnershipRepository,
    required this.spaceRepository,
    required this.offlineOutbox,
    required this.realtimeClient,
    required this.pushService,
    super.key,
  });

  final GateStore gateStore;
  final AuthTokenStore tokenStore;
  final AuthRepository authRepository;
  final PartnershipRepository partnershipRepository;
  final SpaceRepository spaceRepository;
  final OfflineOutbox offlineOutbox;
  final RealtimeClient realtimeClient;
  final PushService pushService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smiley',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      // Arabic locale so built-in Material widgets (date pickers, tooltips,
      // dialogs) render in Arabic with correct right-to-left layout.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
        spaceRepository: spaceRepository,
        offlineOutbox: offlineOutbox,
        realtimeClient: realtimeClient,
        pushService: pushService,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    // Vibrant lavender theme with playful pink/amber accents.
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: brightness,
        ).copyWith(
          primary: const Color(0xFF7C4DFF),
          secondary: const Color(0xFFFF5FA2),
          tertiary: const Color(0xFFFFB300),
          surface: isDark ? const Color(0xFF181425) : const Color(0xFFFDFAFF),
        );

    const transitions = PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _LivelyPageTransitionsBuilder(),
        TargetPlatform.iOS: _LivelyPageTransitionsBuilder(),
        TargetPlatform.macOS: _LivelyPageTransitionsBuilder(),
        TargetPlatform.windows: _LivelyPageTransitionsBuilder(),
        TargetPlatform.linux: _LivelyPageTransitionsBuilder(),
      },
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF120E1C)
          : const Color(0xFFF4EEFF),
      // Animated sparkle ripple on every tap for a livelier feel.
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: transitions,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.primary,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: scheme.primary.withValues(alpha: 0.18),
        surfaceTintColor: scheme.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

/// A livelier default page transition: fade combined with a gentle upward
/// slide, applied to every route push across all platforms.
class _LivelyPageTransitionsBuilder extends PageTransitionsBuilder {
  const _LivelyPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: child,
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
    required this.spaceRepository,
    required this.offlineOutbox,
    required this.realtimeClient,
    required this.pushService,
  });

  final GateStore gateStore;
  final AuthTokenStore tokenStore;
  final AuthRepository authRepository;
  final PartnershipRepository partnershipRepository;
  final SpaceRepository spaceRepository;
  final OfflineOutbox offlineOutbox;
  final RealtimeClient realtimeClient;
  final PushService pushService;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  bool? _gateUnlocked;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gateUnlocked = await widget.gateStore.isUnlocked();
    final accessToken = await widget.tokenStore.readAccessToken();
    if (!mounted) return;
    setState(() {
      _gateUnlocked = gateUnlocked;
      _authenticated = accessToken != null;
    });
    if (accessToken != null) _registerPush();
  }

  // Sets up push (idempotent) and registers the device token now that the user
  // is authenticated.
  Future<void> _registerPush() async {
    await widget.pushService.initialize();
    await widget.pushService.registerCurrentToken();
  }

  void _onAuthenticated() {
    setState(() => _authenticated = true);
    _registerPush();
  }

  // Declarative routing: flipping state rebuilds into the right screen
  // immediately, so login/logout/gate transitions happen without relying on
  // an imperative Navigator call from a possibly-stale context.
  @override
  Widget build(BuildContext context) {
    final gateUnlocked = _gateUnlocked;
    if (gateUnlocked == null) {
      return const _BootScreen();
    }

    if (!gateUnlocked) {
      return DateGateScreen(
        store: widget.gateStore,
        validator: const GateValidator(),
        onUnlocked: () => setState(() => _gateUnlocked = true),
      );
    }

    if (!_authenticated) {
      return AuthScreen(
        repository: widget.authRepository,
        tokenStore: widget.tokenStore,
        onAuthenticated: (_) => _onAuthenticated(),
      );
    }

    return EmptyWorldScreen(
      partnershipRepository: widget.partnershipRepository,
      spaceRepository: widget.spaceRepository,
      offlineOutbox: widget.offlineOutbox,
      authRepository: widget.authRepository,
      realtimeClient: widget.realtimeClient,
      tokenStore: widget.tokenStore,
      onSignedOut: () => setState(() => _authenticated = false),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, size: 76, color: scheme.secondary),
              const SizedBox(height: 16),
              Text(
                'Smiley',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
