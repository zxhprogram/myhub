import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Text input built on the shadcn [TextField].
///
/// Validation (when [validator] is set) runs on every change once the field
/// has content and the error text is rendered below the field.
class NexusInput extends StatefulWidget {
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
  State<NexusInput> createState() => _NexusInputState();
}

class _NexusInputState extends State<NexusInput> {
  String? _error;

  void _validate(String value) {
    if (widget.validator == null) return;
    final error = widget.validator!(value);
    if (error != _error) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final field = TextField(
      controller: widget.controller,
      hintText: widget.hintText,
      maxLines: widget.maxLines,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      style: NexusTypography.bodyMd,
      onChanged: (value) {
        _validate(value);
        widget.onChanged?.call(value);
      },
      onSubmitted: widget.onSubmitted,
    );

    final decoratedField = (widget.prefixIcon != null ||
            widget.suffixIcon != null)
        ? Row(
            children: [
              if (widget.prefixIcon != null) ...[
                widget.prefixIcon!,
                const SizedBox(width: NexusSpacing.sm),
              ],
              Expanded(child: field),
              if (widget.suffixIcon != null) ...[
                const SizedBox(width: NexusSpacing.sm),
                widget.suffixIcon!,
              ],
            ],
          )
        : field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.labelText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: NexusSpacing.xs),
            child: Text(
              widget.labelText!,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.foreground,
              ),
            ),
          ),
        decoratedField,
        if (_error != null) ...[
          const SizedBox(height: NexusSpacing.xs),
          Text(
            _error!,
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }
}
