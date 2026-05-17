import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/constants/app_colors.dart';
import 'core/network/api_client.dart';
import 'core/notification_service.dart';
import 'core/storage/secure_storage.dart';
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

class _AppRouterState extends State<_AppRouter> {
  Widget? _home;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final authenticated = await SecureStorage.isAuthenticated();
    if (!authenticated) {
      _go(_authPage());
      return;
    }

    final role = await SecureStorage.getRole();
    _goRole(role ?? '');
  }

  void _goRole(String role) {
    switch (role) {
      case 'client':
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

  void _onLogout() => _go(_authPage());

  AuthPage _authPage() => AuthPage(onAuthSuccess: _goRole);

  @override
  Widget build(BuildContext context) {
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
