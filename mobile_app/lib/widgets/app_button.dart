import 'package:flutter/material.dart';

enum AppButtonVariant { primary, secondary, outline }

/// Reusable button with consistent styling and a built-in loading state.
/// Use this everywhere instead of raw ElevatedButton / OutlinedButton.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant  = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveOnPressed = isLoading ? null : onPressed;

    Widget child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: variant == AppButtonVariant.primary
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.primary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    final size = Size(width ?? double.infinity, height);

    switch (variant) {
      case AppButtonVariant.primary:
        return SizedBox(
          width: width,
          child: ElevatedButton(
            onPressed: effectiveOnPressed,
            style: ElevatedButton.styleFrom(minimumSize: size),
            child: child,
          ),
        );

      case AppButtonVariant.secondary:
        return SizedBox(
          width: width,
          child: ElevatedButton(
            onPressed: effectiveOnPressed,
            style: ElevatedButton.styleFrom(
              minimumSize: size,
              backgroundColor: theme.colorScheme.secondary,
              foregroundColor: theme.colorScheme.onSecondary,
            ),
            child: child,
          ),
        );

      case AppButtonVariant.outline:
        return SizedBox(
          width: width,
          child: OutlinedButton(
            onPressed: effectiveOnPressed,
            style: OutlinedButton.styleFrom(minimumSize: size),
            child: child,
          ),
        );
    }
  }
}
