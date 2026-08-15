import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/app/krishisathi_app.dart';
import 'package:krishisathi/core/localization/app_strings.dart';
import 'package:krishisathi/core/theme/app_theme.dart';
import 'package:krishisathi/features/saathi/presentation/saathi_screens.dart';
import 'package:krishisathi/features/shared/presentation/app_controller.dart';
import 'package:provider/provider.dart';

import 'support/test_controller.dart';

Future<AppController> _pumpApp(
  WidgetTester tester, {
  required Size size,
  bool onboardingComplete = true,
  String locale = 'en',
  double textScale = 1,
  FakeViewPadding padding = FakeViewPadding.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final controller = await createTestController(
    locale: locale,
    onboardingComplete: onboardingComplete,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
  });
  await tester.pumpWidget(KrishiSathiApp(controller: controller));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('welcome and authentication imagery fills the phone canvas', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      size: const Size(390, 844),
      onboardingComplete: false,
      padding: const FakeViewPadding(top: 47, bottom: 34),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('welcome-hero-image'))),
      const Size(390, 844),
    );
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('auth-hero-image'))),
      const Size(390, 844),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home and Saathi hero stages are edge-to-edge on compact phones',
    (tester) async {
      await _pumpApp(tester, size: const Size(360, 800));

      final homeHero = find.byKey(const ValueKey('home-scan-hero-stage'));
      expect(tester.getTopLeft(homeHero).dx, 0);
      expect(tester.getSize(homeHero).width, 360);

      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      navigation.onDestinationSelected!(3);
      await tester.pumpAndSettle();

      final saathiHero = find.byKey(const ValueKey('saathi-hero-stage'));
      expect(tester.getTopLeft(saathiHero).dx, 0);
      expect(tester.getSize(saathiHero).width, 360);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Realme-sized Android remains usable at 200 percent text', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      size: const Size(360, 780),
      textScale: 2,
      padding: const FakeViewPadding(top: 24),
    );

    expect(find.text('Scan your crop'), findsOneWidget);
    expect(find.text('Start scan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saathi full-bleed stage mirrors safely in RTL', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createTestController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppStrings.supportedLocales,
          theme: AppTheme.light(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: SaathiScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final hero = find.byKey(const ValueKey('saathi-hero-stage'));
    expect(tester.getTopLeft(hero).dx, 0);
    expect(tester.getSize(hero).width, 393);
    expect(Directionality.of(tester.element(hero)), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet keeps imagery prominent without stretching content', (
    tester,
  ) async {
    await _pumpApp(tester, size: const Size(1024, 900));

    final homeHero = find.byKey(const ValueKey('home-scan-hero-stage'));
    expect(tester.getSize(homeHero).height, greaterThanOrEqualTo(520));
    expect(tester.getSize(homeHero).width, lessThan(800));

    final navigation = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    navigation.onDestinationSelected!(3);
    await tester.pumpAndSettle();

    final saathiHero = find.byKey(const ValueKey('saathi-hero-stage'));
    expect(tester.getSize(saathiHero).height, greaterThanOrEqualTo(330));
    expect(tester.getSize(saathiHero).width, lessThanOrEqualTo(940));
    expect(tester.takeException(), isNull);
  });
}
