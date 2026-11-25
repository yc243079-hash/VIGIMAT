import 'package:flutter/material.dart';
import '../core/theme/vigimat_colors.dart';

class VigimatTextField extends StatefulWidget {
  const VigimatTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.minLines,
    this.readOnly = false,
    this.onTap,
    this.autofillHints,
    this.onDark = false,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final int? minLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final Iterable<String>? autofillHints;
  final bool onDark;
  final Widget? suffixIcon;

  @override
  State<VigimatTextField> createState() => _VigimatTextFieldState();
}

class _VigimatTextFieldState extends State<VigimatTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.onDark;

    final fillColor = isDark
        ? const Color(0xFF132B47).withValues(alpha: 0.75)
        : Colors.white;

    final textColor = isDark ? Colors.white : VigimatColors.textPrimary;
    final hintColor = isDark
        ? const Color(0xFF94A3B8)
        : VigimatColors.textMuted;
    final borderColor = isDark
        ? const Color(0xFF23456C)
        : VigimatColors.border;
    final focusBorderColor = isDark
        ? VigimatColors.turquoise
        : VigimatColors.emerald;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: isDark ? const Color(0xFFCBD5E1) : VigimatColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          minLines: widget.minLines,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          autofillHints: widget.autofillHints,
          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: hintColor, fontSize: 14),
            filled: true,
            fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            prefixIcon: widget.icon != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: isDark ? const Color(0xFF94A3B8) : VigimatColors.textSecondary,
                    ),
                  )
                : null,
            prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            suffixIcon: widget.obscureText
                ? IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: isDark ? const Color(0xFF94A3B8) : VigimatColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : widget.suffixIcon,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: borderColor, width: 1.1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: focusBorderColor, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: VigimatColors.crimson, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: VigimatColors.crimson, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
