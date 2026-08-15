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
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 118),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 820;
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
                        final tasksCard = _TodayTaskCard(
                          reminders: pendingReminders,
                        );

                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ScanHero(
                                name: controller.farmerName,
                                weather: weather,
                                locationEnabled: controller.locationEnabled,
                                fullBleed: true,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (recentDiagnosis != null) ...[
                                      const SizedBox(height: 18),
                                      continueCard,
                                    ],
                                    const SizedBox(height: 18),
                                    farmsCard,
                                    const SizedBox(height: 18),
                                    tasksCard,
                                    const SizedBox(height: 18),
                                    weatherCard,
                                  ],
                                ),
                              ),
                            ],
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _ScanHero(
                                      name: controller.farmerName,
                                      weather: weather,
                                      locationEnabled:
                                          controller.locationEnabled,
                                    ),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    farmsCard,
                                    const SizedBox(height: 18),
                                    tasksCard,
                                    const SizedBox(height: 18),
                                    weatherCard,
                                  ],
                                ),
                              ),
                            ],
                          ),
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
    this.fullBleed = false,
  });

  final String name;
  final WeatherSnapshot? weather;
  final bool locationEnabled;
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final visualBreathingRoom = 118 - ((textScale - 1).clamp(0.0, 1.0) * 54);
    final radius = BorderRadius.circular(fullBleed ? 0 : AppRadius.hero);
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      borderRadius: radius,
      child: Ink(
        key: const ValueKey('home-scan-hero-stage'),
        decoration: BoxDecoration(
          borderRadius: radius,
          color: const Color(0xFF173526),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/leaf_healthy.jpg',
                fit: BoxFit.cover,
                alignment: const Alignment(0.12, -0.08),
                semanticLabel: 'Healthy green crop leaf ready to scan',
                errorBuilder: (_, _, _) => Image.asset(
                  'assets/images/crop_tomato.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.38, 0.72, 1],
                    colors: [
                      Color(0xA6172D21),
                      Color(0x26172D21),
                      Color(0xB3152C20),
                      Color(0xF20B1C13),
                    ],
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: 92,
              end: 18,
              child: IgnorePointer(
                child: Semantics(
                  excludeSemantics: true,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.56),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 520),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  fullBleed ? 20 : 22,
                  18,
                  fullBleed ? 20 : 22,
                  22,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroTopBar(
                      name: name,
                      weather: weather,
                      locationEnabled: locationEnabled,
                      onImage: true,
                    ),
                    SizedBox(height: visualBreathingRoom),
                    const _HeroText(onImage: true),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _HeroShortcut(
                          icon: LucideIcons.messageCircle,
                          title: 'Ask Saathi',
                          subtitle: 'Crop advice',
                          onTap: () => context.go('/saathi'),
                          onImage: true,
                        ),
                        _HeroShortcut(
                          icon: LucideIcons.warehouse,
                          title: 'My farms',
                          subtitle: 'Plots and crops',
                          onTap: () => context.go('/farm'),
                          onImage: true,
                        ),
                      ],
                    ),
                  ],
                ),
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
    this.onImage = false,
  });

  final String name;
  final WeatherSnapshot? weather;
  final bool locationEnabled;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: onImage ? Colors.white : _strongInk(context),
      fontWeight: FontWeight.w800,
    );
    final identity = GestureDetector(
      onTap: () => context.push('/profile'),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.trim().isNotEmpty) ...[
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
            const SizedBox(height: 2),
          ],
          Text(
            'KrishiSathi',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: onImage
                  ? Colors.white.withValues(alpha: 0.78)
                  : _mutedInk(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    final bell = IconButton.filled(
      tooltip: context.tr('notifications'),
      onPressed: () => context.push('/reminders'),
      style: IconButton.styleFrom(
        backgroundColor: onImage
            ? Colors.black.withValues(alpha: 0.28)
            : Theme.of(context).colorScheme.secondaryContainer,
        foregroundColor: onImage
            ? Colors.white
            : Theme.of(context).colorScheme.onSecondaryContainer,
      ),
      icon: const Icon(LucideIcons.bell, size: 19),
    );
    final chip = _WeatherChip(
      weather: weather,
      locationEnabled: locationEnabled,
      onImage: onImage,
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
  const _HeroText({this.onImage = false});

  final bool onImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: onImage
                ? Colors.black.withValues(alpha: 0.3)
                : AppColors.leaf.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: onImage
                ? Border.all(color: Colors.white.withValues(alpha: 0.22))
                : null,
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 3,
            children: [
              Icon(
                LucideIcons.sparkles,
                size: 15,
                color: onImage ? AppColors.amber : AppColors.leaf,
              ),
              Text(
                'Leaf health assistant',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: onImage ? Colors.white : AppColors.forest,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Scan your crop',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: onImage ? Colors.white : _strongInk(context),
            letterSpacing: -0.7,
            shadows: onImage
                ? const [Shadow(color: Color(0x66000000), blurRadius: 16)]
                : null,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Check leaf health from a photo and continue the result with Saathi.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: onImage
                ? Colors.white.withValues(alpha: 0.86)
                : _mutedInk(context),
            height: 1.42,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => context.go('/scan'),
          icon: const Icon(LucideIcons.scanLine, size: 19),
          label: const Text('Start scan'),
          style: FilledButton.styleFrom(
            backgroundColor: onImage ? Colors.white : AppColors.forest,
            foregroundColor: onImage ? AppColors.forest : Colors.white,
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

class _WeatherChip extends StatelessWidget {
  const _WeatherChip({
    required this.weather,
    required this.locationEnabled,
    this.onImage = false,
  });

  final WeatherSnapshot? weather;
  final bool locationEnabled;
  final bool onImage;

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
              ? Colors.white.withValues(alpha: onImage ? 0.13 : 0.07)
              : Colors.white.withValues(alpha: onImage ? 0.88 : 0.76),
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
                    color: onImage ? AppColors.forest : _strongInk(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: onImage ? AppColors.mutedInk : _mutedInk(context),
                    height: 1,
                  ),
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
    this.onImage = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 146, maxWidth: 210),
      child: Material(
        color: onImage
            ? Colors.black.withValues(alpha: 0.32)
            : Theme.of(context).brightness == Brightness.dark
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
                    color: onImage
                        ? Colors.white.withValues(alpha: 0.14)
                        : AppColors.leaf.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: onImage ? Colors.white : AppColors.forest,
                    size: 18,
                  ),
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
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: onImage ? Colors.white : _strongInk(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: onImage
                              ? Colors.white.withValues(alpha: 0.72)
                              : _mutedInk(context),
                        ),
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
                for (final farm in farms.take(3))
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: farm != farms.take(3).last ? 12.0 : 0.0,
                    ),
                    child: _FarmListTile(
                      farm: farm,
                      pendingTasks: _pendingTasksForFarm(
                        farm,
                        pendingReminders,
                      ),
                    ),
                  ),
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.05)
            : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/farm/${farm.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _countText(cropCount, 'crop', 'crops'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _mutedInk(context)),
                          ),
                          if (pendingTasks > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _countText(pendingTasks, 'task', 'tasks'),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: AppColors.amber,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                          ],
                        ],
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
          if (reminders.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.leaf.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.checkCircle2,
                    color: AppColors.forest,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'All tasks completed for today — crops are well tended!',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.forest,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
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
            _SectionTitle(
              title: name.trim().isEmpty
                  ? 'Today’s weather'
                  : '$name’s weather',
              actionLabel: 'View',
            ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.sky.withValues(alpha: 0.2),
            AppColors.sky.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.cloudSun, color: AppColors.sky, size: 48),
          const SizedBox(height: 12),
          Text(
            locationEnabled
                ? 'Load today’s phone weather.'
                : 'Turn on location to show phone weather.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: _strongInk(context)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: locationEnabled ? onRefresh : null,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Fetch Live Weather'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.sky,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
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
