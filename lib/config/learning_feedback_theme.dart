import 'package:flutter/material.dart';

@immutable
class LearningFeedbackTheme extends ThemeExtension<LearningFeedbackTheme> {
  const LearningFeedbackTheme({
    required this.success,
    required this.onSuccess,
    required this.support,
    required this.onSupport,
  });
  final Color success, onSuccess, support, onSupport;
  static const light = LearningFeedbackTheme(
    success: Color(0xFFE8F5E9),
    onSuccess: Color(0xFF1B5E20),
    support: Color(0xFFE8EAF6),
    onSupport: Color(0xFF283593),
  );
  static const dark = LearningFeedbackTheme(
    success: Color(0xFF1B3B26),
    onSuccess: Color(0xFFC8E6C9),
    support: Color(0xFF20284F),
    onSupport: Color(0xFFC5CAE9),
  );
  static LearningFeedbackTheme of(BuildContext context) =>
      Theme.of(context).extension<LearningFeedbackTheme>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  @override
  LearningFeedbackTheme copyWith({
    Color? success,
    Color? onSuccess,
    Color? support,
    Color? onSupport,
  }) => LearningFeedbackTheme(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    support: support ?? this.support,
    onSupport: onSupport ?? this.onSupport,
  );
  @override
  LearningFeedbackTheme lerp(
    covariant LearningFeedbackTheme? other,
    double t,
  ) => other == null
      ? this
      : LearningFeedbackTheme(
          success: Color.lerp(success, other.success, t)!,
          onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
          support: Color.lerp(support, other.support, t)!,
          onSupport: Color.lerp(onSupport, other.onSupport, t)!,
        );
}
