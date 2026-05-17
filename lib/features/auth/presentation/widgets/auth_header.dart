import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.mode,
    required this.accountType,
  });

  final String mode; // 'login' | 'signup'
  final String accountType; // 'client' | 'business'

  @override
  Widget build(BuildContext context) {
    final content = _content;
    return Container(
      width: double.infinity,
      color: AppColors.darkBg,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 28,
        left: 28,
        right: 28,
        bottom: 32,
      ),
      child: Stack(
        children: [
          // Ambient glow top-right
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.primary.withValues(alpha: 0.04),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand name
              Row(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 28,
                    height: 28,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'RewardsHub',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Mode badge
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _Badge(key: ValueKey(content.badge), label: content.badge),
              ),
              const SizedBox(height: 10),
              // Title
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  key: ValueKey('${mode}_${accountType}_title'),
                  content.title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Subtitle
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  key: ValueKey('${mode}_${accountType}_sub'),
                  content.subtitle,
                  style: const TextStyle(
                    color: AppColors.textDarkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _HeaderContent get _content {
    if (mode == 'login') {
      return const _HeaderContent(
        badge: 'App para Clientes',
        title: 'Bienvenido\nde vuelta',
        subtitle: 'Acumula puntos y canjea recompensas en tus negocios favoritos',
      );
    }
    if (accountType == 'client') {
      return const _HeaderContent(
        badge: 'Para clientes',
        title: 'Gana puntos\nen tus favoritos',
        subtitle: 'Acumula puntos y canjéalos por recompensas exclusivas',
      );
    }
    return const _HeaderContent(
      badge: 'Para negocios',
      title: 'Fideliza a tus\nclientes',
      subtitle: 'Crea tu programa de puntos personalizado',
    );
  }
}

class _HeaderContent {
  const _HeaderContent({
    required this.badge,
    required this.title,
    required this.subtitle,
  });
  final String badge;
  final String title;
  final String subtitle;
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
