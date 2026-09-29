// test/widget_smoke_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/app/app.dart';
import 'package:hesabi/features/home/presentation/pages/home_page.dart';
import 'package:hesabi/shared/layouts/app_shell.dart';

void main() {
  testWidgets('HesabiApp boots into the home page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: HesabiApp()));

    // Allow the localization delegates to resolve before asserting.
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
  });
}
