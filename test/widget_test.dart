import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rewardshub_mobile/features/auth/presentation/auth_page.dart';

void main() {
  testWidgets('the expired-session notice is shown on the login screen',
      (tester) async {
    const message = 'Tu sesión expiró. Vuelve a iniciar sesión para continuar.';

    await tester.pumpWidget(const MaterialApp(
      home: AuthPage(notice: message),
    ));
    await tester.pump();

    expect(find.text(message), findsOneWidget);
  });

  testWidgets('no notice is shown on a plain login', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthPage()));
    await tester.pump();

    expect(find.byIcon(Icons.lock_clock_rounded), findsNothing);
  });
}
