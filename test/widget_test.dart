import 'package:flutter_test/flutter_test.dart';
import 'package:sensio_ppg_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SensioApp());
    expect(find.text('Sensio PPG Analysis Studio'), findsOneWidget);
  });
}
