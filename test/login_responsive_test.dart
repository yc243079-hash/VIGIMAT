import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigimat/features/auth/auth_gate.dart';

void main() {
  testWidgets('login stays scrollable and usable on compact phones', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in [const Size(320, 568), const Size(360, 640)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint), findsNothing);
      final layoutException = tester.takeException();
      expect(layoutException, isNull, reason: 'viewport size: $size');

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
