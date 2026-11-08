import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sillydraft_core/sillydraft_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('direct Tavern context initializes MVU with the persona name', (
    tester,
  ) async {
    final writes = <Map<String, dynamic>>[];
    var loaded = false;
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => loaded = true),
    );
    await controller.addJavaScriptChannel(
      'SillyDraftBridge',
      onMessageReceived: (message) async {
        final call = jsonDecode(message.message) as Map<String, dynamic>;
        if (call['method'] == 'replaceVariables') writes.add(call);
        await controller.runJavaScript(
          '__sdResolve(${call['id']}, true, null)',
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: controller)),
      ),
    );
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await controller.loadHtmlString('''<!doctype html><html><head><script>
      window.__SD_STATE = {
        api: true, name1: '小明', name2: '向导', message_id: 0,
        messages: [{name: '向导', role: 'assistant', message: '开场'}]
      };
      $tavernRuntimeJs
      </script></head><body></body></html>''');

    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(condition(), isTrue);
    }

    Future<Object> js(String expression) => controller
        .runJavaScriptReturningResult(expression)
        .timeout(const Duration(seconds: 5));

    await waitFor(() => loaded);
    // Community frontends substitute their InitVar before writing both scopes.
    await controller.runJavaScript(r'''
      (async function () {
        const name = SillyTavern.name1 || '{{user}}';
        const data = {stat_data: JSON.parse(
          '{"玩家":{"姓名":"{{user}}"}}'.replace(/\{\{user\}\}/gi, name)
        )};
        await Mvu.replaceMvuData(data, {type: 'message', message_id: 0});
        await Mvu.replaceMvuData(data, {type: 'chat'});
      })();
    ''');
    await waitFor(() => writes.length == 2);
    for (final write in writes) {
      expect(write['args'][0]['stat_data']['玩家']['姓名'], '小明');
    }
    expect(writes[0]['args'][1], {'type': 'message', 'message_id': 0});
    expect(writes[1]['args'][1], {'type': 'chat'});
    expect(await js('SillyTavern.getContext().name1'), '小明');
    expect(await js('SillyTavern.name2'), '向导');

    // Each direct access sees the latest supported context, just like the helper.
    await controller.runJavaScript(
      "setChatMessages([{message_id: 0, message: '下一幕'}])",
    );
    expect(await js('SillyTavern.chat[0].mes'), '下一幕');
    expect(
      await js('SillyTavern.chatMetadata.variables.stat_data.玩家.姓名'),
      '小明',
    );
  });
}
