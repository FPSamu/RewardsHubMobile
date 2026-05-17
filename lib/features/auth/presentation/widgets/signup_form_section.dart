import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../components/app_alert_message.dart';
import '../components/app_auth_divider.dart';
import '../components/app_form_input.dart';
import '../components/app_password_input.dart';
import '../components/app_social_button.dart';
import '../components/app_submit_button.dart';
import 'account_type_toggle.dart';

class SignupFormSection extends StatefulWidget {
  const SignupFormSection({
    super.key,
    required this.accountType,
    required this.onAccountTypeChanged,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.onSubmit,
    required this.onGoogleTap,
    required this.loading,
    this.error,
    required this.onSwitchToLogin,
    required this.onTermsTap,
    required this.onBusinessWebSignup,
  });

  final String accountType; // 'client' | 'business'
  final ValueChanged<String> onAccountTypeChanged;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final VoidCallback onSubmit;
  final VoidCallback onGoogleTap;
  final bool loading;
  final String? error;
  final VoidCallback onSwitchToLogin;
  final VoidCallback onTermsTap;
  final VoidCallback onBusinessWebSignup;

  @override
  State<SignupFormSection> createState() => _SignupFormSectionState();
}

class _SignupFormSectionState extends State<SignupFormSection> {
  bool _termsAccepted = false;

  bool get _canSubmit => _termsAccepted && !widget.loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        const Text(
          'Crea tu cuenta',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.4,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Elige tu tipo de cuenta y empieza gratis',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 20),

        // Account type toggle
        AccountTypeToggle(
          value: widget.accountType,
          onChanged: (t) {
            setState(() => _termsAccepted = false);
            widget.onAccountTypeChanged(t);
          },
        ),
        const SizedBox(height: 20),

        // Content switches based on account type
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: widget.accountType == 'business'
              ? _BusinessSignupPanel(
                  key: const ValueKey('business'),
                  onWebSignup: widget.onBusinessWebSignup,
                  onSwitchToLogin: widget.onSwitchToLogin,
                )
              : _ClientSignupForm(
                  key: const ValueKey('client'),
                  nameController: widget.nameController,
                  emailController: widget.emailController,
                  passwordController: widget.passwordController,
                  confirmPasswordController: widget.confirmPasswordController,
                  error: widget.error,
                  loading: widget.loading,
                  canSubmit: _canSubmit,
                  termsAccepted: _termsAccepted,
                  onTermsChanged: (v) => setState(() => _termsAccepted = v),
                  onTermsTap: widget.onTermsTap,
                  onSubmit: widget.onSubmit,
                  onGoogleTap: widget.onGoogleTap,
                  onSwitchToLogin: widget.onSwitchToLogin,
                ),
        ),
      ],
    );
  }
}

// ── Business: redirect to web ─────────────────────────────────────────────────

class _BusinessSignupPanel extends StatelessWidget {
  const _BusinessSignupPanel({
    super.key,
    required this.onWebSignup,
    required this.onSwitchToLogin,
  });

  final VoidCallback onWebSignup;
  final VoidCallback onSwitchToLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Info card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primaryMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.store_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Plataforma para Negocios',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'La gestión de negocios en RewardsHub se realiza completamente desde la plataforma web. Desde ahí podrás registrarte, configurar tu programa de puntos y administrar todo.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Esta app móvil es exclusiva para clientes.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Bullets
        ...[
          ('Escanea QR de clientes', Icons.qr_code_scanner_rounded),
          ('Configura tu sistema de puntos', Icons.stars_rounded),
          ('Gestiona tu base de clientes', Icons.people_outline_rounded),
        ].map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.$2, size: 14, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Text(
                  item.$1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // CTA button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: onWebSignup,
            icon: const Icon(Icons.open_in_browser_rounded, size: 18),
            label: const Text(
              'Ir a la Plataforma Web',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ).copyWith(
              elevation: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.pressed) ? 2 : 6,
              ),
              shadowColor: WidgetStatePropertyAll(
                AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Switch to login
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              const Text(
                '¿Ya tienes una cuenta? ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
              GestureDetector(
                onTap: onSwitchToLogin,
                child: const Text(
                  'Inicia sesión',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Client: full signup form ──────────────────────────────────────────────────

class _ClientSignupForm extends StatelessWidget {
  const _ClientSignupForm({
    super.key,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.error,
    required this.loading,
    required this.canSubmit,
    required this.termsAccepted,
    required this.onTermsChanged,
    required this.onTermsTap,
    required this.onSubmit,
    required this.onGoogleTap,
    required this.onSwitchToLogin,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final String? error;
  final bool loading;
  final bool canSubmit;
  final bool termsAccepted;
  final ValueChanged<bool> onTermsChanged;
  final VoidCallback onTermsTap;
  final VoidCallback onSubmit;
  final VoidCallback onGoogleTap;
  final VoidCallback onSwitchToLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null && error!.isNotEmpty) ...[
          AppAlertMessage(message: error!),
          const SizedBox(height: 16),
        ],

        AppFormInput(
          controller: nameController,
          label: 'Nombre Completo',
          placeholder: 'Juan Pérez',
          textInputAction: TextInputAction.next,
          prefixIcon: const Icon(Icons.person_outline_rounded),
        ),
        const SizedBox(height: 16),

        AppFormInput(
          controller: emailController,
          label: 'Correo Electrónico',
          placeholder: 'correo@ejemplo.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          prefixIcon: const Icon(Icons.mail_outline_rounded),
        ),
        const SizedBox(height: 16),

        AppPasswordInput(
          controller: passwordController,
          label: 'Contraseña',
          hint: 'Mínimo 6 caracteres',
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 16),

        AppPasswordInput(
          controller: confirmPasswordController,
          label: 'Confirmar Contraseña',
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 16),

        _TermsRow(
          accepted: termsAccepted,
          onChanged: onTermsChanged,
          onTermsTap: onTermsTap,
        ),
        const SizedBox(height: 20),

        AppSubmitButton(
          label: 'Crear Cuenta de Cliente',
          loadingLabel: 'Creando cuenta...',
          onPressed: onSubmit,
          loading: loading,
          enabled: canSubmit,
        ),
        const SizedBox(height: 16),

        const AppAuthDivider(),
        const SizedBox(height: 16),

        AppSocialButton(
          onPressed: onGoogleTap,
          disabled: !canSubmit,
        ),
        const SizedBox(height: 24),

        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              const Text(
                '¿Ya tienes una cuenta? ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
              GestureDetector(
                onTap: onSwitchToLogin,
                child: const Text(
                  'Inicia sesión',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Terms checkbox ────────────────────────────────────────────────────────────

class _TermsRow extends StatelessWidget {
  const _TermsRow({
    required this.accepted,
    required this.onChanged,
    required this.onTermsTap,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTermsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: accepted,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            side: const BorderSide(color: AppColors.border, width: 1.5),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: 'He leído y acepto los ',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: 'términos y condiciones',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.primary,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = onTermsTap,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
