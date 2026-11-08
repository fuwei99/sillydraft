import 'package:flutter_test/flutter_test.dart';

/// Empty-library flows opt into offline use through the real startup guide.
Future<void> skipModelSetup(WidgetTester tester) async {
  await tester.tap(find.text('先离线使用'));
  // Active-task spinners cannot settle; only finish the dialog transition.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
