import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sillydraft/app/theme.dart';
import 'package:sillydraft/app/widgets.dart';

void main() {
  testWidgets('desktop settings badge preserves row height and alignment', (
    tester,
  ) async {
    final item = find.widgetWithText(FSidebarItem, '设置');
    for (final scale in [1.0, 2.0]) {
      Future<void> show(int count) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => FTheme(
              data: appTheme(Brightness.light),
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: Align(
              alignment: Alignment.centerLeft,
              child: AppSidebar(
                selectedIndex: -1,
                onSelect: (_) {},
                footerCount: 1,
                destinations: [
                  (icon: FLucideIcons.settings, label: '设置', badge: count),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(0);
      final withoutBadge = tester.getRect(item);
      await show(1);
      final withBadge = tester.getRect(item);
      final badge = tester.getRect(find.byType(FBadge));
      final label = tester.getRect(find.text('设置'));
      expect(withBadge.height, withoutBadge.height);
      expect(withBadge.center.dy, withoutBadge.center.dy);
      expect(badge.center.dy, label.center.dy);
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
}
