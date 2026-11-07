import 'package:flutter/material.dart';

int _routeCounter = 0;

/// A page that is pushed on top of the current one. It carries a name, so on the web the browser
/// gets a history entry for it: the phone's back swipe (or the back button) then closes this page
/// inside the app, instead of leaving the app and reloading it.
MaterialPageRoute<T> appRoute<T>({
  required WidgetBuilder builder,
  bool fullscreenDialog = false,
}) => MaterialPageRoute<T>(
  settings: RouteSettings(name: '/s${++_routeCounter}'),
  fullscreenDialog: fullscreenDialog,
  builder: builder,
);
