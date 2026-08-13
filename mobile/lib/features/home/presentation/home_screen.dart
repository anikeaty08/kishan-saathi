import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../../core/ui/crop_visuals.dart';
import '../../shared/presentation/app_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final date = context.strings.formatWeekdayDate(DateTime.now());
    final pendingReminders = controller.reminders
        .where((item) => item.status == ReminderStatus.pending)
        .toList();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('home-scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: AppContent(
                maxWidth: 1080,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _HomeHeader(name: controller.farmerName, date: date),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(top: 22, bottom: 110),
              sliver: SliverToBoxAdapter(
                child: AppContent(
                  maxWidth: 1080,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final expanded = constraints.maxWidth >= 760;
                      final primary = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (controller.previewMode) ...[
                            InlineNotice(
                              title: context.tr('demoMode'),
                              message: context.tr('demoModeBody'),
                              color: AppColors.amber,
                              icon: LucideIcons.flaskConical,
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (controller.locationEnabled) ...[
                            if (controller.weather case final weather?)
                              _WeatherPanel(weather: weather)
                            else
                              _WeatherUnavailable(
                                onRefresh: () async {
                                  try {
                                    await context
                                        .read<AppController>()
                                        .refreshCurrentWeather();
                                  } on ApiException catch (error) {
                                    if (context.mounted) {
                                      showAppSnackBar(
                                        context,
                                        context.localizedError(error),
                                      );
                                    }
                                  }
                                },
                              ),
                            const SizedBox(height: 26),
                          ],
                          SectionHeader(
                            title: context.tr('yourFarms'),
                            action: TextButton(
                              onPressed: () => context.go('/farm'),
                              child: Text(context.tr('viewAll')),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (controller.farms.isEmpty)
                            AppStateView(
                              kind: AppStateKind.empty,
                              title: context.tr('noFarmsTitle'),
                              message: context.tr('noFarmsBody'),
                              actionLabel: context.tr('addFarm'),
                              onAction: () => context.push('/farm/add'),
                              compact: true,
                            )
                          else
                            _FarmFeature(farm: controller.farms.first),
                          const SizedBox(height: 26),
                          SectionHeader(
                            title: context.tr('recentChecks'),
                            action: TextButton(
                              onPressed: () => context.go('/scan'),
                              child: Text(context.tr('scan')),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (controller.diagnoses.isNotEmpty)
                            _DiagnosisRow(
                              diagnosis: controller.diagnoses.first,
                            ),
                        ],
                      );
                      final secondary = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(
                            title: context.tr('tasksToday'),
                            action: IconButton(
                              tooltip: context.tr('viewAll'),
                              onPressed: () => context.push('/reminders'),
                              icon: const Icon(LucideIcons.arrowRight),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (pendingReminders.isEmpty)
                            AppStateView(
                              kind: AppStateKind.success,
                              title: 'All clear for today',
                              message:
                                  'New accepted reminders will appear here.',
                              compact: true,
                            )
                          else
                            ...pendingReminders
                                .take(3)
                                .map(
                                  (reminder) =>
                                      _ReminderRow(reminder: reminder),
                                ),
                          const SizedBox(height: 24),
                          _QuickActions(),
                        ],
                      );
                      if (!expanded) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            primary,
                            const SizedBox(height: 26),
                            secondary,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: primary),
                          const SizedBox(width: 28),
                          Expanded(flex: 3, child: secondary),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.name, required this.date});

  final String name;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('goodMorning', {'name': name}),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 3),
              Text(
                date,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedInk),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: context.tr('notifications'),
          onPressed: () => context.push('/reminders'),
          icon: const Icon(LucideIcons.bell, size: 20),
        ),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          label: context.tr('profile'),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            onTap: () => context.push('/profile'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              child: Image.asset(
                'assets/images/farmer_portrait.jpg',
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeatherPanel extends StatelessWidget {
  const _WeatherPanel({required this.weather});

  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final time = context.strings.formatTime(weather.fetchedAt);
    return InkWell(
      onTap: () => context.push('/weather'),
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFFE8F2F5),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: const Color(0xFFCDE0E6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    LucideIcons.cloudSun,
                    size: 28,
                    color: AppColors.sky,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          weather.conditionLabel ?? 'Current weather',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          weather.isStale
                              ? context.tr('weatherStale')
                              : context.tr('lastUpdated', {'time': time}),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.mutedInk),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${weather.temperature.round()}°',
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(color: AppColors.forest),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: MetricCell(
                      icon: LucideIcons.cloudRain,
                      value: weather.rainLastHourMm == null
                          ? '${weather.rainChance}%'
                          : '${weather.rainLastHourMm!.toStringAsFixed(1)} mm',
                      label: weather.rainLastHourMm == null
                          ? context.tr('rainChance')
                          : 'Rain, last hour',
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherUnavailable extends StatelessWidget {
  const _WeatherUnavailable({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => AppStateView(
    kind: AppStateKind.empty,
    title: 'Weather needs your location',
    message: 'Use the phone\'s current location to load weather. KrishiSathi reuses the server-cached update for up to one hour.',
    actionLabel: 'Load weather',
    onAction: onRefresh,
    compact: true,
  );
}

class _FarmFeature extends StatelessWidget {
  const _FarmFeature({required this.farm});

  final FarmModel farm;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Semantics(
      button: true,
      label: '${farm.name}, ${farm.displayLocation ?? 'no plot location'}',
      child: InkWell(
        onTap: () => context.push('/farm/${farm.id}'),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: ImageBand(
          asset: CropVisuals.forFarm(
            farm.plots.expand((plot) => plot.crops).map((crop) => crop.name),
          ),
          height: 224,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                farm.name,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                farm.displayLocation ?? 'Add the first plot location',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.86)),
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _ImageLabel(
                    icon: LucideIcons.map,
                    text: '${farm.plots.length} plots',
                  ),
                  _ImageLabel(
                    icon: LucideIcons.ruler,
                    text: controller.formatFarmArea(farm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageLabel extends StatelessWidget {
  const _ImageLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: Colors.white),
      const SizedBox(width: 6),
      Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Colors.white),
      ),
    ],
  );
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder});
  final FarmReminder reminder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: const Icon(
                  LucideIcons.clock3,
                  color: AppColors.soil,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${reminder.plotName} · ${context.strings.formatTime(reminder.dueAt)}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.mutedInk),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('done'),
                onPressed: () async {
                  try {
                    await context.read<AppController>().completeReminder(
                      reminder.id,
                    );
                  } on ApiException catch (error) {
                    if (context.mounted) {
                      showAppSnackBar(context, context.localizedError(error));
                    }
                  }
                },
                icon: const Icon(LucideIcons.circleCheck, size: 21),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/scan'),
                icon: const Icon(LucideIcons.scanLine, size: 18),
                label: Text(context.tr('scan')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/saathi'),
                icon: const Icon(LucideIcons.messageCircle, size: 18),
                label: Text(context.tr('saathi')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DiagnosisRow extends StatelessWidget {
  const _DiagnosisRow({required this.diagnosis});
  final DiagnosisCaseModel diagnosis;

  @override
  Widget build(BuildContext context) {
    final prediction = diagnosis.predictions.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/scan/result/${diagnosis.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.small),
                child: Image.asset(
                  diagnosis.imageAsset,
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (diagnosis.isSample)
                      Text(
                        context.tr('sampleOnly'),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AppColors.amber),
                      ),
                    Text(
                      prediction.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${diagnosis.cropName} · ${context.tr('confidenceMedium')}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.mutedInk),
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: AppColors.mutedInk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
