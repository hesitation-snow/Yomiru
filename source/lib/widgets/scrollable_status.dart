import 'package:flutter/material.dart';

/// Keeps empty/loading/error states centered in the available viewport and
/// still allows pull-to-refresh on short screens.
class ScrollableStatus extends StatelessWidget {
  const ScrollableStatus({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
                child:
                    Padding(padding: const EdgeInsets.all(24), child: child)),
          ),
        ],
      );
}
