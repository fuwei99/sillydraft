import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sillydraft/app/services.dart';
import 'package:sillydraft/features/settings/settings_screen.dart';
import 'package:sillydraft_core/sillydraft_core.dart';

import 'support/host.dart';

void main() {
  testWidgets('settings tabs retain focus during keyboard navigation', (
    tester,
  ) async {
    final services = AppServices(
      repository: StoryRepository.memory(),
      secrets: MemorySecrets(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await services.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: testHost(const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final modelsFocus = Focus.of(tester.element(find.text('模型')));
    final creationFocus = Focus.of(tester.element(find.text('创作')));
    for (var step = 0; step < 10 && !modelsFocus.hasPrimaryFocus; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(modelsFocus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('模型连接'), findsOneWidget);
    expect(modelsFocus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(creationFocus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('world-info-budget-cap')), findsOneWidget);
    expect(creationFocus.hasPrimaryFocus, isTrue);
  });

  for (final brightness in Brightness.values) {
    for (final width in [390.0, 1000.0]) {
      testWidgets(
        'settings tabs at $width in $brightness retain edits and scroll',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final services = AppServices(
            repository: StoryRepository.memory(),
            secrets: MemorySecrets(),
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await services.close();
          });
          await tester.pumpWidget(
            ProviderScope(
              overrides: [servicesProvider.overrideWithValue(services)],
              child: testHost(
                MediaQuery(
                  data: MediaQueryData.fromView(tester.view)
                      .copyWith(textScaler: TextScaler.linear(1.5)),
                  child: const SettingsScreen(),
                ),
                brightness: brightness,
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final label in ['通用', '模型', '创作', '关于']) {
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
          expect(find.text('外观'), findsOneWidget);
          expect(find.text('模型连接'), findsNothing);
          await tester.tap(find.text('模型'));
          await tester.pumpAndSettle();
          expect(find.text('添加连接').hitTestable(), findsOneWidget);
          expect(find.text('外观'), findsNothing);
          await tester.tap(find.text('创作'));
          await tester.pumpAndSettle();
          final cap = find.byKey(const Key('world-info-budget-cap'));
          final list = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(cap, 250, scrollable: list);
          await tester.enterText(cap, '70000');
          await tester.pumpAndSettle();
          final input = tester.widget<EditableText>(
            find.descendant(of: cap, matching: find.byType(EditableText)),
          );
          expect(input.focusNode.hasFocus, isTrue);
          expect(find.text('请输入 0 到 65536 的整数'), findsOneWidget);
          final offset = tester.state<ScrollableState>(list).position.pixels;
          expect(offset, greaterThan(0));
          await tester.tap(find.text('关于').hitTestable());
          await tester.pumpAndSettle();
          expect(input.focusNode.hasFocus, isFalse);
          expect(
            find.byKey(const Key('settings-privacy-policy')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('world-info-budget-cap')), findsNothing);
          await tester.tap(find.text('创作'));
          await tester.pumpAndSettle();
          expect(tester.state<ScrollableState>(list).position.pixels, offset);
          expect(find.text('70000'), findsOneWidget);
          expect(find.text('请输入 0 到 65536 的整数'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
