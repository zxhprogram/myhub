import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// Consistent page wrapper used by all screens.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, this.header, required this.child});

  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Wrap the page in a Scaffold so ScaffoldMessenger.showSnackBar works
    // everywhere, including inside desktop windows that provide no Scaffold
    // of their own. The inner container's background colour is moved onto the
    // Scaffold so the look is unchanged.
    return Scaffold(
      backgroundColor: NexusColors.background,
      resizeToAvoidBottomInset: false,
      body: Padding(
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
