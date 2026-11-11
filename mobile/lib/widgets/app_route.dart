import 'package:flutter/material.dart';
import 'glass.dart';

int _routeCounter = 0;

/// A page that is pushed on top of the current one. It carries a name, so on the web the browser
/// gets a history entry for it: the phone's back swipe (or the back button) then closes this page
/// inside the app, instead of leaving the app and reloading it.
MaterialPageRoute<T> appRoute<T>({
  required WidgetBuilder builder,
  bool fullscreenDialog = false,
}) => AppPageRoute<T>(
  settings: RouteSettings(name: '/s${++_routeCounter}'),
  fullscreenDialog: fullscreenDialog,
  builder: builder,
);

/// Each pushed page owns its opaque canvas. Glass must not reveal the previous
/// page during an iOS transition (or force both full pages to be composited).
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required WidgetBuilder builder,
    required super.settings,
    super.fullscreenDialog,
  }) : super(
         builder: (context) => Stack(
           fit: StackFit.expand,
           children: [const AmbientField(), builder(context)],
         ),
       );
  T? result;
  @override
  T? get currentResult => result;
}

/// Supplies a default pop result without vetoing iOS's interactive back gesture.
class AppRouteResult<T> extends StatelessWidget {
  const AppRouteResult({super.key, required this.result, required this.child});
  final T result;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is AppPageRoute<T>) route.result = result;
    return child;
  }
}
