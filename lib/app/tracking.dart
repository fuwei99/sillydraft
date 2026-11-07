import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sillydraft_core/sillydraft_core.dart';

const tianjiServerUrl = 'https://app.tianji.dev';
const tianjiApplicationId = 'cmw6hum76e2tw9f84j684epi8';
bool _initialized = false;

void initializeApplicationTracking() {
  if (_initialized) return;
  _initialized = true;
  try {
    final tracking = ApplicationTracking.current = ApplicationTracking(
      serverUrl: tianjiServerUrl,
      applicationId: tianjiApplicationId,
      os: Platform.operatingSystem,
      language: PlatformDispatcher.instance.locale.toLanguageTag(),
      version: PackageInfo.fromPlatform()
          .then((info) => info.version)
          .timeout(const Duration(seconds: 3), onTimeout: () => '')
          .catchError((Object _) => ''),
    );
    installTrackingErrorHandlers();
    tracking.identify({'os': Platform.operatingSystem});
  } catch (_) {
    // App startup does not depend on telemetry or platform metadata.
  }
}

void installTrackingErrorHandlers() {
  final flutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    try {
      ApplicationTracking.current?.error(details.exception, source: 'flutter');
    } finally {
      (flutterHandler ?? FlutterError.presentError)(details);
    }
  };
  final platformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    var handled = false;
    try {
      ApplicationTracking.current?.error(error, source: 'platform');
    } finally {
      handled = platformHandler?.call(error, stack) ?? false;
    }
    return handled;
  };
}

/// Track route identity as well as its pattern: two stories share a name.
class ApplicationRouteObserver extends NavigatorObserver {
  Route<dynamic>? _top, _home, _reportedRoute;
  String _homeTab = '/shelf';
  String? _reportedName;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _top = topRoute;
    if (topRoute.settings.name == '/') _home = topRoute;
    _report();
  }

  void setHomeTab(int index) {
    _homeTab = const ['/shelf', '/resources', '/settings'][index];
    _report();
  }

  void _report() {
    final route = _top;
    if (route is! PageRoute) return; // Dialogs do not replace the focused page.
    final name = identical(route, _home) ? _homeTab : route.settings.name;
    if (name == null ||
        (identical(route, _reportedRoute) && name == _reportedName)) {
      return;
    }
    _reportedRoute = route;
    _reportedName = name;
    ApplicationTracking.current?.screenView(name);
  }
}
