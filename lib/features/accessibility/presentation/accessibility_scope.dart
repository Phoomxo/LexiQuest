import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../domain/accessibility_policy.dart';

/// Immutable platform presentation settings observed by accessibility-aware UI.
final class AccessibilityPresentationState {
  const AccessibilityPresentationState({
    required this.textScale,
    required this.highContrast,
    required this.reducedMotion,
  });

  final double textScale;
  final bool highContrast;
  final bool reducedMotion;
}

/// Provides passive, current platform accessibility settings to a presentation
/// subtree. It neither persists preferences nor changes lesson delivery.
final class AccessibilityScope extends StatelessWidget {
  const AccessibilityScope({super.key, required this.child});

  final Widget child;

  static AccessibilityPresentationState of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_AccessibilityInheritedScope>();
    return inherited?.state ?? _fromMediaQuery(context);
  }

  static AccessibilityPresentationState _fromMediaQuery(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return AccessibilityPresentationState(
      textScale: mediaQuery.textScaler.scale(1),
      highContrast: mediaQuery.highContrast,
      reducedMotion: mediaQuery.disableAnimations,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _fromMediaQuery(context);
    final inherited = _AccessibilityInheritedScope(state: state, child: child);
    if (!state.highContrast) return inherited;

    final parentTheme = Theme.of(context);
    final highContrastScheme = ColorScheme.fromSeed(
      seedColor: parentTheme.colorScheme.primary,
      brightness: parentTheme.brightness,
      contrastLevel: 1,
    );
    return Theme(
      data: parentTheme.copyWith(colorScheme: highContrastScheme),
      child: inherited,
    );
  }
}

/// Gives one canonical lesson region an independent semantic boundary and
/// stable traversal order. A supplied [label] replaces child semantics so a
/// screen cannot accidentally announce the same critical action twice.
final class AccessibilitySemanticRegion extends StatelessWidget {
  const AccessibilitySemanticRegion({
    super.key,
    required this.role,
    required this.child,
    this.label,
    this.button = false,
    this.onTap,
  });

  final AccessibilitySemanticRole role;
  final Widget child;
  final String? label;
  final bool button;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final replacesChildSemantics = label != null;
    return Semantics(
      container: true,
      explicitChildNodes: !replacesChildSemantics,
      sortKey: OrdinalSortKey(_orderFor(role)),
      label: label,
      button: button || onTap != null,
      onTap: onTap,
      child: replacesChildSemantics ? ExcludeSemantics(child: child) : child,
    );
  }

  static double _orderFor(AccessibilitySemanticRole role) => switch (role) {
    AccessibilitySemanticRole.contextAndProgress => 0,
    AccessibilitySemanticRole.prompt => 1,
    AccessibilitySemanticRole.responseAndInput => 2,
    AccessibilitySemanticRole.feedback => 3,
    AccessibilitySemanticRole.navigation => 4,
  };
}

/// Assigns the canonical navigation semantic role to an existing app bar
/// without changing its layout, focus, or navigation behavior.
final class AccessibilityNavigationBar extends StatelessWidget
    implements PreferredSizeWidget {
  const AccessibilityNavigationBar({super.key, required this.child});

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) => AccessibilitySemanticRegion(
    role: AccessibilitySemanticRole.navigation,
    child: child,
  );
}

/// Keeps a mode's real prompt, response, and feedback nodes in one ordered
/// semantic branch ahead of its navigation branch without replacing or
/// relabeling any child semantics.
final class AccessibilityModeContentGroup extends StatelessWidget {
  const AccessibilityModeContentGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    sortKey: const OrdinalSortKey(1),
    child: child,
  );
}

/// Keeps a mode's real app bar visually first while placing its content and
/// navigation under one semantic parent. The content branch remains explicit
/// so prompt/response regions retain their own nodes and sort keys.
final class AccessibilityModeScaffold extends StatelessWidget {
  const AccessibilityModeScaffold({
    super.key,
    required this.appBar,
    required this.body,
  });

  final PreferredSizeWidget appBar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Column(
        children: <Widget>[
          SizedBox(
            height: topPadding + appBar.preferredSize.height,
            child: AccessibilityNavigationBar(child: appBar),
          ),
          Expanded(
            child: AccessibilityModeContentGroup(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Typed opt-in for a mode surface that can place the shell-owned committed
/// feedback within its own semantic traversal group.
///
/// The shell still constructs and owns the feedback widget. Implementations
/// may only place the supplied widget; they do not receive feedback data or
/// evidence authority.
abstract interface class AccessibilityModeFeedbackSurface {
  Widget withShellFeedback(Widget? feedback);
}

/// Carries one shell-owned feedback widget into an opted-in mode subtree.
final class AccessibilityModeFeedbackSlot extends InheritedWidget {
  const AccessibilityModeFeedbackSlot({
    super.key,
    required this.feedback,
    required super.child,
  });

  final Widget? feedback;

  static Widget? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AccessibilityModeFeedbackSlot>()
      ?.feedback;

  @override
  bool updateShouldNotify(AccessibilityModeFeedbackSlot oldWidget) =>
      !identical(feedback, oldWidget.feedback);
}

final class _AccessibilityInheritedScope extends InheritedWidget {
  const _AccessibilityInheritedScope({
    required this.state,
    required super.child,
  });

  final AccessibilityPresentationState state;

  @override
  bool updateShouldNotify(_AccessibilityInheritedScope oldWidget) =>
      state.textScale != oldWidget.state.textScale ||
      state.highContrast != oldWidget.state.highContrast ||
      state.reducedMotion != oldWidget.state.reducedMotion;
}
