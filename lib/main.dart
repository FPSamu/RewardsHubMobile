import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/constants/app_colors.dart';
import 'core/network/api_client.dart';
import 'core/notification_service.dart';
import 'core/storage/secure_storage.dart';
import 'core/update/update_gate.dart';
import 'core/update/update_service.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/auth_page.dart';
import 'features/client/presentation/client_shell.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    initializeDateFormatting('es', null),
  ]);

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  ApiClient.init();
  await NotificationService.init();

  runApp(const RewardsHubApp());
}

class RewardsHubApp extends StatelessWidget {
  const RewardsHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RewardsHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEBA626),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0B07),
      ),
      home: const _AppRouter(),
    );
  }
}

class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> with WidgetsBindingObserver {
  Widget? _home;

  /// Set once the session died, so a burst of parallel 401s does not rebuild
  /// the login screen repeatedly and so [_resolve] knows not to route past it.
  bool _sessionEnded = false;

  /// Set when the backend refuses this build. Nothing routes past it.
  UpdateStatus? _blockingUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiClient.onSessionExpired = _onSessionExpired;
    _resolve();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ApiClient.onSessionExpired = null;
    super.dispose();
  }

  /// Renewing on resume means the token is refreshed before a screen tries to
  /// use it, instead of every screen firing a 401 at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkForUpdate();
    if (_home is! ClientShell) return;
    ApiClient.ensureValidSession();
  }

  /// Returns true when the build is blocked and the caller must stop routing.
  Future<bool> _checkForUpdate() async {
    final status = await UpdateService.check();
    if (!mounted) return false;

    if (status.isRequired) {
      setState(() => _blockingUpdate = status);
      return true;
    }

    if (status.isOptional && !UpdateService.optionalPromptDismissed) {
      UpdateService.optionalPromptDismissed = true;
      // Deferred so it lands after the frame that shows the destination page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showOptionalUpdateSheet(context, status);
      });
    }
    return false;
  }

  Future<void> _resolve() async {
    // Runs before anything else: an unsupported build must not reach the login
    // screen either. Fails open, so an unreachable backend never blocks anyone.
    if (await _checkForUpdate()) return;

    final authenticated = await SecureStorage.isAuthenticated();
    if (!authenticated) {
      _go(_authPage());
      return;
    }

    final role = await SecureStorage.getRole();
    if (role != 'client') {
      await SecureStorage.clear();
      _go(_authPage());
      return;
    }

    // Renew up front. A network failure is not fatal here — the interceptor
    // still refreshes on demand — but an outright rejection routes to login
    // through _onSessionExpired before any screen loads.
    await ApiClient.ensureValidSession();
    if (_sessionEnded) return;

    NotificationService.syncToken();
    _go(ClientShell(onLogout: _onLogout));
  }

  void _goRole(String role) {
    switch (role) {
      case 'client':
        _sessionEnded = false;
        NotificationService.syncToken();
        _go(ClientShell(onLogout: _onLogout));
      default:
        SecureStorage.clear();
        _go(_authPage());
    }
  }

  void _go(Widget page) {
    if (mounted) setState(() => _home = page);
  }

  void _onSessionExpired() {
    if (_sessionEnded) return;
    _sessionEnded = true;
    _go(_authPage(
      notice: 'Tu sesión expiró. Vuelve a iniciar sesión para continuar.',
    ));
    // Tokens are already cleared; drop the Firebase session too. Kept off the
    // await path so the login screen appears immediately.
    AuthService.signOutLocal();
  }

  void _onLogout() {
    _sessionEnded = false;
    _go(_authPage());
  }

  AuthPage _authPage({String? notice}) =>
      AuthPage(onAuthSuccess: _goRole, notice: notice);

  @override
  Widget build(BuildContext context) {
    final blocking = _blockingUpdate;
    if (blocking != null) return UpdateRequiredScreen(status: blocking);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _home ??
          const Scaffold(
            key: ValueKey('splash'),
            backgroundColor: Color(0xFF0D0B07),
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
    );
  }
}
