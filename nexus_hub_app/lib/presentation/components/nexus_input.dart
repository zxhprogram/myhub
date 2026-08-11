import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

class NexusInput extends StatelessWidget {
  const NexusInput({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.autofocus = false,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.autovalidateMode,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int maxLines;
  final bool autofocus;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labelText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: NexusSpacing.xs),
            child: Text(
              labelText!,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          autofocus: autofocus,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          autovalidateMode: autovalidateMode,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          style: NexusTypography.bodyMd.copyWith(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: NexusTypography.bodyMd.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.md,
              vertical: NexusSpacing.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: BorderSide(
                color: isDark
                    ? Colors.transparent
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: BorderSide(color: colorScheme.secondary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: BorderSide(color: colorScheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: BorderSide(color: colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}
