import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  final path = Platform.environment['SILLYDRAFT_SCREENSHOT_DIR'];
  if (path == null || path.isEmpty) {
    throw StateError(
      'Set SILLYDRAFT_SCREENSHOT_DIR to a dedicated output folder.',
    );
  }
  final output = Directory(path);
  await output.create(recursive: true);
  await integrationDriver(
    responseDataCallback: (data) async {
      final captures = data?['captures'];
      if (captures is! Map) throw StateError('No store screenshots returned.');
      if (Platform.environment['SILLYDRAFT_REQUIRE_ILLUSTRATION'] == 'true' &&
          !captures.containsKey('illustration')) {
        throw StateError('The requested illustration screenshot is missing.');
      }
      for (final name in [
        'workspace',
        'reader',
        'lore',
        if (captures.containsKey('illustration')) 'illustration',
        if (captures.containsKey('illustration-details'))
          'illustration-details',
      ]) {
        final encoded = captures[name];
        if (encoded is! String) throw StateError('Missing $name screenshot.');
        await File('${output.path}/$name.png')
            .writeAsBytes(base64Decode(encoded));
      }
    },
  );
}
