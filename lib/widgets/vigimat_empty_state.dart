import 'package:flutter/material.dart';
import '../core/theme/vigimat_colors.dart';
import 'vigimat_button.dart';

class VigimatEmptyState extends StatelessWidget {
  const VigimatEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.buttonText,
    this.onButtonPressed,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: VigimatColors.navy.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(
                  color: VigimatColors.border,
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                size: 36,
                color: VigimatColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VigimatColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VigimatColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (buttonText != null && onButtonPressed != null) ...[
              const SizedBox(height: 24),
              VigimatButton(
                text: buttonText!,
                onPressed: onButtonPressed,
                fullWidth: false,
                icon: Icons.add_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
