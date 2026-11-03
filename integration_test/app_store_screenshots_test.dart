import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sillydraft/app/app.dart';
import 'package:sillydraft/app/sample.dart';
import 'package:sillydraft/app/services.dart';
import 'package:sillydraft/app/widgets.dart';
import 'package:sillydraft/features/lore/lore_screen.dart';
import 'package:sillydraft/features/illustrations/illustration_detail.dart';
import 'package:sillydraft_core/sillydraft_core.dart';

import '../test/support/finders.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture store screens with isolated sample data', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'sillydraft-store-',
    );
    final repository = StoryRepository.open('${directory.path}/library.sqlite');
    final services = AppServices(
      repository: repository,
      secrets: MemorySecrets(),
      dataDirectory: directory,
    );
    final novel = await createSample(repository);
    for (final entry in [
      (LoreKind.character, '林舟', '雾港的年轻信使，收到一封来自十三年前的信。'),
      (LoreKind.character, '阿雨', '深夜来到旧邮局的访客，也收到了同样的来信。'),
      (LoreKind.location, '旧邮局', '地图藏在柜台上，第三块地板总会发出响声。'),
      (LoreKind.world, '雾中的灯塔', '旧地图上新出现的灯塔，墨迹尚未干透。'),
    ]) {
      await repository.saveLoreEntry(
        branchId: novel.activeBranchId,
        kind: entry.$1,
        name: entry.$2,
        content: entry.$3,
      );
    }
    final captureKey = GlobalKey();
    final captures = <String, String>{};
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      captures[name] = base64Encode(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: SillyDraftApp(services: services),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(novel.title));
    await tester.pumpAndSettle();
    await capture('workspace');
    await tester.tap(find.byKey(const Key('open-reader')));
    await tester.pumpAndSettle();
    await capture('reader');
    unawaited(
      Navigator.of(tester.element(find.byType(AppScaffold).last)).push(
        MaterialPageRoute<void>(
          builder: (_) => LoreScreen(branchId: novel.activeBranchId),
        ),
      ),
    );
    await capture('lore');
    const illustrationUrl = String.fromEnvironment('STORE_ILLUSTRATION_URL');
    if (illustrationUrl.isNotEmpty) {
      final uri = Uri.parse(illustrationUrl);
      expect(uri.scheme, 'http');
      expect(uri.host, '127.0.0.1');
      final client = HttpClient();
      late Uint8List illustration;
      try {
        final response = await (await client.getUrl(uri)).close();
        expect(response.statusCode, HttpStatus.ok);
        illustration = await consolidateHttpClientResponseBytes(response);
      } finally {
        client.close(force: true);
      }
      final asset = await services.assets!.importImage(
        branchId: novel.activeBranchId,
        name: '雾港来信 · 插画示例',
        bytes: illustration,
        metadata: const {'origin': 'imported_store_sample'},
      );
      unawaited(
        Navigator.of(tester.element(find.byType(AppScaffold).last)).push(
          MaterialPageRoute<void>(
            builder: (_) => IllustrationDetail(
              branchId: novel.activeBranchId,
              assetId: asset.id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (find
              .byWidgetPredicate((w) => w is RawImage && w.image != null)
              .evaluate()
              .isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byWidgetPredicate((w) => w is RawImage && w.image != null),
        findsWidgets,
      );
      await capture('illustration');
      if ((tester.view.physicalSize / tester.view.devicePixelRatio).width <
          900) {
        await tester.tap(findAction('图片详情'));
        await capture('illustration-details');
      }
    }
    binding.reportData = {'captures': captures};
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await services.close();
    await directory.delete(recursive: true);
  });
}
