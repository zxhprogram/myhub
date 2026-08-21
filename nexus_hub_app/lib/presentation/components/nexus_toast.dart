import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Transient feedback built on the shadcn toast overlay.
///
/// Replaces all Material snack bars. Requires the shadcn infrastructure
/// installed by [ShadcnApp] (or a local [ShadcnLayer] in widget tests).
void nexusToast(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration showDuration = const Duration(seconds: 3),
}) {
  showToast(
    context: context,
    showDuration: showDuration,
    builder: (context, overlay) => _NexusToast(
      message: message,
      isError: isError,
    ),
  );
}

class _NexusToast extends StatelessWidget {
  const _NexusToast({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedContainer(
      backgroundColor: theme.colorScheme.popover,
      borderRadius: theme.borderRadiusMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError ? LucideIcons.circleAlert : LucideIcons.check,
              size: 16,
              color: isError
                  ? theme.colorScheme.destructive
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(message).small(),
          ],
        ),
      ),
    );
  }
}
