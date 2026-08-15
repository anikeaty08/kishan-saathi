import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../shared/presentation/app_controller.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = context.read<AppController>();
      if (controller.weather == null && controller.locationEnabled) {
        await _refresh(requestPermission: false);
      }
    });
  }

  Future<void> _refresh({bool requestPermission = true}) async {
    try {
      await context.read<AppController>().refreshCurrentWeather(
        requestPermission: requestPermission,
      );
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final weather = controller.weather;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('weather')),
        actions: [
          IconButton(
            tooltip: 'Refresh current weather',
            onPressed: controller.locationEnabled ? _refresh : null,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: AppContent(
            maxWidth: 760,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 12, bottom: 40),
              children: [
                Text(
                  'Weather for better field decisions',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  'Live conditions from this phone’s current location.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.mutedInk),
                ),
                const SizedBox(height: 20),
                if (!controller.locationEnabled)
                  _LocationRequired(
                    onOpenSettings: () {
                      context.push('/settings/privacy');
                    },
                  )
                else if (weather != null) ...[
                  _WeatherHero(weather: weather),
                  const SizedBox(height: 22),
                  _ConditionsGrid(weather: weather),
                  const SizedBox(height: 18),
                  _FieldNote(weather: weather),
                ] else
                  AppStateView(
                    kind: AppStateKind.empty,
                    title: 'Weather is not loaded yet',
                    message:
                        'Load conditions using this phone’s current location.',
                    actionLabel: 'Load weather',
                    onAction: _refresh,
                    compact: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherHero extends StatelessWidget {
  const _WeatherHero({required this.weather});

  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final label =
        weather.conditionLabel ?? _conditionLabel(weather.conditionCode);
    return Semantics(
      label: '$label, ${weather.temperature.round()} degrees',
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A3D2A), Color(0xFF234837), Color(0xFF1C4230)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: [
            BoxShadow(
              color: AppColors.forest.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Soft glow accent top-right
            PositionedDirectional(
              top: -20,
              end: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFD5A43B).withValues(alpha: 0.18),
                      const Color(0xFFD5A43B).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Condition icon badge
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5A43B)
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(AppRadius.medium),
                          border: Border.all(
                            color: const Color(0xFFD5A43B)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          _conditionIcon(weather.conditionCode),
                          color: const Color(0xFFF1C85B),
                          size: 30,
                        ),
                      ),
                      const Spacer(),
                      // Large temperature
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${weather.temperature.round()}°',
                            style: const TextStyle(
                              color: Color(0xFFF6F1E5),
                              fontSize: 64,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              letterSpacing: -2,
                            ),
                          ),
                          Text(
                            'Celsius',
                            style: TextStyle(
                              color: const Color(0xFFF6F1E5)
                                  .withValues(alpha: 0.5),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFFF6F1E5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        weather.isStale
                            ? LucideIcons.cloudOff
                            : LucideIcons.mapPin,
                        size: 12,
                        color: const Color(0xFFF6F1E5).withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        weather.isStale
                            ? context.tr('weatherStale')
                            : context.tr('lastUpdated', {
                                'time': context.strings.formatTime(
                                  weather.fetchedAt.toLocal(),
                                ),
                              }),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFF6F1E5).withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConditionsGrid extends StatelessWidget {
  const _ConditionsGrid({required this.weather});

  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = <_ConditionData>[
      _ConditionData(
        icon: LucideIcons.cloudRain,
        value: weather.rainLastHourMm == null
            ? '${weather.rainChance}%'
            : '${weather.rainLastHourMm!.toStringAsFixed(1)} mm',
        label: weather.rainLastHourMm == null
            ? context.tr('rainChance')
            : 'Rain in the last hour',
      ),
      _ConditionData(
        icon: LucideIcons.droplets,
        value: '${weather.humidity}%',
        label: context.tr('humidity'),
      ),
      _ConditionData(
        icon: LucideIcons.wind,
        value: '${weather.windKph.round()} km/h',
        label: context.tr('wind'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 92,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [const Color(0xFF1D3428), const Color(0xFF26382E)]
                      : [const Color(0xFFEBF2E3), const Color(0xFFDDE8D3)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.medium),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : AppColors.divider,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      color: dark ? AppColors.youngLeaf : AppColors.forest,
                      size: 21,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.value,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: dark
                                      ? Colors.white.withValues(alpha: 0.68)
                                      : AppColors.mutedInk,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FieldNote extends StatelessWidget {
  const _FieldNote({required this.weather});

  final WeatherSnapshot weather;

  String get _message {
    if (weather.isStale) {
      return 'Refresh before making a weather-sensitive field decision.';
    }
    if ((weather.rainLastHourMm ?? 0) > 0 || weather.rainChance >= 60) {
      return 'Rain is likely. Keep harvested produce covered and inspect drainage.';
    }
    if (weather.windKph >= 25) {
      return 'Strong wind today. Secure light covers before starting field work.';
    }
    if (weather.temperature >= 35) {
      return 'Hot conditions. Prefer early-morning crop inspection and carry water.';
    }
    return 'Conditions look suitable for a routine crop inspection.';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3B321F) : const Color(0xFFF0E2BC),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border(left: BorderSide(color: AppColors.amber, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              LucideIcons.wheat,
              color: dark ? const Color(0xFFF1C85B) : const Color(0xFF76591B),
              size: 21,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Field note',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(_message, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationRequired extends StatelessWidget {
  const _LocationRequired({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => AppStateView(
    kind: AppStateKind.empty,
    title: 'Turn on location for weather',
    message: 'KrishiSathi uses this phone’s current location only when loading weather.',
    actionLabel: 'Open privacy settings',
    onAction: onOpenSettings,
    compact: true,
  );
}

class _ConditionData {
  const _ConditionData({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;
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
