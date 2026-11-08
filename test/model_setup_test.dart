import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sillydraft/app/app.dart';
import 'package:sillydraft/app/home_screen.dart';
import 'package:sillydraft/app/services.dart';
import 'package:sillydraft/app/widgets.dart';
import 'package:sillydraft_core/sillydraft_core.dart';

void main() {
  Future<AppServices> open(
    WidgetTester tester, {
    bool configured = false,
  }) async {
    final services = AppServices(
      repository: StoryRepository.memory(),
      secrets: MemorySecrets(),
    );
    if (configured) {
      await services.saveConnection(
        ModelConnection(
          id: 'test',
          name: '测试连接',
          baseUrl: 'https://example.test/v1',
          model: 'test',
        ),
      );
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await services.close();
    });
    await tester.pumpWidget(SillyDraftApp(services: services));
    await tester.pumpAndSettle();
    return services;
  }

  for (final wide in [true, false]) {
    final navigation = find.byType(wide ? AppSidebar : AppBottomBar);
    int badge(WidgetTester tester) => wide
        ? tester
              .widget<AppSidebar>(navigation)
              .destinations[HomeTab.settings]
              .badge
        : tester
              .widget<AppBottomBar>(navigation)
              .destinations[HomeTab.settings]
              .badge;

    testWidgets(
      '${wide ? 'desktop' : 'phone'} settings badge follows model connections',
      (tester) async {
        tester.view.physicalSize = wide
            ? const Size(1280, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final services = await open(tester);
        expect(badge(tester), 1);

        await services.saveConnection(
          ModelConnection(
            id: 'test',
            name: '测试',
            baseUrl: 'https://example.test/v1',
            model: 'test',
          ),
        );
        await tester.pumpAndSettle();
        expect(badge(tester), 0);
        await services.removeConnection('test');
        await tester.pumpAndSettle();
        expect(badge(tester), 1);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${wide ? 'desktop' : 'phone'} configured library has no setup badge',
      (tester) async {
        tester.view.physicalSize = wide
            ? const Size(1280, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester, configured: true);
        expect(badge(tester), 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
