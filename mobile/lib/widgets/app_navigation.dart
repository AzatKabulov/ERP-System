import 'dart:async';
import 'package:flutter/material.dart';

/// Browser history and native gestures share the same in-memory Navigator.
/// No route URL is a document load or a source of authorization.
class AppNavigation extends RouterDelegate<String>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<String> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Widget home = const SizedBox.shrink();
  late final _observer = _NavigationObserver(this);
  final List<Route<dynamic>> _stack = [];
  final Map<Route<dynamic>, String> _names = {};
  int _overlayId = 0;
  bool _queued = false;
  bool _replaceHistory = false;
  bool _disposed = false;

  @override
  String get currentConfiguration => _names[_stack.lastOrNull] ?? '/';

  void _changed({bool replace = false}) {
    _replaceHistory |= replace;
    if (_queued || _disposed) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (_disposed) return;
      final context = navigatorKey.currentContext;
      final replace = _replaceHistory;
      _replaceHistory = false;
      if (replace && context != null) {
        // An in-app pop replaces its transient URL. Pushing the parent here
        // would leave a stale detail entry that traps Safari's next Back.
        Router.neglect(context, notifyListeners);
      } else {
        notifyListeners();
      }
    });
  }

  void reset() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    for (final route in _stack.skip(1).toList().reversed) {
      navigator.removeRoute(route);
    }
  }

  @override
  Future<void> setNewRoutePath(String configuration) async {
    // Reloaded/deep-linked transient pages have no trusted in-memory builder:
    // enter the root and restore the session normally, never reconstruct data
    // or issue writes from a URL. Existing stack entries support browser Back.
    if (_stack.isEmpty) return;
    final target = _stack.indexWhere((r) => _names[r] == configuration);
    if (target < 0) {
      _changed(replace: true);
      return;
    }
    while (_stack.length > target + 1) {
      final top = _stack.last;
      final popped = await navigatorKey.currentState!.maybePop();
      if (!popped || _stack.contains(top)) {
        break; // includes a newly opened confirmation
      }
    }
    _changed();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    observers: [_observer],
    pages: [
      MaterialPage<void>(
        key: const ValueKey('app-root'),
        name: '/',
        child: home,
      ),
    ],
    onDidRemovePage: (_) {},
  );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppRouteParser extends RouteInformationParser<String> {
  const AppRouteParser();
  @override
  Future<String> parseRouteInformation(
    RouteInformation routeInformation,
  ) async =>
      routeInformation.uri.path.isEmpty ? '/' : routeInformation.uri.path;
  @override
  RouteInformation restoreRouteInformation(String configuration) =>
      RouteInformation(uri: Uri(path: configuration));
}

class _NavigationObserver extends NavigatorObserver {
  _NavigationObserver(this.owner);
  final AppNavigation owner;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    owner._stack.add(route);
    owner._names[route] = route.settings.name ?? '/o${++owner._overlayId}';
    owner._changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    owner._stack.remove(route);
    owner._names.remove(route);
    owner._changed(replace: true);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    owner._stack.remove(route);
    owner._names.remove(route);
    owner._changed(replace: true);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null || newRoute == null) return;
    final i = owner._stack.indexOf(oldRoute);
    if (i >= 0) {
      owner._stack[i] = newRoute;
      owner._names.remove(oldRoute);
      owner._names[newRoute] =
          newRoute.settings.name ?? '/o${++owner._overlayId}';
    }
    owner._changed();
  }
}
