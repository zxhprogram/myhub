import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/spacing.dart';

/// Consistent page wrapper used by all screens.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, this.header, required this.child});

  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.background,
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null) ...[
              header!,
              const SizedBox(height: NexusSpacing.md),
            ],
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
