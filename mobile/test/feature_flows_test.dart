import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:krishisathi/core/config/app_config.dart';
import 'package:krishisathi/core/localization/app_strings.dart';
import 'package:krishisathi/core/theme/app_theme.dart';
import 'package:krishisathi/core/ui/crop_visuals.dart';
import 'package:krishisathi/features/farm/presentation/farm_screens.dart';
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
  test('map tile provider is configurable with an OSM-safe default', () {
    final config = AppConfig(
      apiBaseUri: Uri.parse('http://localhost:8000'),
      awsRegion: 'ap-south-1',
      environment: 'test',
    );

    expect(
      config.mapTileUrlTemplate,
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
  });

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
    seedTestFarmData(controller);
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

  test('area preference converts mixed plot units consistently', () async {
    final controller = await createTestController();

    expect(controller.formatArea(1, 'hectare'), '2.5 acres');
    await controller.setPreferredAreaUnit('hectare');
    expect(controller.formatArea(2.47105381, 'acre'), '1.0 hectare');
    expect(controller.preferredAreaUnit, 'hectare');
  });

  test(
    'preview plot weather provides current and seven-day forecast',
    () async {
      final controller = await createTestController();
      final weather = await controller.loadPlotWeather('plot-1');

      expect(weather.forecast, hasLength(7));
      expect(weather.current?.humidity, inInclusiveRange(0, 100));
      expect(controller.plotWeather['plot-1'], same(weather));
    },
  );

  test(
    'plot history filters activity records without losing pagination',
    () async {
      final controller = await createTestController();
      seedTestFarmData(controller);
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
      expect(
        find.text('Live conditions from this phone’s current location.'),
        findsOneWidget,
      );
      expect(find.text('Plot forecast'), findsNothing);
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
    seedTestFarmData(controller);
    await controller.loadPlotTimeline('plot-1');
    await tester.pumpWidget(
      _screen(controller, const PlotHistoryScreen(plotId: 'plot-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filter history'), findsOneWidget);
    expect(find.text('Drip irrigation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed plot pointer remains usable at large accessible text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final controller = await createTestController();
      seedTestFarmData(controller);
      await tester.pumpWidget(
        _screen(controller, const EditPlotScreen(plotId: 'plot-1')),
      );
      await tester.pumpAndSettle();
      final formScroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(FlutterMap),
        420,
        scrollable: formScroll,
      );
      await tester.ensureVisible(find.byType(FlutterMap));
      await tester.scrollUntilVisible(
        find.text('Map pointer confirmed'),
        360,
        scrollable: formScroll,
      );

      expect(find.text('Map pointer confirmed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
