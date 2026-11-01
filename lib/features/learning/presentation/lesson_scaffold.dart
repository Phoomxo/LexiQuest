import 'package:flutter/material.dart';

import '../../../config/m3_theme.dart';
import '../../../widgets/adaptive_content_pane.dart';

class LessonScaffold extends StatelessWidget {
  const LessonScaffold({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.largeControls = false,
    this.reduceMotion = false,
  });

  final String title;
  final Widget body;
  final Widget? leading;
  final bool largeControls;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = const WidgetStatePropertyAll(Size(64, 64));
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || reduceMotion,
      ),
      child: Theme(
        data: !largeControls
            ? theme
            : theme.copyWith(
                filledButtonTheme: FilledButtonThemeData(
                  style: (theme.filledButtonTheme.style ?? const ButtonStyle())
                      .copyWith(minimumSize: size),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style:
                      (theme.outlinedButtonTheme.style ?? const ButtonStyle())
                          .copyWith(minimumSize: size),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: (theme.textButtonTheme.style ?? const ButtonStyle())
                      .copyWith(minimumSize: size),
                ),
              ),
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: M3Theme.appBarToolbarHeight(context),
            title: M3Theme.appBarTitle(context, title),
            leading: leading,
          ),
          body: AdaptiveContentPane(child: body),
        ),
      ),
    );
  }
}

class LessonProgress extends StatelessWidget {
  const LessonProgress({
    super.key,
    required this.current,
    required this.total,
    this.languageCode = 'th',
  }) : assert(current > 0 && total > 0 && current <= total);

  final int current;
  final int total;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final label = languageCode == 'en'
        ? 'Question $current of $total'
        : 'คำถาม $current จาก $total';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: LinearProgressIndicator(value: current / total),
        ),
      ],
    );
  }
}
