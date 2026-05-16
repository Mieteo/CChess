import 'package:cchess/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots: splash → home', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: CChessApp()),
    );

    // First frame: splash should be present.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Kỳ Vương Việt'), findsOneWidget);

    // Advance past the 2.2s auto-navigate so the timer drains and the
    // Home screen renders.
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pumpAndSettle();

    expect(find.text('Đánh Cờ Ngay'), findsOneWidget);
  });
}
