import 'package:flutter/material.dart';
import '../application/menu_action_registry.dart';
import '../../../navigation/navigation_glossary.dart';

/// Finite menu sections stay mounted below the viewport so their real callbacks
/// can be discovered. Data lists (words, history) must remain virtualized.
final class MenuActionListView extends StatelessWidget {
  const MenuActionListView({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => ListView(
    padding: padding,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ],
  );
}

/// Shares only canonical route metadata, never arbitrary route arguments.
final class MenuRouteObserver extends NavigatorObserver {
  MenuRouteObserver(this.registry);
  final MenuActionRegistry registry;
  Route<dynamic>? _current;
  VoidCallback? _remove;
  void refresh() {
    _remove?.call();
    final route = _current;
    final entry = NavigationGlossary.entries[route?.settings.name];
    if (entry == null) return;
    _remove = registry.registerContext(
      id: entry.id,
      label: entry.fullThaiLabel,
      available: () => route?.isCurrent == true,
      value: () => entry.tooltip,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _current = route;
    refresh();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _current = previousRoute;
    refresh();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_current == oldRoute) {
      _current = newRoute;
      refresh();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_current == route) {
      _current = previousRoute;
      refresh();
    }
  }
}

final class MenuActionScope extends InheritedWidget {
  const MenuActionScope({
    super.key,
    required this.registry,
    required super.child,
  });
  final MenuActionRegistry registry;
  static MenuActionRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MenuActionScope>()?.registry;
  @override
  bool updateShouldNotify(MenuActionScope oldWidget) =>
      oldWidget.registry != registry;
}

/// Registers the same callback as a real menu control, only while its route and
/// surface are active. No scope means ordinary application behavior is unchanged.
final class MenuActionBinding extends StatefulWidget {
  const MenuActionBinding({
    super.key,
    required this.id,
    required this.label,
    required this.onInvoke,
    required this.child,
    this.readValue,
    this.ownerId,
  });
  final String id, label;
  final MenuAction? onInvoke;
  final Widget child;
  final String? readValue;

  /// Personal records stay bound to their data owner even before a UI rebuild.
  final String? ownerId;
  @override
  State<MenuActionBinding> createState() => _MenuActionBindingState();
}

class _MenuActionBindingState extends State<MenuActionBinding> {
  MenuActionRegistry? _registry;
  VoidCallback? _unbind;
  bool _available() {
    if (widget.ownerId != null && widget.ownerId != _registry?.currentOwner()) {
      return false;
    }
    if (!mounted || widget.onInvoke == null && widget.readValue == null) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    var active = true;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage ||
          widget is Visibility && !widget.visible ||
          widget is TickerMode && !widget.enabled) {
        active = false;
        return false;
      }
      return true;
    });
    return active;
  }

  void _bind() {
    _unbind?.call();
    if (widget.readValue != null) {
      _unbind = _registry?.registerContext(
        id: widget.id,
        label: widget.label,
        available: _available,
        value: () => widget.readValue!,
      );
      return;
    }
    _unbind = _registry?.register(
      id: widget.id,
      label: widget.label,
      available: _available,
      invoke: () => widget.onInvoke!(),
      dispatchOnly: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = MenuActionScope.maybeOf(context);
    if (_registry != registry) {
      _registry = registry;
      _bind();
    }
  }

  @override
  void didUpdateWidget(MenuActionBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Callback closures may be rebuilt without changing the advertised action.
    // Availability is always rechecked immediately before invocation.
    if (oldWidget.id != widget.id ||
        oldWidget.ownerId != widget.ownerId ||
        oldWidget.label != widget.label ||
        oldWidget.readValue != widget.readValue ||
        widget.readValue != null) {
      _bind();
    }
  }

  @override
  void dispose() {
    _unbind?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
