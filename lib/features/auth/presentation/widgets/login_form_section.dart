import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../components/app_alert_message.dart';
import '../components/app_auth_divider.dart';
import '../components/app_form_input.dart';
import '../components/app_password_input.dart';
import '../components/app_social_button.dart';
import '../components/app_submit_button.dart';

class LoginFormSection extends StatelessWidget {
  const LoginFormSection({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onSubmit,
    required this.onGoogleTap,
    required this.loading,
    this.error,
    required this.onSwitchToSignup,
    required this.onForgotPassword,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final ValueChanged<bool> onRememberMeChanged;
  final VoidCallback onSubmit;
  final VoidCallback onGoogleTap;
  final bool loading;
  final String? error;
  final VoidCallback onSwitchToSignup;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        const Text(
          'Bienvenido de vuelta',
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
          'Ingresa tus credenciales para continuar',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 16),

        // Client-only notice
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.primaryMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Esta app es exclusiva para clientes. Los negocios se administran desde rewardshub.cloud',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Error banner
        if (error != null && error!.isNotEmpty) ...[
          AppAlertMessage(message: error!),
          const SizedBox(height: 16),
        ],

        // Email
        AppFormInput(
          controller: emailController,
          label: 'Correo electrónico',
          placeholder: 'correo@ejemplo.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          prefixIcon: const Icon(Icons.mail_outline_rounded),
        ),
        const SizedBox(height: 16),

        // Password
        AppPasswordInput(
          controller: passwordController,
          label: 'Contraseña',
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          labelRight: GestureDetector(
            onTap: onForgotPassword,
            child: const Text(
              '¿Olvidaste tu contraseña?',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Remember me
        _RememberMeRow(value: rememberMe, onChanged: onRememberMeChanged),
        const SizedBox(height: 20),

        // Submit
        AppSubmitButton(
          label: 'Iniciar Sesión',
          loadingLabel: 'Iniciando sesión...',
          onPressed: onSubmit,
          loading: loading,
        ),
        const SizedBox(height: 16),

        const AppAuthDivider(),
        const SizedBox(height: 16),

        AppSocialButton(
          onPressed: onGoogleTap,
          disabled: loading,
        ),
        const SizedBox(height: 24),

        // Switch to signup
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              const Text(
                '¿No tienes una cuenta? ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
              GestureDetector(
                onTap: onSwitchToSignup,
                child: const Text(
                  'Regístrate aquí',
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

// ── Remember me row ───────────────────────────────────────────────────────────

class _RememberMeRow extends StatelessWidget {
  const _RememberMeRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
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
          const Text(
            'Recordarme',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
