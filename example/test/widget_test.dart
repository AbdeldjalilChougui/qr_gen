import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_gen.dart';
import 'package:qr_gen_example/main.dart';

void main() {
  testWidgets('shows a QR code that follows the text field', (tester) async {
    await tester.pumpWidget(const QrGenExampleApp());
    expect(find.byType(QrImageView), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a' * 3000);
    await tester.pump();
    expect(find.text('Too much data for a QR code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'short');
    await tester.pump();
    expect(find.text('Too much data for a QR code'), findsNothing);
  });

  testWidgets('style chips update the code', (tester) async {
    await tester.pumpWidget(const QrGenExampleApp());
    await tester.tap(find.widgetWithText(ChoiceChip, 'circle').first);
    await tester.pump();
    final view = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(view.eyeStyle.shape, QrModuleShape.circle);
  });
}
