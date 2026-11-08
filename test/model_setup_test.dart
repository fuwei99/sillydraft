import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sillydraft/app/app.dart';
import 'package:sillydraft/app/home_screen.dart';
import 'package:sillydraft/app/services.dart';
import 'package:sillydraft/app/widgets.dart';
import 'package:sillydraft/features/settings/settings_screen.dart';
import 'package:sillydraft_core/sillydraft_core.dart';

const _guide = Key('model-setup-dialog');

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

    Future<void> select(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(of: navigation, matching: find.text(label)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      '${wide ? 'desktop' : 'phone'} startup guide opens model setup',
      (tester) async {
        tester.view.physicalSize = wide
            ? const Size(1280, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final services = await open(tester);
        expect(find.byKey(_guide), findsOneWidget);
        await tester.tap(find.text('去配置'));
        await tester.pumpAndSettle();
        expect(find.byKey(_guide), findsNothing);
        expect(
          tester.widget<SettingsScreen>(find.byType(SettingsScreen)).initialTab,
          SettingsTab.models,
        );
        await tester.tap(find.text('添加连接'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(FTextFormField, '模型名称'),
          'test',
        );
        await tester.ensureVisible(find.text('保存连接'));
        await tester.tap(find.text('保存连接'));
        await tester.pumpAndSettle();
        expect(await services.connections(), hasLength(1));
        await tester.tap(find.byType(AppBackButton));
        await tester.pumpAndSettle();
        expect(badge(tester), 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${wide ? 'desktop' : 'phone'} skip keeps the reminder without repeating the guide',
      (tester) async {
        tester.view.physicalSize = wide
            ? const Size(1280, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final services = await open(tester);
        await tester.tap(find.text('先离线使用'));
        await tester.pumpAndSettle();
        expect(badge(tester), 1);
        await select(tester, '设置');
        await select(tester, '作品');
        expect(find.byKey(_guide), findsNothing);

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
        expect(find.byKey(_guide), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(SillyDraftApp(services: services));
        await tester.pumpAndSettle();
        expect(find.byKey(_guide), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${wide ? 'desktop' : 'phone'} configured startup has no setup guide or badge',
      (tester) async {
        tester.view.physicalSize = wide
            ? const Size(1280, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester, configured: true);
        expect(find.byKey(_guide), findsNothing);
        expect(badge(tester), 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
