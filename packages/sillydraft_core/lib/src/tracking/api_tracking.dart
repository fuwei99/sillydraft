import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'application_tracking.dart';

/// Attach only to owned clients, including injected clients, once per client.
Dio trackApplicationApi(Dio client, {String? path}) {
  if (!client.interceptors.any((i) => i is _ApiTracking)) {
    client.interceptors.add(_ApiTracking(path));
  }
  return client;
}

final class _ApiTracking extends Interceptor {
  _ApiTracking(this.path);
  final String? path;
  final _started = Expando<Stopwatch>();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (ApplicationTracking.current != null) {
      _started[options] = Stopwatch()..start();
    }
    handler.next(options);
  }

  void _report(RequestOptions options, int? status) {
    try {
      final started = _started[options];
      if (started == null || options.cancelToken?.isCancelled == true) return;
      _started[options] = null;
      reportApplicationApi(
        options.method,
        path ?? applicationApiPath(options.uri.path),
        status,
        started.elapsedMilliseconds,
      );
    } catch (_) {}
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final body = response.data;
      if (body is ResponseBody) {
        body.stream = _body(body.stream, response);
      } else {
        _report(response.requestOptions, response.statusCode);
      }
    } finally {
      handler.next(response);
    }
  }

  Stream<Uint8List> _body(Stream<Uint8List> stream, Response response) async* {
    var status = response.statusCode;
    try {
      yield* stream.handleError((Object error, StackTrace stack) {
        status = 0;
        Error.throwWithStackTrace(error, stack);
      });
    } finally {
      // Consumers may stop at SSE [DONE] or discard a body; tokens mark aborts.
      _report(response.requestOptions, status);
    }
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    try {
      if (!CancelToken.isCancel(error)) {
        _report(error.requestOptions, error.response?.statusCode);
      }
    } finally {
      handler.next(error);
    }
  }
}

void reportApplicationApi(
  String method,
  String pattern,
  int? status,
  int duration,
) {
  ApplicationTracking.current?.event('API Request', {
    'method': method.toUpperCase(),
    'path': pattern,
    'status': status ?? 0,
    'duration': duration,
  });
}

/// Return only constants: custom base paths can contain credentials, too.
String applicationApiPath(String path) {
  final clean =
      '/${path.split('?').first.split('#').first.replaceFirst(RegExp(r'^/+'), '')}';
  for (final endpoint in const [
    '/chat/completions',
    '/images/generations',
    '/images/edits',
    '/ai/generate-image',
    '/v1/models',
    '/models',
    '/v1/jobs',
    '/upload/image',
    '/prompt',
    '/userdata',
    '/object_info',
    '/view',
    '/v1/hello',
    '/v1/tasks/start',
    '/v1/provider/text',
    '/v1/provider/image',
    '/v1/provider/workflow',
  ]) {
    if (clean.endsWith(endpoint)) return endpoint;
  }
  for (final suffix in const ['', '/cancel', '/image']) {
    if (RegExp('/v1/jobs/[^/]+$suffix\$').hasMatch(clean)) {
      return '/v1/jobs/[id]$suffix';
    }
  }
  for (final endpoint in const ['history', 'userdata', 'object_info']) {
    if (RegExp('/$endpoint/[^/]+\$').hasMatch(clean)) return '/$endpoint/[id]';
  }
  for (final suffix in const ['cancel', 'reconnect', 'resume', 'confirm']) {
    if (RegExp('/v1/tasks/[^/]+/$suffix\$').hasMatch(clean)) {
      return '/v1/tasks/[id]/$suffix';
    }
  }
  if (RegExp(r'/v1/assets/[^/]+$').hasMatch(clean)) return '/v1/assets/[id]';
  return '/[endpoint]';
}
