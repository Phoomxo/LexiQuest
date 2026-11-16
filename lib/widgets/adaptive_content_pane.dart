import 'package:flutter/material.dart';

class AdaptiveContentPane extends StatelessWidget {
  const AdaptiveContentPane({
    super.key,
    required this.child,
    this.maxWidth = taskMaxWidth,
  });

  static const double formMaxWidth = 560;
  static const double proseMaxWidth = 640;
  static const double taskMaxWidth = 720;
  static const double tutorMaxWidth = 760;

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite && constraints.maxWidth < maxWidth
            ? constraints.maxWidth
            : maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }
}
