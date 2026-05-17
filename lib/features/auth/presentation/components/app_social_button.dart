import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class AppSocialButton extends StatelessWidget {
  const AppSocialButton({
    super.key,
    required this.onPressed,
    this.disabled = false,
    this.label = 'Continuar con Google',
  });

  final VoidCallback onPressed;
  final bool disabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: disabled ? 0.4 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: disabled ? null : onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.textPrimary,
            disabledForegroundColor: AppColors.textPrimary,
            disabledBackgroundColor: AppColors.white,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _GoogleLogo(size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    // Simple "G" styled to match Google's brand colors
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw colored arc segments
    final sweeps = [
      (startAngle: -0.52, sweep: 1.57, color: const Color(0xFF4285F4)),  // blue
      (startAngle: 1.05, sweep: 1.57, color: const Color(0xFF34A853)),   // green
      (startAngle: 2.62, sweep: 1.05, color: const Color(0xFFFBBC05)),   // yellow
      (startAngle: 3.67, sweep: 1.09, color: const Color(0xFFEA4335)),   // red
    ];

    for (final seg in sweeps) {
      paint.color = seg.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        seg.startAngle,
        seg.sweep,
        true,
        paint,
      );
    }

    // White center cutout
    paint.color = Colors.white;
    canvas.drawCircle(center, radius * 0.6, paint);

    // Blue "G" bar on the right
    paint.color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - radius * 0.18, radius, radius * 0.36),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
