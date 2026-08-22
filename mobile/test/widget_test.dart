import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/app/krishisathi_app.dart';
import 'package:krishisathi/core/localization/app_strings.dart';
import 'package:krishisathi/features/shared/presentation/app_controller.dart';
import 'package:krishisathi/features/saathi/presentation/saathi_screens.dart';

import 'support/test_controller.dart';

Future<AppController> _controllerFor(
  WidgetTester tester, {
  String locale = 'en',
}) async {
  final controller = await createTestController(locale: locale);
  seedTestFarmData(controller);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
  });
  return controller;
}

void main() {
  testWidgets('renders the mobile shell above the system safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controllerFor(tester);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Test Farmer'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses navigation rail on expanded layouts', (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controllerFor(tester);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a compact rail without losing state at medium width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controllerFor(tester);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    rail.onDestinationSelected!(1);
    await tester.pumpAndSettle();
    expect(find.text('Your farms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape phone keeps navigation and content usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controllerFor(tester);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Test Farmer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark appearance keeps the operational shell readable', (
    tester,
  ) async {
    final controller = await _controllerFor(tester);
    await controller.setThemeMode(ThemeMode.dark);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Test Farmer'))).brightness,
      Brightness.dark,
    );
    final systemUi = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const ValueKey('system-ui-overlay')),
    );
    expect(systemUi.value.statusBarIconBrightness, Brightness.light);
    expect(systemUi.value.systemNavigationBarIconBrightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders Urdu with RTL direction', (tester) async {
    final controller = await _controllerFor(tester, locale: 'ur');
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    // Advance the finite launch reveal explicitly. `pumpAndSettle` can wait on
    // unrelated platform/plugin frames left by earlier adaptive tests.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

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
    final urdu = AppStrings.cached(const Locale('ur'))!;
    expect(find.text(urdu.text('home')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary navigation reaches all four product sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controllerFor(tester);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Farm').last);
    await tester.pumpAndSettle();
    expect(find.text('Your farms'), findsOneWidget);

    await tester.tap(find.text('Scan').last);
    // The scanner has a deliberate continuous pulse; advance the route
    // transition without waiting for all animation tickers to become idle.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Check a leaf'), findsWidgets);

    await tester.tap(find.text('Saathi').last);
    await tester.pumpAndSettle();
    expect(find.text('Recent conversations'), findsOneWidget);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('Test Farmer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone back returns to Saathi after creating a chat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controllerFor(tester);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saathi').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New chat').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'How is my field today?');
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ChatDetailScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Recent conversations'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plot detail exposes linked records without weather clutter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controllerFor(tester);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Farm').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anand Fields').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('North Plot').last);
    await tester.pumpAndSettle();

    expect(find.text('Plot records'), findsOneWidget);
    expect(find.text('Full forecast'), findsNothing);
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

    final controller = await _controllerFor(tester);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Test Farmer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
