import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/localization/app_strings.dart';
import 'package:krishisathi/core/theme/app_theme.dart';
import 'package:krishisathi/core/ui/crop_visuals.dart';
import 'package:krishisathi/features/farm/presentation/plot_history_screen.dart';
import 'package:krishisathi/features/home/presentation/weather_screen.dart';
import 'package:krishisathi/features/shared/presentation/app_controller.dart';
import 'package:provider/provider.dart';

import 'support/test_controller.dart';

Widget _screen(AppController controller, Widget child) {
  return ChangeNotifierProvider.value(
    value: controller,
    child: MaterialApp(
      locale: controller.locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: child,
    ),
  );
}

void main() {
  test('generated crop visual mapping uses compact project assets', () {
    final expected = <String, String>{
      'rice': 'assets/images/crop_rice.webp',
      'wheat': 'assets/images/crop_wheat.webp',
      'cotton': 'assets/images/crop_cotton.webp',
      'banana': 'assets/images/crop_banana.webp',
    };
    for (final entry in expected.entries) {
      expect(CropVisuals.forCrop(entry.key), entry.value);
      final file = File(entry.value);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), lessThan(200000));
    }
  });

  test('preview activity preserves crop and farmer-selected time', () async {
    final controller = await createTestController();
    final occurredAt = DateTime(2026, 8, 12, 7, 30);
    final result = await controller.addActivity(
      plotId: 'plot-1',
      type: 'Observation',
      notes: 'Flowering is even across the row.',
      occurredAt: occurredAt,
      cropId: 'crop-1',
    );

    expect(result.failedPhotoCount, 0);
    expect(result.activity.cropId, 'crop-1');
    expect(result.activity.occurredAt, occurredAt);
    expect(
      controller.plotById('plot-1')!.activities.first.id,
      result.activity.id,
    );
  });

  test(
    'preview plot weather provides current and seven-day forecast',
    () async {
      final controller = await createTestController();
      final weather = await controller.loadPlotWeather('plot-1');

      expect(weather.forecast, hasLength(7));
      expect(weather.current.humidity, inInclusiveRange(0, 100));
      expect(controller.plotWeather['plot-1'], same(weather));
    },
  );

  test(
    'plot history filters activity records without losing pagination',
    () async {
      final controller = await createTestController();
      await controller.loadPlotTimeline('plot-1');
      final page = await controller.fetchPlotTimeline(
        'plot-1',
        categories: const {'activity'},
        limit: 1,
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.category, 'activity');
      expect(page.hasMore, isTrue);
    },
  );

  for (final viewport in <({String name, Size size})>[
    (name: 'compact phone', size: Size(320, 568)),
    (name: 'large phone', size: Size(430, 932)),
    (name: 'tablet', size: Size(1024, 900)),
  ]) {
    testWidgets('weather screen adapts to a ${viewport.name}', (tester) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await createTestController();
      await tester.pumpWidget(_screen(controller, const WeatherScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Weather for better field decisions'), findsOneWidget);
      if (find.text('Plot forecast').evaluate().isEmpty) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -430));
        await tester.pumpAndSettle();
      }
      expect(find.text('Plot forecast'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('filtered history renders records and controls on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await createTestController();
    await controller.loadPlotTimeline('plot-1');
    await tester.pumpWidget(
      _screen(controller, const PlotHistoryScreen(plotId: 'plot-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filter history'), findsOneWidget);
    expect(find.text('Drip irrigation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
