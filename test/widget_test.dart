import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_studio/main.dart';

void main() {
  testWidgets('app renders the empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const PdfStudioApp());

    expect(find.text('No PDF open'), findsOneWidget);
  });
}
