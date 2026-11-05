import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/settings/pages/connectors_page.dart';

void main() {
  testWidgets('ConnectorsPage renders search, categories and catalog header', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ConnectorsPage()));

    // Initial pump
    await tester.pump();

    expect(find.text('Connectors'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Productivity'), findsOneWidget);
    expect(find.text('Developer Tools'), findsOneWidget);
  });
}
