import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/app/app_launch_reveal.dart';
import 'package:krishisathi/features/scan/presentation/leaf_camera_screen.dart';

void main() {
  testWidgets('brand reveal is brief and removes itself after launch', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppLaunchReveal(child: Scaffold(body: Text('Home ready'))),
      ),
    );

    expect(find.byKey(const ValueKey('app-launch-reveal')), findsOneWidget);
    expect(find.text('KrishiSathi'), findsOneWidget);
    expect(find.text('Home ready'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const ValueKey('app-launch-reveal')), findsNothing);
    expect(find.text('Home ready'), findsOneWidget);
  });

  testWidgets('brand reveal completes immediately when motion is reduced', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AppLaunchReveal(child: Scaffold(body: Text('Home ready'))),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('app-launch-reveal')), findsNothing);
    expect(find.text('Home ready'), findsOneWidget);
  });

  testWidgets('scanner overlay has a static reduced-motion presentation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.expand(
          child: LeafScannerOverlay(progress: 0.5, reducedMotion: true),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('live-leaf-scanner-overlay')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
