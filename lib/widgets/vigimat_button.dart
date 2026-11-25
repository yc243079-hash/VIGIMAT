import 'package:flutter/material.dart';
import '../core/theme/vigimat_colors.dart';

enum VigimatButtonVariant { primary, secondary, danger, ghost }

class VigimatButton extends StatefulWidget {
  const VigimatButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = VigimatButtonVariant.primary,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = true,
    this.height = 50,
  });

  final String text;
  final VoidCallback? onPressed;
  final VigimatButtonVariant variant;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool fullWidth;
  final double height;

  @override
  State<VigimatButton> createState() => _VigimatButtonState();
}

class _VigimatButtonState extends State<VigimatButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onPressed != null && !widget.loading) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.onPressed != null && !widget.loading) {
      _controller.reverse();
    }
  }

  void _onTapCancel() {
    if (widget.onPressed != null && !widget.loading) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;

    // Couleurs selon variante
    final (bgGradient, bgColor, fgColor, border) = switch (widget.variant) {
      VigimatButtonVariant.primary => (
        enabled ? VigimatColors.emeraldGradient : null,
        enabled ? VigimatColors.emerald : VigimatColors.muted.withValues(alpha: 0.3),
        Colors.white,
        null,
      ),
      VigimatButtonVariant.secondary => (
        null,
        enabled ? Colors.white : Colors.grey.shade100,
        enabled ? VigimatColors.navy : VigimatColors.muted,
        Border.all(color: enabled ? VigimatColors.border : Colors.transparent),
      ),
      VigimatButtonVariant.danger => (
        null,
        enabled ? VigimatColors.crimson : VigimatColors.muted.withValues(alpha: 0.3),
        Colors.white,
        null,
      ),
      VigimatButtonVariant.ghost => (
        null,
        Colors.transparent,
        enabled ? VigimatColors.navy : VigimatColors.muted,
        null,
      ),
    };

    final content = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading) ...[
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(fgColor),
            ),
          ),
          const SizedBox(width: 10),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 19, color: fgColor),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fgColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        if (widget.trailingIcon != null && !widget.loading) ...[
          const SizedBox(width: 8),
          Icon(widget.trailingIcon, size: 18, color: fgColor),
        ],
      ],
    );

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: child,
      ),
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: enabled ? widget.onPressed : null,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: bgGradient,
            color: bgGradient == null ? bgColor : null,
            borderRadius: BorderRadius.circular(14),
            border: border,
            boxShadow: widget.variant == VigimatButtonVariant.primary && enabled
                ? VigimatColors.glow(VigimatColors.emerald, opacity: 0.22)
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}
