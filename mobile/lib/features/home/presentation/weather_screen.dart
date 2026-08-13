import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../shared/presentation/app_controller.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key, this.initialPlotId});

  final String? initialPlotId;

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  String? _plotId;
  bool _loading = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _plotId = widget.initialPlotId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  Future<void> _initialLoad() async {
    final controller = context.read<AppController>();
    _plotId ??= controller.farms.expand((farm) => farm.plots).firstOrNull?.id;
    if (controller.weather == null && controller.locationEnabled) {
      try {
        await controller.refreshCurrentWeather(requestPermission: false);
      } on ApiException {
        // The phone card has its own recoverable state.
      }
    }
    await _loadPlot();
  }

  Future<void> _loadPlot() async {
    final plotId = _plotId;
    if (plotId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppController>().loadPlotWeather(plotId);
    } on ApiException catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final plots = controller.farms
        .expand((farm) => farm.plots)
        .toList(growable: false);
    final selectedPlot = _plotId == null ? null : controller.plotById(_plotId!);
    final plotWeather = _plotId == null
        ? null
        : controller.plotWeather[_plotId!];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('weather'))),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            if (controller.locationEnabled) {
              await controller.refreshCurrentWeather();
            }
            await _loadPlot();
          },
          child: AppContent(
            maxWidth: 1040,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 12, bottom: 40),
              children: [
                Text(
                  'Weather for better field decisions',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Phone conditions use your current location. Plot forecasts use the confirmed map point saved with each plot.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.mutedInk),
                ),
                const SizedBox(height: 22),
                SectionHeader(
                  title: 'Near you now',
                  action: IconButton(
                    tooltip: 'Refresh current weather',
                    onPressed: controller.locationEnabled
                        ? () async {
                            try {
                              await controller.refreshCurrentWeather();
                            } on ApiException catch (error) {
                              if (context.mounted) {
                                showAppSnackBar(context, error.message);
                              }
                            }
                          }
                        : null,
                    icon: const Icon(LucideIcons.refreshCw),
                  ),
                ),
                const SizedBox(height: 10),
                if (!controller.locationEnabled)
                  AppStateView(
                    kind: AppStateKind.empty,
                    title: 'Location is turned off',
                    message: 'Enable location in Privacy settings to see phone weather. Plot forecasts remain available.',
                    actionLabel: 'Open privacy settings',
                    onAction: () => context.push('/settings/privacy'),
                    compact: true,
                  )
                else if (controller.weather case final weather?)
                  _CurrentWeatherCard(weather: weather)
                else
                  AppStateView(
                    kind: AppStateKind.empty,
                    title: 'Current weather is not loaded',
                    message: 'Pull down or tap refresh to use the phone’s current location.',
                    actionLabel: 'Load weather',
                    onAction: () => controller.refreshCurrentWeather(),
                    compact: true,
                  ),
                const SizedBox(height: 28),
                SectionHeader(
                  title: 'Plot forecast',
                  subtitle: 'Current conditions and the next seven days',
                ),
                const SizedBox(height: 12),
                if (plots.isEmpty)
                  AppStateView(
                    kind: AppStateKind.empty,
                    title: 'Add a plot for field forecasts',
                    message: 'A confirmed plot location lets KrishiSathi show local conditions and forecasts.',
                    actionLabel: context.tr('addFarm'),
                    onAction: () => context.go('/farm'),
                    compact: true,
                  )
                else ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final plot in plots) ...[
                          ChoiceChip(
                            avatar: const Icon(LucideIcons.mapPin, size: 16),
                            label: Text(plot.name),
                            selected: _plotId == plot.id,
                            onSelected: (_) {
                              setState(() => _plotId = plot.id);
                              _loadPlot();
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (selectedPlot != null)
                    InlineNotice(
                      title: selectedPlot.name,
                      message:
                          selectedPlot.locationLabel ??
                          '${selectedPlot.latitude.toStringAsFixed(4)}, ${selectedPlot.longitude.toStringAsFixed(4)}',
                      icon: LucideIcons.mapPinned,
                    ),
                  const SizedBox(height: 14),
                  if (_loading && plotWeather == null)
                    const AppStateView(
                      kind: AppStateKind.loading,
                      title: 'Loading plot forecast',
                      message: 'Checking current and upcoming conditions.',
                      compact: true,
                    )
                  else if (_error != null && plotWeather == null)
                    AppStateView(
                      kind: AppStateKind.error,
                      title: 'Plot weather could not be loaded',
                      message: _error!.message,
                      actionLabel: context.tr('retry'),
                      onAction: _loadPlot,
                      compact: true,
                    )
                  else if (plotWeather != null) ...[
                    if (plotWeather.isStale) ...[
                      const InlineNotice(
                        title: 'Saved weather shown',
                        message: 'The live provider could not be reached. Check the updated time before making weather-sensitive decisions.',
                        color: AppColors.amber,
                        icon: LucideIcons.history,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _CurrentWeatherCard(weather: plotWeather.current),
                    const SizedBox(height: 18),
                    _ForecastStrip(days: plotWeather.forecast),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentWeatherCard extends StatelessWidget {
  const _CurrentWeatherCard({required this.weather});

  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final label =
        weather.conditionLabel ?? _conditionLabel(weather.conditionCode);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F2F5),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: const Color(0xFFCDE0E6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 560;
            final headline = Row(
              children: [
                Icon(
                  _conditionIcon(weather.conditionCode),
                  size: 38,
                  color: AppColors.sky,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        weather.isStale
                            ? context.tr('weatherStale')
                            : context.tr('lastUpdated', {
                                'time': DateFormat.jm().format(
                                  weather.fetchedAt.toLocal(),
                                ),
                              }),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.mutedInk),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${weather.temperature.round()}°',
                  style: Theme.of(context).textTheme.displaySmall
                      ?.copyWith(color: AppColors.forest),
                ),
              ],
            );
            final metrics = Row(
              children: [
                Expanded(
                  child: MetricCell(
                    icon: LucideIcons.cloudRain,
                    value: weather.rainLastHourMm == null
                        ? '${weather.rainChance}%'
                        : '${weather.rainLastHourMm!.toStringAsFixed(1)} mm',
                    label: weather.rainLastHourMm == null
                        ? context.tr('rainChance')
                        : 'Rain in last hour',
                    color: AppColors.sky,
                  ),
                ),
                Expanded(
                  child: MetricCell(
                    icon: LucideIcons.droplets,
                    value: '${weather.humidity}%',
                    label: context.tr('humidity'),
                    color: AppColors.sky,
                  ),
                ),
                Expanded(
                  child: MetricCell(
                    icon: LucideIcons.wind,
                    value: '${weather.windKph.round()} km/h',
                    label: context.tr('wind'),
                    color: AppColors.soil,
                  ),
                ),
              ],
            );
            if (!wide) {
              return Column(
                children: [
                  headline,
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 12),
                  metrics,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: headline),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: metrics),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ForecastStrip extends StatelessWidget {
  const _ForecastStrip({required this.days});

  final List<ForecastDayModel> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const AppStateView(
        kind: AppStateKind.empty,
        title: 'No forecast available',
        message: 'Current conditions are still available above.',
        compact: true,
      );
    }
    return SizedBox(
      height: 184,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final day = days[index];
          return SizedBox(
            width: 132,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      index == 0 ? 'Today' : DateFormat.E().format(day.date),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      DateFormat.MMMd().format(day.date),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.mutedInk),
                    ),
                    const Spacer(),
                    Icon(
                      _conditionIcon(day.conditionCode),
                      color: AppColors.sky,
                      size: 28,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${day.maximumTemperature.round()}° / ${day.minimumTemperature.round()}°',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.cloudRain,
                          size: 14,
                          color: AppColors.sky,
                        ),
                        const SizedBox(width: 4),
                        Text('${day.rainChance}%'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

IconData _conditionIcon(String code) {
  final value = int.tryParse(code);
  if (value == null) return LucideIcons.cloudSun;
  if (value == 0 || value == 800) return LucideIcons.sun;
  if ({1, 2, 3, 801, 802, 803, 804}.contains(value)) {
    return LucideIcons.cloudSun;
  }
  if ({45, 48}.contains(value) || value == 741) return LucideIcons.cloudFog;
  if ((value >= 51 && value <= 67) || (value >= 300 && value < 600)) {
    return LucideIcons.cloudRain;
  }
  if (value >= 71 && value <= 86) return LucideIcons.cloudSnow;
  if ((value >= 95 && value <= 99) || (value >= 200 && value < 300)) {
    return LucideIcons.cloudLightning;
  }
  return LucideIcons.cloudSun;
}

String _conditionLabel(String code) {
  final value = int.tryParse(code);
  if (value == 0 || value == 800) return 'Clear sky';
  if (value != null && ({1, 2, 3, 801, 802, 803, 804}.contains(value))) {
    return 'Partly cloudy';
  }
  if (value != null &&
      ((value >= 51 && value <= 67) || (value >= 300 && value < 600))) {
    return 'Rain expected';
  }
  if (value != null &&
      ((value >= 95 && value <= 99) || (value >= 200 && value < 300))) {
    return 'Thunderstorms';
  }
  return 'Current conditions';
}
