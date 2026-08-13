import 'dart:io';

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
    final pendingReminders = controller.reminders
        .where((item) => item.status == ReminderStatus.pending)
        .toList();
    final recentDiagnosis = controller.diagnoses.isEmpty
        ? null
        : controller.diagnoses.first;
    final weather = controller.locationEnabled ? controller.weather : null;

    return Scaffold(
      backgroundColor: _homeBaseColor(context),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _homeGradient(context),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: const PageStorageKey('home-scroll'),
            slivers: [
              SliverToBoxAdapter(
                child: AppContent(
                  maxWidth: 1040,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 118),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 820;
                        final hero = _ScanHero(
                          name: controller.farmerName,
                          weather: weather,
                          locationEnabled: controller.locationEnabled,
                        );
                        final continueCard = recentDiagnosis == null
                            ? const SizedBox.shrink()
                            : _ContinueScanCard(diagnosis: recentDiagnosis);
                        final farmsCard = _FarmOverviewCard(
                          farms: controller.farms,
                          pendingReminders: pendingReminders,
                        );
                        final weatherCard = _PersonalWeatherCard(
                          name: controller.farmerName,
                          weather: weather,
                          locationEnabled: controller.locationEnabled,
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
                        );
                        final tasksCard = pendingReminders.isEmpty
                            ? const SizedBox.shrink()
                            : _TodayTaskCard(reminders: pendingReminders);

                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (controller.previewMode) ...[
                                InlineNotice(
                                  title: context.tr('demoMode'),
                                  message: context.tr('demoModeBody'),
                                  color: AppColors.amber,
                                  icon: LucideIcons.flaskConical,
                                ),
                                const SizedBox(height: 16),
                              ],
                              hero,
                              if (recentDiagnosis != null) ...[
                                const SizedBox(height: 18),
                                continueCard,
                              ],
                              const SizedBox(height: 18),
                              farmsCard,
                              if (pendingReminders.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                tasksCard,
                              ],
                              const SizedBox(height: 18),
                              weatherCard,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (controller.previewMode) ...[
                                    InlineNotice(
                                      title: context.tr('demoMode'),
                                      message: context.tr('demoModeBody'),
                                      color: AppColors.amber,
                                      icon: LucideIcons.flaskConical,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  hero,
                                  if (recentDiagnosis != null) ...[
                                    const SizedBox(height: 18),
                                    continueCard,
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  farmsCard,
                                  if (pendingReminders.isNotEmpty) ...[
                                    const SizedBox(height: 18),
                                    tasksCard,
                                  ],
                                  const SizedBox(height: 18),
                                  weatherCard,
                                ],
                              ),
                            ),
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
      ),
    );
  }
}

class _ScanHero extends StatelessWidget {
  const _ScanHero({
    required this.name,
    required this.weather,
    required this.locationEnabled,
  });

  final String name;
  final WeatherSnapshot? weather;
  final bool locationEnabled;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF18261D), Color(0xFF0D1711)]
                : const [Color(0xFFFFFAEF), Color(0xFFEAF1DF)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.22 : 0.08),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE5DDC6),
          ),
        ),
        child: Stack(
          children: [
            const PositionedDirectional(
              top: -42,
              end: -30,
              child: _SoftGlow(size: 168, color: Color(0x6671A858)),
            ),
            const PositionedDirectional(
              bottom: -54,
              start: -40,
              child: _SoftGlow(size: 176, color: Color(0x52D5A43B)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final rowLayout = constraints.maxWidth >= 640;
                  final visual = const _LeafHeroVisual();
                  final text = const _HeroText();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroTopBar(
                        name: name,
                        weather: weather,
                        locationEnabled: locationEnabled,
                      ),
                      const SizedBox(height: 24),
                      if (rowLayout)
                        Row(
                          children: [
                            Expanded(child: text),
                            const SizedBox(width: 26),
                            SizedBox(width: 210, child: visual),
                          ],
                        )
                      else ...[
                        visual,
                        const SizedBox(height: 22),
                        text,
                      ],
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _HeroShortcut(
                            icon: LucideIcons.messageCircle,
                            title: 'Ask Saathi',
                            subtitle: 'Crop advice',
                            onTap: () => context.go('/saathi'),
                          ),
                          _HeroShortcut(
                            icon: LucideIcons.warehouse,
                            title: 'My farms',
                            subtitle: 'Plots and crops',
                            onTap: () => context.go('/farm'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroTopBar extends StatelessWidget {
  const _HeroTopBar({
    required this.name,
    required this.weather,
    required this.locationEnabled,
  });

  final String name;
  final WeatherSnapshot? weather;
  final bool locationEnabled;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: _strongInk(context), fontWeight: FontWeight.w800);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        const SizedBox(height: 2),
        Text(
          'KrishiSathi',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _mutedInk(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final bell = IconButton.filledTonal(
      tooltip: context.tr('notifications'),
      onPressed: () => context.push('/reminders'),
      icon: const Icon(LucideIcons.bell, size: 19),
    );
    final chip = _WeatherChip(
      weather: weather,
      locationEnabled: locationEnabled,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 10),
                  bell,
                ],
              ),
              const SizedBox(height: 10),
              Align(alignment: AlignmentDirectional.centerStart, child: chip),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: identity),
            const SizedBox(width: 12),
            chip,
            const SizedBox(width: 8),
            bell,
          ],
        );
      },
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.leaf.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.sparkles, size: 15, color: AppColors.leaf),
              const SizedBox(width: 6),
              Text(
                'Leaf health assistant',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.forest,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Scan your crop',
          style: Theme.of(context).textTheme.displaySmall
              ?.copyWith(color: _strongInk(context), letterSpacing: -0.7),
        ),
        const SizedBox(height: 7),
        Text(
          'Check leaf health from a photo and continue the result with Saathi.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: _mutedInk(context), height: 1.42),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => context.go('/scan'),
          icon: const Icon(LucideIcons.scanLine, size: 19),
          label: const Text('Start scan'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.forest,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeafHeroVisual extends StatelessWidget {
  const _LeafHeroVisual();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: SizedBox(
        height: 190,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: dark
                      ? const [Color(0xFF2B4E36), Color(0xFF132219)]
                      : const [Color(0xFFFFFFFF), Color(0xFFDDEACF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.forest.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              child: Transform.rotate(
                angle: -0.08,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(42),
                  child: Image.asset(
                    'assets/images/leaf_healthy.jpg',
                    width: 142,
                    height: 164,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFFDDEACF),
                      child: Center(
                        child: Icon(
                          LucideIcons.leaf,
                          size: 72,
                          color: AppColors.forest,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const PositionedDirectional(
              top: 18,
              end: 14,
              child: _MiniPlantBadge(icon: LucideIcons.droplets),
            ),
            const PositionedDirectional(
              bottom: 18,
              start: 16,
              child: _MiniPlantBadge(icon: LucideIcons.sprout),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlantBadge extends StatelessWidget {
  const _MiniPlantBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF203427)
            : Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: AppColors.leaf, size: 19),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  const _WeatherChip({required this.weather, required this.locationEnabled});

  final WeatherSnapshot? weather;
  final bool locationEnabled;

  @override
  Widget build(BuildContext context) {
    final label = weather == null
        ? (locationEnabled ? 'Weather' : 'Location off')
        : '${weather!.temperature.round()}°';
    final caption = weather == null ? 'Home' : _shortCondition(weather!);
    return InkWell(
      onTap: () => context.push('/weather'),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.1)
                : const Color(0xFFE7DFC9),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _conditionIcon(weather),
              size: 16,
              color: weather == null ? AppColors.mutedInk : AppColors.amber,
            ),
            const SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _strongInk(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: _mutedInk(context), height: 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroShortcut extends StatelessWidget {
  const _HeroShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 146, maxWidth: 210),
      child: Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.leaf.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.forest, size: 18),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: _strongInk(context)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: _mutedInk(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueScanCard extends StatelessWidget {
  const _ContinueScanCard({required this.diagnosis});

  final DiagnosisCaseModel diagnosis;

  @override
  Widget build(BuildContext context) {
    final prediction = diagnosis.predictions.isEmpty
        ? null
        : diagnosis.predictions.first;
    return _HomeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: 'Continue',
            actionLabel: 'View all',
            onAction: () => context.go('/scan'),
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DiagnosisThumbnail(diagnosis: diagnosis, size: 76),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${diagnosis.cropName} leaf scan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: _strongInk(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _diagnosisSubtitle(diagnosis, prediction),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: _mutedInk(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => context.push('/scan/result/${diagnosis.id}'),
                icon: const Icon(LucideIcons.eye, size: 17),
                label: const Text('View result'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push(
                  '/saathi/new?scope=scan&context=${Uri.encodeComponent(diagnosis.id)}',
                ),
                icon: const Icon(LucideIcons.messageCircle, size: 17),
                label: const Text('Ask Saathi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FarmOverviewCard extends StatelessWidget {
  const _FarmOverviewCard({
    required this.farms,
    required this.pendingReminders,
  });

  final List<FarmModel> farms;
  final List<FarmReminder> pendingReminders;

  @override
  Widget build(BuildContext context) {
    return _HomeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: context.tr('yourFarms'),
            actionLabel: context.tr('viewAll'),
            onAction: () => context.go('/farm'),
          ),
          const SizedBox(height: 12),
          if (farms.isEmpty)
            AppStateView(
              kind: AppStateKind.empty,
              title: context.tr('noFarmsTitle'),
              message: context.tr('noFarmsBody'),
              actionLabel: context.tr('addFarm'),
              onAction: () => context.push('/farm/add'),
              compact: true,
            )
          else
            Column(
              children: [
                for (final farm in farms.take(3)) ...[
                  _FarmListTile(
                    farm: farm,
                    pendingTasks: _pendingTasksForFarm(farm, pendingReminders),
                  ),
                  if (farm != farms.take(3).last)
                    const Divider(height: 18, indent: 64),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _FarmListTile extends StatelessWidget {
  const _FarmListTile({required this.farm, required this.pendingTasks});

  final FarmModel farm;
  final int pendingTasks;

  @override
  Widget build(BuildContext context) {
    final cropCount = farm.plots.fold<int>(
      0,
      (total, plot) => total + plot.crops.length,
    );
    final asset = CropVisuals.forFarm(
      farm.plots.expand((plot) => plot.crops).map((crop) => crop.name),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/farm/${farm.id}'),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  asset,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFE3EDD8),
                    child: SizedBox.square(
                      dimension: 52,
                      child: Icon(LucideIcons.wheat, color: AppColors.forest),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farm.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: _strongInk(context)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _countText(cropCount, 'crop', 'crops'),
                        if (pendingTasks > 0)
                          _countText(pendingTasks, 'task', 'tasks'),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: _mutedInk(context)),
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: AppColors.mutedInk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayTaskCard extends StatelessWidget {
  const _TodayTaskCard({required this.reminders});

  final List<FarmReminder> reminders;

  @override
  Widget build(BuildContext context) {
    return _HomeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: context.tr('tasksToday'),
            actionLabel: context.tr('viewAll'),
            onAction: () => context.push('/reminders'),
          ),
          const SizedBox(height: 11),
          for (final reminder in reminders.take(2)) ...[
            _ReminderTile(reminder: reminder),
            if (reminder != reminders.take(2).last)
              const Divider(height: 18, indent: 52),
          ],
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder});

  final FarmReminder reminder;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            LucideIcons.clock3,
            color: AppColors.soil,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reminder.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: _strongInk(context)),
              ),
              const SizedBox(height: 2),
              Text(
                '${reminder.plotName} · ${context.strings.formatTime(reminder.dueAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: _mutedInk(context)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: context.tr('done'),
          onPressed: () async {
            try {
              await context.read<AppController>().completeReminder(reminder.id);
            } on ApiException catch (error) {
              if (context.mounted) {
                showAppSnackBar(context, context.localizedError(error));
              }
            }
          },
          icon: const Icon(LucideIcons.circleCheck, size: 21),
        ),
      ],
    );
  }
}

class _PersonalWeatherCard extends StatelessWidget {
  const _PersonalWeatherCard({
    required this.name,
    required this.weather,
    required this.locationEnabled,
    required this.onRefresh,
  });

  final String name;
  final WeatherSnapshot? weather;
  final bool locationEnabled;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final current = weather;
    return _HomeSurface(
      child: InkWell(
        onTap: () => context.push('/weather'),
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(title: '$name’s weather', actionLabel: 'View'),
            const SizedBox(height: 12),
            if (current == null)
              _WeatherEmptyLine(
                locationEnabled: locationEnabled,
                onRefresh: onRefresh,
              )
            else
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.sky.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      _conditionIcon(current),
                      color: AppColors.sky,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${current.temperature.round()}° · ${_conditionText(current)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: _strongInk(context)),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Phone location · ${context.strings.formatTime(current.fetchedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _mutedInk(context)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: AppColors.mutedInk,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _WeatherEmptyLine extends StatelessWidget {
  const _WeatherEmptyLine({
    required this.locationEnabled,
    required this.onRefresh,
  });

  final bool locationEnabled;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = locationEnabled
        ? 'Load today’s phone weather.'
        : 'Turn on location to show phone weather.';
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.leaf.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            LucideIcons.locateFixed,
            color: AppColors.forest,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: _mutedInk(context)),
          ),
        ),
        if (locationEnabled)
          IconButton(
            tooltip: 'Load weather',
            onPressed: onRefresh,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
          ),
      ],
    );
  }
}

class _HomeSurface extends StatelessWidget {
  const _HomeSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark
          ? Colors.white.withValues(alpha: 0.045)
          : Colors.white.withValues(alpha: 0.83),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE8E0CE),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.18 : 0.045),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final action = actionLabel;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: _strongInk(context)),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction ?? () => context.push('/weather'),
            child: Text(action),
          ),
      ],
    );
  }
}

class _DiagnosisThumbnail extends StatelessWidget {
  const _DiagnosisThumbnail({required this.diagnosis, required this.size});

  final DiagnosisCaseModel diagnosis;
  final double size;

  @override
  Widget build(BuildContext context) {
    final localPath = diagnosis.imagePath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox.square(
        dimension: size,
        child: localPath != null && File(localPath).existsSync()
            ? Image.file(File(localPath), fit: BoxFit.cover)
            : Image.asset(
                diagnosis.imageAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFDDEACF),
                  child: Icon(LucideIcons.leaf, color: AppColors.forest),
                ),
              ),
      ),
    );
  }
}

class _SoftGlow extends StatelessWidget {
  const _SoftGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

String _diagnosisSubtitle(
  DiagnosisCaseModel diagnosis,
  DiagnosisPrediction? prediction,
) {
  final issue = prediction == null ? 'possible issue' : prediction.name;
  final confidence = prediction?.confidenceLabel ?? diagnosis.confidenceLabel;
  return 'Possible $issue · ${_confidenceText(confidence)}';
}

String _confidenceText(String value) => switch (value.toLowerCase()) {
  'high' => 'high confidence',
  'medium' => 'medium confidence',
  _ => 'low confidence',
};

String _conditionText(WeatherSnapshot weather) =>
    weather.conditionLabel ?? _shortCondition(weather);

String _shortCondition(WeatherSnapshot weather) {
  final value = (weather.conditionLabel ?? weather.conditionCode)
      .replaceAll('_', ' ')
      .trim();
  if (value.isEmpty) return 'Weather';
  final words = value.split(RegExp(r'\s+'));
  return words.length <= 2 ? value : words.take(2).join(' ');
}

IconData _conditionIcon(WeatherSnapshot? weather) {
  final condition =
      '${weather?.conditionCode ?? ''} ${weather?.conditionLabel ?? ''}'
          .toLowerCase();
  if (condition.contains('rain') || condition.contains('drizzle')) {
    return LucideIcons.cloudRain;
  }
  if (condition.contains('storm') || condition.contains('thunder')) {
    return LucideIcons.cloudLightning;
  }
  if (condition.contains('cloud')) return LucideIcons.cloudSun;
  if (condition.contains('wind')) return LucideIcons.wind;
  return LucideIcons.sun;
}

int _pendingTasksForFarm(FarmModel farm, List<FarmReminder> reminders) {
  final plotIds = farm.plots.map((plot) => plot.id).toSet();
  final plotNames = farm.plots.map((plot) => plot.name).toSet();
  return reminders
      .where(
        (reminder) =>
            reminder.status == ReminderStatus.pending &&
            ((reminder.plotId != null && plotIds.contains(reminder.plotId)) ||
                plotNames.contains(reminder.plotName)),
      )
      .length;
}

String _countText(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

Color _homeBaseColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF0D1711)
    : const Color(0xFFFBF6EA);

List<Color> _homeGradient(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const [Color(0xFF0D1711), Color(0xFF14231B), Color(0xFF0D1711)]
    : const [Color(0xFFFCF7EC), Color(0xFFF2EBD9), Color(0xFFEAF2E1)];

Color _strongInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF5F1E8)
    : AppColors.ink;

Color _mutedInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFB8C5BA)
    : AppColors.mutedInk;
