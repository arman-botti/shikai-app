import 'package:flutter_test/flutter_test.dart';
import 'package:shikai_app/main.dart';

void main() {
  testWidgets('ShikaiApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ShikaiApp());
    expect(find.byType(ShikaiApp), findsOneWidget);
  });
}
