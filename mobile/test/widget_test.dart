import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/app/krishisathi_app.dart';

import 'support/test_controller.dart';

void main() {
  testWidgets('renders the mobile shell above the system safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await createTestController();
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('Good morning'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses navigation rail on expanded layouts', (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await createTestController();
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders Urdu with RTL direction', (tester) async {
    final controller = await createTestController(locale: 'ur');
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    final directionality = tester.widget<Directionality>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Directionality &&
                widget.textDirection == TextDirection.rtl,
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
    expect(find.text('گھر'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary navigation reaches all four product sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await createTestController();
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Farm').last);
    await tester.pumpAndSettle();
    expect(find.text('Your farms'), findsOneWidget);

    await tester.tap(find.text('Scan').last);
    await tester.pumpAndSettle();
    expect(find.text('Check a leaf'), findsWidgets);

    await tester.tap(find.text('Saathi').last);
    await tester.pumpAndSettle();
    expect(find.text('Recent conversations'), findsOneWidget);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Good morning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plot detail exposes linked records and weather on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await createTestController();
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Farm').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anand Fields').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('North Plot').last);
    await tester.pumpAndSettle();

    expect(find.text('Plot records'), findsOneWidget);
    expect(find.text('Full forecast'), findsOneWidget);
    expect(find.text('Leaf checks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact shell remains usable at large accessibility text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final controller = await createTestController();
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining('Good morning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
