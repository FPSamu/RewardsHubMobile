import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';
import 'update_service.dart';

Future<void> _openStore(String? url) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Full-screen block for a build the backend refuses to serve.
///
/// Intentionally offers no way past it: an unsupported build stops here.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.status});

  final UpdateStatus status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primaryMuted,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppColors.primary,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Actualización requerida',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  status.message ??
                      'Esta versión de la app ya no es compatible. '
                          'Actualízala para seguir usando RewardsHub.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textLight,
                    height: 1.5,
                  ),
                ),
                if (status.latestVersion != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Versión disponible: ${status.latestVersion}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDarkMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (status.storeUrl != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openStore(status.storeUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Actualizar ahora'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100)),
                        elevation: 0,
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dismissible nudge for a build that is merely behind.
Future<void> showOptionalUpdateSheet(
  BuildContext context,
  UpdateStatus status,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.system_update_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hay una versión nueva',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (status.latestVersion != null)
                      Text(
                        'Versión ${status.latestVersion}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            status.message ??
                'Actualiza para tener las mejoras y correcciones más recientes.',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (status.storeUrl != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(sheetContext);
                _openStore(status.storeUrl);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100)),
                elevation: 0,
              ),
              child: const Text('Actualizar',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(sheetContext),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('Ahora no',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}
