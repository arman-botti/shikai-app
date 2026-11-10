import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shikai_app/main.dart';

void main() {
  testWidgets('ShikaiApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ShikaiApp());
    expect(find.byType(ShikaiApp), findsOneWidget);

    // Let the splash screen timers fire so no timers are left pending.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });
}
