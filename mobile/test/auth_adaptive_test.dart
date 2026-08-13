import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/app/krishisathi_app.dart';
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

      await tester.pumpWidget(KrishiSathiApp(controller: await _controller()));
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
}
