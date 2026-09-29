import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_commuter/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots without throwing', (tester) async {
    await tester.pumpWidget(const SmartCommuterApp());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
