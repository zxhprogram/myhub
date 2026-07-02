import 'package:flutter/material.dart';

import '../../theme/colors.dart';
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
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
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
                color: NexusColors.onSurface,
              ),
            ),
          ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          autofocus: autofocus,
          enabled: enabled,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: NexusTypography.bodyMd,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: NexusTypography.bodyMd.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: NexusColors.surfaceContainerLow,
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
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: const BorderSide(color: NexusColors.outline),
            ),
          ),
        ),
      ],
    );
  }
}
