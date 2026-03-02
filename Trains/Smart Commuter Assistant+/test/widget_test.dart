import 'package:flutter_test/flutter_test.dart';

import 'package:smart_commuter_assistant/main.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartCommuterApp());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
