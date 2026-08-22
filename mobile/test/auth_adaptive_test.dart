import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:krishisathi/app/krishisathi_app.dart';
import 'package:krishisathi/features/onboarding/presentation/onboarding_screens.dart';
import 'package:krishisathi/features/profile/presentation/profile_screens.dart';
import 'package:krishisathi/features/shared/presentation/app_controller.dart';

import 'support/test_controller.dart';

Future<AppController> _controller() =>
    createTestController(onboardingComplete: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => 'build/test-cache',
        );
  });

  for (final viewport in <({String name, Size size})>[
    (name: 'small Android phone', size: Size(320, 568)),
    (name: 'standard Android or iPhone', size: Size(390, 844)),
    (name: 'tablet', size: Size(1024, 900)),
  ]) {
    testWidgets('sign-in adapts to a ${viewport.name}', (tester) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(KrishiSathiApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/images/auth_field_hero.webp',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('create account collects the farmer name on the auth screen', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();

    expect(find.text('Your name'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pre-auth onboarding routes remain behind login', (tester) async {
    final controller = await _controller()
      ..previewMode = false
      ..isAuthenticated = false;
    addTearDown(controller.dispose);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(WelcomeScreen)))
        .go('/onboarding/language');
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(LanguageSetupScreen), findsNothing);
    expect(find.byType(PermissionsSetupScreen), findsNothing);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(PermissionsSetupScreen), findsNothing);
  });

  testWidgets('changing language keeps the current settings route', (
    tester,
  ) async {
    final controller = await createTestController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test Farmer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguageSettingsScreen), findsOneWidget);

    controller
      ..locale = const Locale('hi')
      ..notifyListeners();
    await tester.pump();

    expect(controller.locale.languageCode, 'hi');
    expect(find.byType(LanguageSettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an authenticated account without a name must complete profile', (
    tester,
  ) async {
    final controller = await createTestController(
      live: true,
      onboardingComplete: false,
      farmerName: '',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(KrishiSathiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.text('Test Farmer'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
