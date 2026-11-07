import 'dart:async';

import 'package:dio/dio.dart';

/// Process-local, best-effort Tianji HTTP tracking; CLI/server users stay off.
final class ApplicationTracking {
  ApplicationTracking({
    required String serverUrl,
    required this.applicationId,
    required this.os,
    required this.language,
    required this.version,
  }) : _client = Dio(
         BaseOptions(
           baseUrl: serverUrl.replaceFirst(RegExp(r'/+$'), ''),
           connectTimeout: const Duration(seconds: 3),
           sendTimeout: const Duration(seconds: 3),
           receiveTimeout: const Duration(seconds: 3),
           followRedirects: false,
           responseType: ResponseType.plain,
           headers: {'User-Agent': 'SillyDraft/1 ($os)'},
         ),
       );

  static ApplicationTracking? current;
  final String applicationId, os, language;
  final Future<String> version;
  // This client must never have the application's API interceptor.
  final Dio _client;
  final _queue = <Map<String, Object?>>[];
  Timer? _timer;
  Future<void>? _sending;
  String _screen = '';
  bool _disposed = false;

  void identify(Map<String, Object?> profile) =>
      _enqueue('identify', data: profile);

  void screenView(String pattern) {
    _screen = _limit(pattern, 500);
    _enqueue('event');
  }

  void event(String name, Map<String, Object?> data) =>
      _enqueue('event', name: _limit(name, 50), data: data);

  void error(Object error, {required String source}) {
    // Exception text and stacks can contain prompts, tokens and local paths.
    event('App Error', {
      'type': error.runtimeType.toString(),
      'source': source,
    });
    unawaited(flush());
  }

  void _enqueue(
    String type, {
    String? name,
    Map<String, Object?> data = const {},
  }) {
    if (_disposed || _queue.length >= 100) return;
    try {
      _queue.add({
        'type': type,
        'payload': {
          'application': applicationId,
          'os': _limit(os, 20),
          'language': _limit(language, 35),
          'screen': _screen,
          'params': <String, Object?>{},
          'name': ?name,
          'data': {
            for (final entry in data.entries)
              if (entry.value is String ||
                  entry.value is bool ||
                  (entry.value is num && (entry.value as num).isFinite))
                entry.key: entry.value is String
                    ? _limit(entry.value as String, 500)
                    : entry.value,
          },
        },
      });
      _timer ??= Timer(
        const Duration(milliseconds: 200),
        () => unawaited(flush()),
      );
    } catch (_) {
      // Tracking never changes the result of the operation being measured.
    }
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _sending ??= _send().whenComplete(() => _sending = null);
  }

  Future<void> _send() async {
    final String appVersion;
    try {
      appVersion = _limit((await version).trim(), 50);
      if (appVersion.isEmpty) {
        _queue.clear();
        return;
      }
    } catch (_) {
      _queue.clear();
      return;
    }
    while (!_disposed && _queue.isNotEmpty) {
      final batch = List<Map<String, Object?>>.of(_queue);
      _queue.clear();
      try {
        // New sessions (including IP changes) need the version on every payload.
        for (final event in batch) {
          final payload = event['payload'] as Map<String, Object?>;
          payload['version'] = appVersion;
          if (event['type'] == 'identify') {
            (payload['data'] as Map<String, Object?>)['version'] = appVersion;
          }
        }
        await _client.post<void>(
          '/api/application/batch',
          data: {'events': batch},
        );
      } catch (_) {
        // shortcut: drop offline batches; add durable delivery only if required.
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _queue.clear();
    _client.close(force: true);
  }
}

String _limit(String value, int length) {
  if (value.length <= length) return value;
  // Avoid splitting a UTF-16 surrogate pair at the server's character limit.
  final end = value.codeUnitAt(length - 1);
  return value.substring(
    0,
    end >= 0xd800 && end <= 0xdbff ? length - 1 : length,
  );
}
