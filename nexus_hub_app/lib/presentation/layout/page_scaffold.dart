import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../theme/density.dart';

/// Consistent page wrapper used by all screens.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, this.header, required this.child});

  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final colorScheme = Theme.of(context).colorScheme;

      return Container(
        color: colorScheme.background,
        child: Padding(
          padding: EdgeInsets.all(NexusDensityController.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (header != null) ...[
                header!,
                SizedBox(height: NexusDensityController.sectionGap),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      );
    });
  }
}
