import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../data/auth_service.dart';
import 'widgets/auth_header.dart';
import 'widgets/login_form_section.dart';
import 'widgets/signup_form_section.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    this.initialMode = 'login',
    this.onAuthSuccess,
    this.notice,
  });

  final String initialMode; // 'login' | 'signup'
  final void Function(String role)? onAuthSuccess;

  /// Explains why the user landed back here, e.g. an expired session. Cleared
  /// as soon as they submit, so it never lingers over a real login error.
  final String? notice;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late String _mode; // 'login' | 'signup'
  String? _notice;
  String _accountType = 'client'; // 'client' | 'business'

  // Login controllers
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _rememberMe = false;

  // Signup controllers
  final _signupNameCtrl = TextEditingController();
  final _signupEmailCtrl = TextEditingController();
  final _signupPasswordCtrl = TextEditingController();
  final _signupConfirmCtrl = TextEditingController();

  bool _loading = false;
  String? _loginError;
  String? _signupError;

  @override
  void initState() {
    super.initState();
    _notice = widget.notice;
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _signupNameCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPasswordCtrl.dispose();
    _signupConfirmCtrl.dispose();
    super.dispose();
  }

  // ── Navigation after auth ─────────────────────────────────────────────────

  void _handleAuthSuccess(Map<String, dynamic> data) {
    final user = data['user'] as Map<String, dynamic>?;
    final role = data['role'] as String?;

    if (user?['isVerified'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifica tu correo para continuar')),
      );
      return;
    }

    // API returns 'user' for clients — map to internal role before routing
    final internalRole = role == 'user' ? 'client' : (role ?? 'client');
    widget.onAuthSuccess?.call(internalRole);
  }

  // ── Terms ─────────────────────────────────────────────────────────────────

  Future<void> _openBusinessWebSignup() async {
    await launchUrl(
      Uri.parse('https://rewardshub.cloud/signup'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openTerms() async {
    await launchUrl(
      Uri.parse('https://rewardshub.cloud/terminos'),
      mode: LaunchMode.externalApplication,
    );
  }

  // ── Mode switch ───────────────────────────────────────────────────────────

  void _switchMode(String newMode) {
    if (newMode == _mode) return;
    setState(() {
      _mode = newMode;
      _loginError = null;
      _signupError = null;
    });
  }

  // ── Login handlers ────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    setState(() {
      _loading = true;
      _loginError = null;
    });
    try {
      final data = await AuthService.login(
        _loginEmailCtrl.text.trim(),
        _loginPasswordCtrl.text,
      );
      _handleAuthSuccess(data);
    } catch (e) {
      setState(() => _loginError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleLoginGoogle() async {
    setState(() {
      _loading = true;
      _loginError = null;
    });
    try {
      final data = await AuthService.loginWithGoogle();
      _handleAuthSuccess(data);
    } catch (e) {
      setState(() => _loginError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Signup handlers ───────────────────────────────────────────────────────

  Future<void> _handleSignup() async {
    if (_signupPasswordCtrl.text != _signupConfirmCtrl.text) {
      setState(() => _signupError = 'Las contraseñas no coinciden.');
      return;
    }
    if (_signupPasswordCtrl.text.length < 6) {
      setState(() => _signupError = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    setState(() {
      _loading = true;
      _signupError = null;
    });
    try {
      final apiRole = _accountType == 'client' ? 'user' : 'business';
      final data = await AuthService.register(
        email: _signupEmailCtrl.text.trim(),
        password: _signupPasswordCtrl.text,
        role: apiRole,
        username: _signupNameCtrl.text.trim(),
      );
      _handleAuthSuccess(data);
    } catch (e) {
      setState(() => _signupError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleSignupGoogle() async {
    setState(() {
      _loading = true;
      _signupError = null;
    });
    try {
      final apiRole = _accountType == 'client' ? 'user' : 'business';
      final data = await AuthService.registerWithGoogle(apiRole);
      _handleAuthSuccess(data);
    } catch (e) {
      setState(() => _signupError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        children: [
          // Dark hero header
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: AuthHeader(
              key: ValueKey('${_mode}_$_accountType'),
              mode: _mode,
              accountType: _accountType,
            ),
          ),

          // White form card
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Mode tab switcher
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: _ModeSwitcher(
                      selected: _mode,
                      onChanged: _switchMode,
                    ),
                  ),

                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: _SessionNotice(message: _notice!),
                    ),

                  // Form content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.04),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: _mode == 'login'
                            ? LoginFormSection(
                                key: const ValueKey('login'),
                                emailController: _loginEmailCtrl,
                                passwordController: _loginPasswordCtrl,
                                rememberMe: _rememberMe,
                                onRememberMeChanged: (v) =>
                                    setState(() => _rememberMe = v),
                                onSubmit: _handleLogin,
                                onGoogleTap: _handleLoginGoogle,
                                loading: _loading,
                                error: _loginError,
                                onSwitchToSignup: () => _switchMode('signup'),
                                onForgotPassword: () {
                                  debugPrint('Navigate to forgot password');
                                },
                              )
                            : SignupFormSection(
                                key: const ValueKey('signup'),
                                accountType: _accountType,
                                onAccountTypeChanged: (t) =>
                                    setState(() => _accountType = t),
                                nameController: _signupNameCtrl,
                                emailController: _signupEmailCtrl,
                                passwordController: _signupPasswordCtrl,
                                confirmPasswordController: _signupConfirmCtrl,
                                onSubmit: _handleSignup,
                                onGoogleTap: _handleSignupGoogle,
                                loading: _loading,
                                error: _signupError,
                                onSwitchToLogin: () => _switchMode('login'),
                                onTermsTap: _openTerms,
                                onBusinessWebSignup: _openBusinessWebSignup,
                              ),
                      ),
                    ),
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

// ── Mode switcher (Iniciar Sesión | Crear Cuenta) ─────────────────────────────

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'Iniciar Sesión',
            selected: selected == 'login',
            onTap: () => onChanged('login'),
          ),
          _Tab(
            label: 'Crear Cuenta',
            selected: selected == 'signup',
            onTap: () => onChanged('signup'),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 42,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.white : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Neutral, non-alarming banner for "you were signed out" style messages.
/// The red [AppAlertMessage] is reserved for failed login attempts.
class _SessionNotice extends StatelessWidget {
  const _SessionNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_clock_rounded,
              size: 16, color: AppColors.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryDark,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
