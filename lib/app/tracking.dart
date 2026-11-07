import 'dart:async';
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
    );
    installTrackingErrorHandlers();
    tracking.identify({'os': Platform.operatingSystem});
    unawaited(
      PackageInfo.fromPlatform()
          .then((info) {
            tracking.identify({
              'os': Platform.operatingSystem,
              'version': info.version,
            });
          })
          .catchError((Object _) {}),
    );
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
