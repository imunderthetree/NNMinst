import 'package:flutter_test/flutter_test.dart';
import 'package:madbase_digit_app/main.dart';

void main() {
  testWidgets('NNMINST home screen shows image actions', (tester) async {
    await tester.pumpWidget(const NnminstApp(loadModel: false));

    expect(find.text('NNMINST'), findsWidgets);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
  });
}
