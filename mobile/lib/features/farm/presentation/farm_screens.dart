import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../../core/ui/crop_visuals.dart';
import '../../shared/presentation/app_controller.dart';
import '../../saathi/data/chat_scope_policy.dart';

class FarmScreen extends StatelessWidget {
  const FarmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('farm')),
        actions: [
          IconButton(
            tooltip: context.tr('addFarm'),
            onPressed: () => context.push('/farm/add'),
            icon: const Icon(LucideIcons.plus),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: controller.farms.isEmpty
            ? AppStateView(
                kind: AppStateKind.empty,
                title: context.tr('noFarmsTitle'),
                message: context.tr('noFarmsBody'),
                actionLabel: context.tr('addFarm'),
                onAction: () => context.push('/farm/add'),
              )
            : AppContent(
                maxWidth: 1100,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final expanded = constraints.maxWidth >= 760;
                    final map = _FarmMap(farms: controller.farms);
                    final list = ListView.separated(
                      key: const PageStorageKey('farm-list'),
                      padding: EdgeInsets.fromLTRB(
                        0,
                        expanded ? 12 : 18,
                        0,
                        110,
                      ),
                      itemCount: controller.farms.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return SectionHeader(
                            title: context.tr('yourFarms'),
                            subtitle: context.tr('activeCount', {
                              'count': controller.farms.length,
                            }),
                          );
                        }
                        return _FarmListItem(farm: controller.farms[index - 1]);
                      },
                    );
                    if (!expanded) {
                      return Column(
                        children: [
                          SizedBox(height: 220, child: map),
                          Expanded(child: list),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: map,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(flex: 4, child: list),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _FarmMap extends StatelessWidget {
  const _FarmMap({required this.farms});
  final List<FarmModel> farms;

  @override
  Widget build(BuildContext context) {
    final mappable = farms
        .expand((farm) => farm.plots.map((plot) => (farm: farm, plot: plot)))
        .toList(growable: false);
    if (mappable.isEmpty) {
      return AppStateView(
        kind: AppStateKind.empty,
        title: context.tr('noPlotLocationsYet'),
        message: context.tr('noPlotLocationsBody'),
        actionLabel: farms.length == 1 ? context.tr('addPlot') : null,
        onAction: farms.length == 1
            ? () => context.push('/farm/${farms.first.id}/plot/add')
            : null,
        compact: true,
      );
    }
    final center = LatLng(
      mappable.fold<double>(0, (sum, item) => sum + item.plot.latitude) /
          mappable.length,
      mappable.fold<double>(0, (sum, item) => sum + item.plot.longitude) /
          mappable.length,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2, end: 2, bottom: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: mappable.length == 1 ? 14 : 11.5,
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: context
                      .read<AppController>()
                      .config
                      .mapTileUrlTemplate,
                  userAgentPackageName: 'com.krishisathi.mobile',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: mappable
                      .map(
                        (item) => Marker(
                          point: LatLng(
                            item.plot.latitude,
                            item.plot.longitude,
                          ),
                          width: 52,
                          height: 52,
                          child: Semantics(
                            label: '${item.farm.name}, ${item.plot.name}',
                            button: true,
                            child: GestureDetector(
                              onTap: () =>
                                  context.push('/plot/${item.plot.id}'),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.forest,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.medium,
                                  ),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x33000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  LucideIcons.sprout,
                                  color: Colors.white,
                                  size: 23,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            PositionedDirectional(
              top: 12,
              start: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.map, size: 17),
                      const SizedBox(width: 7),
                      Text(
                        context.tr('map'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
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

class _FarmListItem extends StatelessWidget {
  const _FarmListItem({required this.farm});
  final FarmModel farm;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/farm/${farm.id}'),
        child: Row(
          children: [
            Image.asset(
              CropVisuals.forFarm(
                farm.plots
                    .expand((plot) => plot.crops)
                    .map((crop) => crop.name),
              ),
              width: 110,
              height: 112,
              fit: BoxFit.cover,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farm.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      farm.displayLocation ?? 'Add a plot location',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.mutedInk),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _InlineFact(
                          icon: LucideIcons.map,
                          text: '${farm.plots.length} plots',
                        ),
                        _InlineFact(
                          icon: LucideIcons.ruler,
                          text: controller.formatFarmArea(farm, compact: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 10),
              child: Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: AppColors.mutedInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FarmDetailScreen extends StatelessWidget {
  const FarmDetailScreen({super.key, required this.farmId});
  final String farmId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final farm = controller.farmById(farmId);
    if (farm == null) {
      return Scaffold(
        appBar: AppBar(),
        body: AppStateView(
          kind: AppStateKind.error,
          title: context.tr('errorTitle'),
          message: context.tr('farmCouldNotBeFound'),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(farm.name),
          actions: [
            PopupMenuButton<String>(
              tooltip: context.tr('farmActions'),
              onSelected: (value) {
                if (value == 'edit') {
                  context.push('/farm/${farm.id}/edit');
                }
                if (value == 'delete') _showDeletionImpact(context, farm);
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(context.tr('edit'))),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.tr('delete')),
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AppContent(
            maxWidth: 1000,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ImageBand(
                    asset: CropVisuals.forFarm(
                      farm.plots
                          .expand((plot) => plot.crops)
                          .map((crop) => crop.name),
                    ),
                    height: 192,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        Text(
                          farm.displayLocation ?? 'No plot location yet',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          children: [
                            _ImageFact(
                              icon: LucideIcons.map,
                              text: '${farm.plots.length} plots',
                            ),
                            _ImageFact(
                              icon: LucideIcons.ruler,
                              text: controller.formatFarmArea(farm),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TabBar(
                  tabs: [
                    Tab(text: context.tr('plots')),
                    Tab(text: context.tr('activities')),
                    Tab(text: context.tr('map')),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _PlotsTab(farm: farm),
                      _FarmActivitiesTab(farm: farm),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: _FarmMap(farms: [farm]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/farm/${farm.id}/plot/add'),
          icon: const Icon(LucideIcons.plus),
          label: Text(context.tr('addPlot')),
        ),
      ),
    );
  }

  Future<void> _showDeletionImpact(BuildContext context, FarmModel farm) async {
    late final DeletionImpact impact;
    try {
      impact = await context.read<AppController>().farmDeletionImpact(farm.id);
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
      return;
    }
    if (!context.mounted) return;
    final delete = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete ${farm.name}?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                impact.linkedRecordCount == 0
                    ? 'No linked records will be lost.'
                    : 'This farm has ${impact.linkedRecordCount} linked records. Remove or move them before deleting the farm.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 18),
              InlineNotice(
                title: impact.canDelete
                    ? 'Ready to delete'
                    : 'Linked data must be reviewed',
                message: impact.linkedRecords.isEmpty
                    ? 'Deleting removes the farm name. Plot data remains protected by deletion rules.'
                    : impact.linkedRecords.entries
                          .where((entry) => entry.value > 0)
                          .map((entry) => '${entry.key}: ${entry.value}')
                          .join(' · '),
                color: impact.canDelete ? AppColors.leaf : AppColors.danger,
                icon: impact.canDelete
                    ? LucideIcons.circleCheck
                    : LucideIcons.triangleAlert,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: impact.canDelete
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  child: Text(context.tr('delete')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!(delete ?? false) || !context.mounted) return;
    try {
      await context.read<AppController>().deleteFarm(farm.id);
      if (context.mounted) context.go('/farm');
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }
}

class _PlotsTab extends StatelessWidget {
  const _PlotsTab({required this.farm});
  final FarmModel farm;

  @override
  Widget build(BuildContext context) {
    if (farm.plots.isEmpty) {
      return AppStateView(
        kind: AppStateKind.empty,
        title: context.tr('noPlotsYet'),
        message: context.tr('noPlotsBody'),
        actionLabel: context.tr('addPlot'),
        onAction: () => context.push('/farm/${farm.id}/plot/add'),
      );
    }
    return ListView.separated(
      key: const PageStorageKey('plots-list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      itemCount: farm.plots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _PlotRow(plot: farm.plots[index]),
    );
  }
}

class _PlotRow extends StatelessWidget {
  const _PlotRow({required this.plot});
  final PlotModel plot;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final crop = plot.crops.where((crop) => crop.isActive).firstOrNull;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: () => context.push('/plot/${plot.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.leaf.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: const Icon(LucideIcons.sprout, color: AppColors.forest),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plot.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        crop?.name ?? 'No active crop',
                        if (plot.area != null)
                          controller.formatArea(plot.area!, plot.areaUnit),
                      ].join(' · '),
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

class _FarmActivitiesTab extends StatelessWidget {
  const _FarmActivitiesTab({required this.farm});
  final FarmModel farm;

  @override
  Widget build(BuildContext context) {
    final items =
        farm.plots
            .expand(
              (plot) => plot.activities.map((activity) => (plot, activity)),
            )
            .toList()
          ..sort((a, b) => b.$2.occurredAt.compareTo(a.$2.occurredAt));
    if (items.isEmpty) {
      return AppStateView(
        kind: AppStateKind.empty,
        title: context.tr('noActivityRecorded'),
        message: context.tr('noActivityRecordedBody'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(indent: 52),
      itemBuilder: (context, index) {
        final (plot, activity) = items[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            backgroundColor: Color(0x172E7D4F),
            foregroundColor: AppColors.forest,
            child: Icon(LucideIcons.clipboardList, size: 19),
          ),
          title: Text(activity.title),
          subtitle: Text(
            '${plot.name} · ${context.strings.formatShortDate(activity.occurredAt)}',
          ),
        );
      },
    );
  }
}

class PlotDetailScreen extends StatefulWidget {
  const PlotDetailScreen({super.key, required this.plotId});
  final String plotId;

  @override
  State<PlotDetailScreen> createState() => _PlotDetailScreenState();
}

class _PlotDetailScreenState extends State<PlotDetailScreen> {
  bool _loadingTimeline = true;
  ApiException? _timelineError;
  ApiException? _weatherError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlotData());
  }

  Future<void> _loadPlotData() async {
    final controller = context.read<AppController>();
    await Future.wait([
      () async {
        try {
          await Future.wait([
            controller.loadPlotTimeline(widget.plotId),
            controller.loadPlotActivities(widget.plotId),
          ]);
        } on ApiException catch (error) {
          _timelineError = error;
        }
      }(),
      () async {
        try {
          await controller.loadPlotWeather(widget.plotId);
        } on ApiException catch (error) {
          _weatherError = error;
        }
      }(),
    ]);
    if (mounted) setState(() => _loadingTimeline = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final plot = controller.plotById(widget.plotId);
    if (plot == null) {
      return Scaffold(
        appBar: AppBar(),
        body: AppStateView(
          kind: AppStateKind.error,
          title: context.tr('plotNotFound'),
          message: context.tr('plotRemovedBody'),
        ),
      );
    }
    final crop = plot.crops.where((crop) => crop.isActive).firstOrNull;
    final timeline = controller.plotTimelines[plot.id] ?? const [];
    final plotWeather = controller.plotWeather[plot.id];
    final plotDiagnoses = controller.diagnoses
        .where((diagnosis) => diagnosis.plotId == plot.id)
        .toList(growable: false);
    final plotChats = controller.chats
        .where(
          (chat) => ChatScopePolicy.belongsToPlot(
            chat,
            plot.id,
            diagnosisIds: plotDiagnoses.map((item) => item.id).toSet(),
          ),
        )
        .toList(growable: false);
    final plotReminders = controller.reminders
        .where((reminder) => reminder.plotId == plot.id)
        .toList(growable: false);
    final cropImage = CropVisuals.forCrop(crop?.name);
    return Scaffold(
      appBar: AppBar(
        title: Text(plot.name),
        actions: [
          IconButton(
            tooltip: context.tr('edit'),
            onPressed: () => context.push('/plot/${plot.id}/edit'),
            icon: const Icon(LucideIcons.pencil),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 860,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 110),
            children: [
              ImageBand(
                asset: cropImage,
                height: 214,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text(
                      crop?.name ?? 'No active crop',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${crop?.variety ?? ''} · ${crop?.stage ?? ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: MetricCell(
                      icon: LucideIcons.ruler,
                      value: plot.area == null
                          ? '—'
                          : controller.formatArea(plot.area!, plot.areaUnit),
                      label: context.tr('area'),
                    ),
                  ),
                  Expanded(
                    child: MetricCell(
                      icon: LucideIcons.layers3,
                      value: plot.soilType ?? 'Not recorded',
                      label: context.tr('soilType'),
                      color: AppColors.soil,
                    ),
                  ),
                  Expanded(
                    child: MetricCell(
                      icon: LucideIcons.droplets,
                      value: plot.irrigation ?? 'Not recorded',
                      label: context.tr('irrigation'),
                      color: AppColors.sky,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionHeader(title: context.tr('weather')),
              const SizedBox(height: 10),
              if (plotWeather != null)
                _PlotWeatherSummary(weather: plotWeather)
              else if (_weatherError != null)
                AppStateView(
                  kind: AppStateKind.error,
                  title: context.tr('plotWeatherUnavailable'),
                  message: _weatherError!.message,
                  actionLabel: context.tr('retry'),
                  onAction: () async {
                    setState(() => _weatherError = null);
                    try {
                      await context.read<AppController>().loadPlotWeather(
                        plot.id,
                      );
                    } on ApiException catch (error) {
                      if (mounted) setState(() => _weatherError = error);
                    }
                  },
                  compact: true,
                )
              else
                AppStateView(
                  kind: AppStateKind.loading,
                  title: context.tr('loadingPlotWeather'),
                  message: context.tr('loadingPlotWeatherBody'),
                  compact: true,
                ),
              const SizedBox(height: 24),
              SectionHeader(
                title: context.tr('plotRecords'),
                subtitle: context.tr('plotRecordsBody'),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700 ? 4 : 2;
                  final width =
                      (constraints.maxWidth - ((columns - 1) * 10)) / columns;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _PlotRecordCard(
                        width: width,
                        icon: LucideIcons.scanLine,
                        label: context.tr('leafChecks'),
                        count: plotDiagnoses.length,
                        onTap: () => plotDiagnoses.isEmpty
                            ? context.go('/scan?plot=${plot.id}')
                            : context.push(
                                '/scan/result/${plotDiagnoses.first.id}',
                              ),
                      ),
                      _PlotRecordCard(
                        width: width,
                        icon: LucideIcons.messagesSquare,
                        label: context.tr('chats'),
                        count: plotChats.length,
                        onTap: () => plotChats.isEmpty
                            ? context.push(
                                '/saathi/new?scope=plot&context=${plot.id}',
                              )
                            : context.push(
                                '/saathi/chat/${plotChats.first.id}',
                              ),
                      ),
                      _PlotRecordCard(
                        width: width,
                        icon: LucideIcons.bell,
                        label: context.tr('reminders'),
                        count: plotReminders.length,
                        onTap: () => context.push('/reminders'),
                      ),
                      _PlotRecordCard(
                        width: width,
                        icon: LucideIcons.clipboardCheck,
                        label: context.tr('activities'),
                        count: plot.activities.length,
                        onTap: () => context.push('/plot/${plot.id}/history'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              SectionHeader(
                title: context.tr('crops'),
                action: TextButton.icon(
                  onPressed: () => context.push('/plot/${plot.id}/crops'),
                  icon: const Icon(LucideIcons.settings2, size: 18),
                  label: Text(context.tr('manage')),
                ),
              ),
              const SizedBox(height: 10),
              if (plot.crops.isEmpty)
                AppStateView(
                  kind: AppStateKind.empty,
                  title: context.tr('noCropsRecorded'),
                  message: context.tr('noCropsRecordedBody'),
                  compact: true,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: plot.crops
                      .map(
                        (item) => Chip(
                          avatar: Icon(
                            item.isActive
                                ? LucideIcons.sprout
                                : LucideIcons.archive,
                            size: 16,
                          ),
                          label: Text(
                            '${item.name} - ${item.isActive ? item.stage : 'closed'}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 20),
              SectionHeader(
                title: context.tr('timeline'),
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/plot/${plot.id}/history'),
                      child: Text(context.tr('viewAll')),
                    ),
                    IconButton(
                      tooltip: context.tr('addActivity'),
                      onPressed: () =>
                          context.push('/plot/${plot.id}/activity/add'),
                      icon: const Icon(LucideIcons.plus, size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_loadingTimeline)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_timelineError != null)
                AppStateView(
                  kind: AppStateKind.error,
                  title: context.tr('timelineLoadFailed'),
                  message: _timelineError!.message,
                  actionLabel: 'Try again',
                  onAction: () {
                    setState(() {
                      _loadingTimeline = true;
                      _timelineError = null;
                    });
                    _loadPlotData();
                  },
                  compact: true,
                )
              else if (timeline.isEmpty)
                AppStateView(
                  kind: AppStateKind.empty,
                  title: context.tr('noPlotHistoryYet'),
                  message: context.tr('noPlotHistoryBody'),
                  compact: true,
                )
              else
                ...timeline
                    .take(8)
                    .map(
                      (event) => _TimelineItem(event: event, plotId: plot.id),
                    ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/scan?plot=${plot.id}'),
        icon: const Icon(LucideIcons.scanLine),
        label: Text(context.tr('scan')),
      ),
    );
  }
}

class _PlotRecordCard extends StatelessWidget {
  const _PlotRecordCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.leaf, size: 21),
                const SizedBox(height: 12),
                Text('$count', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.mutedInk),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlotWeatherSummary extends StatelessWidget {
  const _PlotWeatherSummary({required this.weather});

  final PlotWeatherModel weather;

  @override
  Widget build(BuildContext context) {
    final tomorrow = weather.forecast.length > 1 ? weather.forecast[1] : null;
    final current = weather.current;
    return Card(
      color: const Color(0xFFE8F2F5),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(LucideIcons.cloudSun, color: AppColors.sky, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current?.conditionLabel ??
                        (current == null
                            ? 'Current conditions unavailable'
                            : 'Current conditions'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tomorrow == null
                        ? 'Forecast details are available'
                        : 'Tomorrow: ${tomorrow.minimumTemperature.round()}–${tomorrow.maximumTemperature.round()}° · ${tomorrow.rainChance}% rain',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.mutedInk),
                  ),
                ],
              ),
            ),
            Text(
              current == null ? '—' : '${current.temperature.round()}°',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: AppColors.forest),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.event, required this.plotId});
  final TimelineEventModel event;
  final String plotId;

  @override
  Widget build(BuildContext context) {
    final child = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _timelineColor(event.category),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(child: Container(width: 1, color: AppColors.divider)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.strings.formatDateTime(event.occurredAt.toLocal()),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.mutedInk),
                  ),
                  if (_timelineDetail(context, event) case final detail?) ...[
                    const SizedBox(height: 6),
                    Text(detail),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (event.category != 'activity') return child;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      onTap: () => context.push('/plot/$plotId/activity/${event.referenceId}'),
      child: child,
    );
  }
}

Color _timelineColor(String category) => switch (category) {
  'diagnosis' => AppColors.amber,
  'chat' => AppColors.sky,
  'reminder' => AppColors.soil,
  'crop_stage' || 'crop_cycle' => AppColors.youngLeaf,
  _ => AppColors.leaf,
};

String? _timelineDetail(BuildContext context, TimelineEventModel event) =>
    switch (event.category) {
      'diagnosis' => switch (event.data['confidence_label']) {
        final String confidence => '$confidence confidence',
        _ => event.data['plant_name'] as String?,
      },
      'activity' => event.data['notes'] as String?,
      'chat' => 'Saathi conversation',
      'reminder' => switch (event.data['due_at']) {
        final String dueAt => context.tr('date.due', {
          'date': context.strings.formatDateTime(
            DateTime.parse(dueAt).toLocal(),
          ),
        }),
        _ => null,
      },
      _ => null,
    };

class ManageCropsScreen extends StatelessWidget {
  const ManageCropsScreen({super.key, required this.plotId});

  final String plotId;

  @override
  Widget build(BuildContext context) {
    final plot = context.watch<AppController>().plotById(plotId);
    if (plot == null) {
      return Scaffold(
        appBar: AppBar(),
        body: AppStateView(
          kind: AppStateKind.error,
          title: context.tr('plotNotFound'),
          message: context.tr('plotRemovedBody'),
        ),
      );
    }
    final crops = [...plot.crops]
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('cropCycles'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 100),
            children: [
              InlineNotice(
                title: context.tr('multipleCropsHelp'),
                message: context.tr('multipleCropsHelpBody'),
                icon: LucideIcons.sprout,
                color: AppColors.leaf,
              ),
              const SizedBox(height: 20),
              if (crops.isEmpty)
                AppStateView(
                  kind: AppStateKind.empty,
                  title: context.tr('noCropCycles'),
                  message: context.tr('noCropCyclesBody'),
                  actionLabel: 'Add crop',
                  onAction: () => _editCrop(context, plot),
                )
              else
                ...crops.map(
                  (crop) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                crop.isActive
                                    ? LucideIcons.sprout
                                    : LucideIcons.archive,
                                color: crop.isActive
                                    ? AppColors.leaf
                                    : AppColors.mutedInk,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      crop.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      [
                                        if (crop.variety != null) crop.variety!,
                                        crop.isActive
                                            ? crop.stage
                                            : 'Cycle closed',
                                      ].join(' - '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppColors.mutedInk),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (action) =>
                                    _act(context, plot, crop, action),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(context.tr('editDetails')),
                                  ),
                                  if (crop.isActive) ...[
                                    PopupMenuItem(
                                      value: 'stage',
                                      child: Text(context.tr('updateStage')),
                                    ),
                                    PopupMenuItem(
                                      value: 'close',
                                      child: Text(context.tr('closeCropCycle')),
                                    ),
                                  ],
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(context.tr('deleteCrop')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (crop.sownOn != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              context.tr('date.sownOrTransplanted', {
                                'date': context.strings.formatDate(
                                  crop.sownOn!,
                                ),
                              }),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCrop(context, plot),
        icon: const Icon(LucideIcons.plus),
        label: Text(context.tr('addCrop')),
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    PlotModel plot,
    CropModel crop,
    String action,
  ) async {
    switch (action) {
      case 'edit':
        return _editCrop(context, plot, crop: crop);
      case 'stage':
        return _updateStage(context, plot, crop);
      case 'close':
        return _closeCycle(context, plot, crop);
      case 'delete':
        return _deleteCrop(context, plot, crop);
    }
  }

  Future<void> _editCrop(
    BuildContext context,
    PlotModel plot, {
    CropModel? crop,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CropEditorSheet(plot: plot, crop: crop),
    );
  }

  Future<void> _updateStage(
    BuildContext context,
    PlotModel plot,
    CropModel crop,
  ) async {
    final stage = TextEditingController(text: crop.stage);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('updateCropStage', {'crop': crop.name})),
        content: TextField(
          controller: stage,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: context.tr('currentStage')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, stage.text.trim()),
            child: Text(context.tr('save')),
          ),
        ],
      ),
    );
    stage.dispose();
    if (value == null || value.isEmpty || !context.mounted) return;
    try {
      await context.read<AppController>().updateCropStage(
        plotId: plot.id,
        crop: crop,
        stage: value,
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }

  Future<void> _closeCycle(
    BuildContext context,
    PlotModel plot,
    CropModel crop,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('closeNamedCropCycle', {'crop': crop.name})),
        content: Text(context.tr('closeCropCycleBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('closeCycle')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<AppController>().closeCropCycle(
        plotId: plot.id,
        crop: crop,
        endedOn: DateTime.now(),
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }

  Future<void> _deleteCrop(
    BuildContext context,
    PlotModel plot,
    CropModel crop,
  ) async {
    try {
      final controller = context.read<AppController>();
      final impact = await controller.cropDeletionImpact(crop.id);
      if (!context.mounted) return;
      final linked = impact.linkedRecords.entries
          .where((entry) => entry.value > 0)
          .toList(growable: false);
      if (!impact.canDelete) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('cropCannotDeleteYet')),
            content: Text(
              linked.isEmpty
                  ? 'Remove or unlink the records connected to this crop first.'
                  : 'First remove or unlink: ${linked.map((entry) => '${entry.value} ${entry.key.replaceAll('_', ' ')}').join(', ')}.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr('close')),
              ),
            ],
          ),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('deleteNamedCrop', {'crop': crop.name})),
          content: Text(
            linked.isEmpty
                ? 'This removes the crop cycle from the plot.'
                : 'This also removes ${linked.map((entry) => '${entry.value} ${entry.key.replaceAll('_', ' ')}').join(', ')}. This history cannot be restored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('delete')),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false) || !context.mounted) return;
      await controller.deleteCrop(
        plotId: plot.id,
        cropId: crop.id,
        confirmHistoryLoss: linked.isNotEmpty,
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }
}

class _CropEditorSheet extends StatefulWidget {
  const _CropEditorSheet({required this.plot, this.crop});

  final PlotModel plot;
  final CropModel? crop;

  @override
  State<_CropEditorSheet> createState() => _CropEditorSheetState();
}

class _CropEditorSheetState extends State<_CropEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _variety;
  late final TextEditingController _stage;
  DateTime? _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.crop?.name);
    _variety = TextEditingController(text: widget.crop?.variety);
    _stage = TextEditingController(text: widget.crop?.stage);
    _date = widget.crop?.sownOn;
  }

  @override
  void dispose() {
    _name.dispose();
    _variety.dispose();
    _stage.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final controller = context.read<AppController>();
      if (widget.crop == null) {
        await controller.addCrop(
          plotId: widget.plot.id,
          name: _name.text,
          stage: _stage.text,
          variety: _variety.text,
          sowingOrTransplantDate: _date,
        );
      } else {
        await controller.editCrop(
          plotId: widget.plot.id,
          crop: widget.crop!,
          name: _name.text,
          variety: _variety.text,
          sowingOrTransplantDate: _date,
        );
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.crop == null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(creating ? 'addCropCycle' : 'editCropDetails'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: context.tr('crop')),
                textCapitalization: TextCapitalization.words,
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Enter the crop name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _variety,
                decoration: InputDecoration(
                  labelText: context.tr('varietyOptional'),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              if (creating) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _stage,
                  decoration: InputDecoration(
                    labelText: context.tr('cropStage'),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? 'Enter the current crop stage'
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.calendarDays),
                title: Text(context.tr('sowingOrTransplantDate')),
                subtitle: Text(
                  _date == null
                      ? 'Optional'
                      : context.strings.formatDate(_date!),
                ),
                trailing: _date == null
                    ? const Icon(LucideIcons.chevronRight)
                    : IconButton(
                        tooltip: context.tr('removeDate'),
                        onPressed: () => setState(() => _date = null),
                        icon: const Icon(LucideIcons.x, size: 18),
                      ),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    initialDate: _date ?? DateTime.now(),
                  );
                  if (selected != null) setState(() => _date = selected);
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving...' : context.tr('save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddFarmScreen extends StatefulWidget {
  const AddFarmScreen({super.key});

  @override
  State<AddFarmScreen> createState() => _AddFarmScreenState();
}

class _AddFarmScreenState extends State<AddFarmScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('addFarm'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 600,
          child: Form(
            key: _key,
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              children: [
                Text(
                  'Create a simple farm record',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Plots, crops, activities and diagnoses can be linked after the farm is saved.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.mutedInk),
                ),
                const SizedBox(height: 26),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.tr('farmName'),
                    prefixIcon: const Icon(LucideIcons.sprout),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Farm name is required.'
                      : null,
                ),
                const SizedBox(height: 14),
                InlineNotice(
                  title: context.tr('startWithFarmName'),
                  message: context.tr('startWithFarmNameBody'),
                  icon: LucideIcons.sprout,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: context.watch<AppController>().busy
                      ? null
                      : () async {
                          if (!_key.currentState!.validate()) return;
                          try {
                            final farm = await context
                                .read<AppController>()
                                .addFarm(name: _name.text);
                            if (context.mounted) {
                              context.pushReplacement('/farm/${farm.id}');
                            }
                          } on ApiException catch (error) {
                            if (context.mounted) {
                              showAppSnackBar(
                                context,
                                context.localizedError(error),
                              );
                            }
                          }
                        },
                  child: context.watch<AppController>().busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditFarmScreen extends StatefulWidget {
  const EditFarmScreen({super.key, required this.farmId});

  final String farmId;

  @override
  State<EditFarmScreen> createState() => _EditFarmScreenState();
}

class _EditFarmScreenState extends State<EditFarmScreen> {
  final _key = GlobalKey<FormState>();
  late final FarmModel? _farm;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _farm = context.read<AppController>().farmById(widget.farmId);
    _name = TextEditingController(text: _farm?.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_farm == null) {
      return Scaffold(
        body: SafeArea(
          child: AppStateView(
            kind: AppStateKind.error,
            title: context.tr('farmNotFound'),
            message: context.tr('farmRemovedBody'),
          ),
        ),
      );
    }
    final busy = context.watch<AppController>().busy;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('editFarm'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 600,
          child: Form(
            key: _key,
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              children: [
                Text(
                  'Farm name',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Plot locations and weather remain unchanged when you rename a farm.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.mutedInk),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.tr('farmName'),
                    prefixIcon: const Icon(LucideIcons.sprout),
                  ),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? 'Farm name is required.'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : _save,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('saveChanges')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    try {
      await context.read<AppController>().updateFarm(
        farmId: widget.farmId,
        name: _name.text,
      );
      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }
}

class AddPlotScreen extends StatefulWidget {
  const AddPlotScreen({super.key, required this.farmId});
  final String farmId;

  @override
  State<AddPlotScreen> createState() => _AddPlotScreenState();
}

class _AddPlotScreenState extends State<AddPlotScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _crop = TextEditingController();
  final _variety = TextEditingController();
  final _soil = TextEditingController();
  final _irrigation = TextEditingController();
  LocationPoint? _confirmedLocation;
  String _stage = 'Sowing';
  String _areaUnit = 'acre';
  bool _loadedPreferredAreaUnit = false;
  DateTime? _sowingOrTransplantDate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedPreferredAreaUnit) return;
    _areaUnit = context.read<AppController>().preferredAreaUnit;
    _loadedPreferredAreaUnit = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _crop.dispose();
    _variety.dispose();
    _soil.dispose();
    _irrigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('addPlot'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 720,
          child: Form(
            key: _key,
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              children: [
                Text(
                  'Create a plot workspace',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'A plot keeps its own crops, map-based weather, scans, chats and history.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.mutedInk),
                ),
                const SizedBox(height: 24),
                _FormSectionLabel(
                  number: '1',
                  title: context.tr('plotAndMapLocation'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: context.tr('plotName'),
                    prefixIcon: const Icon(LucideIcons.map),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Plot name is required.'
                      : null,
                ),
                const SizedBox(height: 16),
                _PlotLocationPicker(
                  onConfirmed: (location) =>
                      setState(() => _confirmedLocation = location),
                ),
                const SizedBox(height: 28),
                _FormSectionLabel(number: '2', title: context.tr('firstCrop')),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _crop,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.tr('crop'),
                    prefixIcon: const Icon(LucideIcons.wheat),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'At least one crop is required.'
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _stage,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('cropStage'),
                    prefixIcon: const Icon(LucideIcons.sprout),
                  ),
                  items:
                      const [
                            'Sowing',
                            'Seedling',
                            'Vegetative',
                            'Flowering',
                            'Fruiting',
                            'Maturity',
                          ]
                          .map(
                            (stage) => DropdownMenuItem(
                              value: stage,
                              child: Text(stage),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _stage = value);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _variety,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.tr('varietyOptional'),
                    prefixIcon: const Icon(LucideIcons.tag),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _pickCropDate,
                  icon: const Icon(LucideIcons.calendarDays),
                  label: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _sowingOrTransplantDate == null
                          ? 'Sowing or transplant date (optional)'
                          : context.strings.formatDate(
                              _sowingOrTransplantDate!,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _FormSectionLabel(
                  number: '3',
                  title: context.tr('fieldDetailsOptional'),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackFields =
                        constraints.maxWidth < 460 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3;
                    final areaField = TextFormField(
                      controller: _area,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.tr('area'),
                        prefixIcon: const Icon(LucideIcons.ruler),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final area = double.tryParse(value.trim());
                        return area == null || area <= 0
                            ? 'Enter a positive area.'
                            : null;
                      },
                    );
                    final unitField = DropdownButtonFormField<String>(
                      initialValue: _areaUnit,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.tr('unit'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'acre',
                          child: Text(context.tr('acre')),
                        ),
                        DropdownMenuItem(
                          value: 'hectare',
                          child: Text(context.tr('hectare')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _areaUnit = value);
                        }
                      },
                    );
                    if (stackFields) {
                      return Column(
                        children: [
                          areaField,
                          const SizedBox(height: 14),
                          unitField,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: areaField),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: unitField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _soil,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: context.tr('soilNotesOptional'),
                    prefixIcon: const Icon(LucideIcons.layers3),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _irrigation,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: context.tr('irrigationDetailsOptional'),
                    prefixIcon: const Icon(LucideIcons.droplets),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: context.watch<AppController>().busy
                      ? null
                      : () async {
                          if (!_key.currentState!.validate()) return;
                          if (_confirmedLocation == null) {
                            showAppSnackBar(
                              context,
                              'Confirm the plot pointer on the map before saving.',
                            );
                            return;
                          }
                          try {
                            final plot = await context
                                .read<AppController>()
                                .addPlot(
                                  farmId: widget.farmId,
                                  name: _name.text,
                                  location: _confirmedLocation!,
                                  cropName: _crop.text,
                                  cropStage: _stage,
                                  cropVariety: _variety.text,
                                  sowingOrTransplantDate:
                                      _sowingOrTransplantDate,
                                  area: _area.text.trim().isEmpty
                                      ? null
                                      : double.parse(_area.text.trim()),
                                  areaUnit: _area.text.trim().isEmpty
                                      ? null
                                      : _areaUnit,
                                  soilNotes: _soil.text,
                                  irrigationDetails: _irrigation.text,
                                );
                            if (context.mounted) {
                              context.pushReplacement('/plot/${plot.id}');
                            }
                          } on ApiException catch (error) {
                            if (context.mounted) {
                              showAppSnackBar(
                                context,
                                context.localizedError(error),
                              );
                            }
                          }
                        },
                  child: context.watch<AppController>().busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCropDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _sowingOrTransplantDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now(),
      helpText: 'Sowing or transplant date',
    );
    if (selected != null) {
      setState(() => _sowingOrTransplantDate = selected);
    }
  }
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.forest,
          foregroundColor: Colors.white,
          child: Text(number, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            softWrap: true,
          ),
        ),
      ],
    );
  }
}

class _PlotLocationPicker extends StatefulWidget {
  const _PlotLocationPicker({required this.onConfirmed, this.initialLocation});

  final ValueChanged<LocationPoint?> onConfirmed;
  final LocationPoint? initialLocation;

  @override
  State<_PlotLocationPicker> createState() => _PlotLocationPickerState();
}

class _PlotLocationPickerState extends State<_PlotLocationPicker> {
  final _query = TextEditingController();
  final _mapController = MapController();
  List<LocationPoint> _results = const [];
  LocationPoint? _selected;
  bool _confirmed = false;
  bool _busy = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialLocation;
    _confirmed = widget.initialLocation != null;
  }

  @override
  void dispose() {
    _query.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) return;
    setState(() {
      _busy = true;
      _searched = false;
      _results = const [];
    });
    try {
      final results = await context.read<AppController>().searchLocations(
        query,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _searched = true;
        });
      }
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _busy = true);
    try {
      final point = await context.read<AppController>().currentDeviceLocation();
      if (!mounted) return;
      _select(point);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(LocationPoint point) {
    setState(() {
      _selected = point;
      _confirmed = false;
      _results = const [];
      _searched = false;
    });
    widget.onConfirmed(null);
    _mapController.move(LatLng(point.latitude, point.longitude), 15);
  }

  void _placePointer(LatLng point) {
    _select(
      LocationPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        label: _selected?.label ?? 'Map pointer',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('plot-location-search'),
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: context.tr('searchLocationHint'),
            prefixIcon: const Icon(LucideIcons.search),
            suffixIcon: IconButton(
              tooltip: context.tr('searchLocation'),
              onPressed: _busy ? null : _search,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.arrowRight),
            ),
          ),
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: _results
                  .map(
                    (point) => ListTile(
                      leading: const Icon(LucideIcons.mapPin),
                      title: Text(point.displayLabel),
                      subtitle: point.country == null
                          ? null
                          : Text(point.country!),
                      onTap: () => _select(point),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (_searched && _results.isEmpty) ...[
          const SizedBox(height: 8),
          InlineNotice(
            key: const ValueKey('plot-location-empty'),
            title: context.tr('searchLocation'),
            message: context.tr('choosePlotLocationBody'),
            icon: LucideIcons.mapPinOff,
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _useCurrentLocation,
            icon: const Icon(LucideIcons.locateFixed),
            label: Text(context.tr('useCurrentDeviceLocation')),
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: SizedBox(
            height: 260,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: selected == null
                    ? const LatLng(20.5937, 78.9629)
                    : LatLng(selected.latitude, selected.longitude),
                initialZoom: selected == null ? 4.5 : 15,
                onTap: (_, point) => _placePointer(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: context
                      .read<AppController>()
                      .config
                      .mapTileUrlTemplate,
                  userAgentPackageName: 'com.krishisathi.mobile',
                  maxZoom: 19,
                ),
                if (selected != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(selected.latitude, selected.longitude),
                        width: 52,
                        height: 52,
                        child: const Icon(
                          LucideIcons.mapPin,
                          color: AppColors.forest,
                          size: 42,
                        ),
                      ),
                    ],
                  ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (selected == null)
          InlineNotice(
            title: context.tr('choosePlotLocation'),
            message: context.tr('choosePlotLocationBody'),
            icon: LucideIcons.mapPinned,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final stackAction =
                  constraints.maxWidth < 440 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final notice = InlineNotice(
                title: context.tr(
                  _confirmed ? 'mapPointerConfirmed' : 'confirmPointer',
                ),
                message:
                    '${selected.displayLabel}\n${selected.latitude.toStringAsFixed(5)}, ${selected.longitude.toStringAsFixed(5)}',
                icon: _confirmed ? LucideIcons.circleCheck : LucideIcons.mapPin,
                color: _confirmed ? AppColors.leaf : AppColors.amber,
              );
              final action = FilledButton.icon(
                onPressed: _confirmed
                    ? null
                    : () {
                        setState(() => _confirmed = true);
                        widget.onConfirmed(selected);
                      },
                icon: Icon(
                  _confirmed ? LucideIcons.circleCheck : LucideIcons.mapPin,
                ),
                label: Text(
                  context.tr(_confirmed ? 'confirmed' : 'confirmPointer'),
                ),
              );
              if (stackAction) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [notice, const SizedBox(height: 10), action],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: notice),
                  const SizedBox(width: 10),
                  action,
                ],
              );
            },
          ),
      ],
    );
  }
}

class EditPlotScreen extends StatefulWidget {
  const EditPlotScreen({super.key, required this.plotId});

  final String plotId;

  @override
  State<EditPlotScreen> createState() => _EditPlotScreenState();
}

class _EditPlotScreenState extends State<EditPlotScreen> {
  final _key = GlobalKey<FormState>();
  late final PlotModel? _plot;
  late final TextEditingController _name;
  late final TextEditingController _area;
  late final TextEditingController _soil;
  late final TextEditingController _irrigation;
  late String _areaUnit;
  LocationPoint? _confirmedLocation;

  @override
  void initState() {
    super.initState();
    _plot = context.read<AppController>().plotById(widget.plotId);
    _name = TextEditingController(text: _plot?.name);
    _area = TextEditingController(text: _plot?.area?.toString() ?? '');
    _soil = TextEditingController(text: _plot?.soilType ?? '');
    _irrigation = TextEditingController(text: _plot?.irrigation ?? '');
    _areaUnit = _plot?.areaUnit ?? 'acre';
    if (_plot case final plot?) {
      _confirmedLocation = LocationPoint(
        latitude: plot.latitude,
        longitude: plot.longitude,
        label: plot.locationLabel,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _soil.dispose();
    _irrigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plot = _plot;
    if (plot == null) {
      return Scaffold(
        body: SafeArea(
          child: AppStateView(
            kind: AppStateKind.error,
            title: context.tr('plotNotFound'),
            message: context.tr('plotRemovedBody'),
          ),
        ),
      );
    }
    final busy = context.watch<AppController>().busy;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('editPlot'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 720,
          child: Form(
            key: _key,
            child: ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 32),
              children: [
                Text(
                  'Plot details and weather location',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Moving the pointer changes the location used for this plot’s weather and Saathi context.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.mutedInk),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.tr('plotName'),
                    prefixIcon: const Icon(LucideIcons.map),
                  ),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? 'Plot name is required.'
                      : null,
                ),
                const SizedBox(height: 16),
                _PlotLocationPicker(
                  initialLocation: _confirmedLocation,
                  onConfirmed: (location) =>
                      setState(() => _confirmedLocation = location),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackFields =
                        constraints.maxWidth < 460 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3;
                    final areaField = TextFormField(
                      controller: _area,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.tr('areaOptional'),
                        prefixIcon: const Icon(LucideIcons.ruler),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final parsed = double.tryParse(value.trim());
                        return parsed == null || parsed <= 0
                            ? 'Enter a positive area.'
                            : null;
                      },
                    );
                    final unitField = DropdownButtonFormField<String>(
                      initialValue: _areaUnit,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.tr('unit'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'acre',
                          child: Text(context.tr('acre')),
                        ),
                        DropdownMenuItem(
                          value: 'hectare',
                          child: Text(context.tr('hectare')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _areaUnit = value);
                      },
                    );
                    if (stackFields) {
                      return Column(
                        children: [
                          areaField,
                          const SizedBox(height: 14),
                          unitField,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: areaField),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: unitField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _soil,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: context.tr('soilNotesOptional'),
                    prefixIcon: const Icon(LucideIcons.layers3),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _irrigation,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: context.tr('irrigationDetailsOptional'),
                    prefixIcon: const Icon(LucideIcons.droplets),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: busy ? null : _save,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('saveChanges')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final location = _confirmedLocation;
    if (location == null) {
      showAppSnackBar(context, context.tr('confirmPlotPointerFirst'));
      return;
    }
    try {
      await context.read<AppController>().updatePlot(
        plotId: widget.plotId,
        name: _name.text,
        location: location,
        area: _area.text.trim().isEmpty
            ? null
            : double.parse(_area.text.trim()),
        areaUnit: _area.text.trim().isEmpty ? null : _areaUnit,
        soilNotes: _soil.text,
        irrigationDetails: _irrigation.text,
      );
      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }
}

class AddActivityScreen extends StatefulWidget {
  const AddActivityScreen({super.key, required this.plotId});
  final String plotId;

  @override
  State<AddActivityScreen> createState() => _AddActivityScreenState();
}

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({
    super.key,
    required this.plotId,
    required this.activityId,
  });

  final String plotId;
  final String activityId;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  final _picker = ImagePicker();
  FarmActivity? _activity;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _activity = await context.read<AppController>().loadActivity(
        plotId: widget.plotId,
        activityId: widget.activityId,
      );
    } on ApiException catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPhotos() async {
    final selected = await _picker.pickMultiImage(
      imageQuality: 90,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (!mounted || selected.isEmpty || _activity == null) return;
    var activity = _activity!;
    try {
      for (final image in selected) {
        activity = await context.read<AppController>().addActivityPhoto(
          plotId: widget.plotId,
          activity: activity,
          imagePath: image.path,
        );
      }
      if (mounted) {
        setState(() => _activity = activity);
        showAppSnackBar(context, context.tr('fieldPhotosAdded'), success: true);
      }
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  Future<void> _deletePhoto(ActivityPhotoModel photo) async {
    final activity = _activity;
    if (activity == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('removePhotoQuestion')),
        content: Text(context.tr('removeActivityPhotoBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('removePhoto')),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    try {
      await context.read<AppController>().deleteActivityPhoto(
        plotId: widget.plotId,
        activity: activity,
        photoId: photo.id,
      );
      if (mounted) {
        setState(
          () => _activity = activity.copyWith(
            photos: activity.photos
                .where((item) => item.id != photo.id)
                .toList(growable: false),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  Future<void> _edit() async {
    final activity = _activity;
    if (activity == null) return;
    final title = TextEditingController(text: activity.title);
    final notes = TextEditingController(text: activity.notes);
    var occurredAt = activity.occurredAt.toLocal();
    final result = await showModalBottomSheet<(String, String, DateTime)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit field activity',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: title,
                    maxLength: 150,
                    decoration: InputDecoration(
                      labelText: context.tr('activityTitle'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: context.tr('notes'),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.calendarClock),
                    title: Text(context.tr('activityDateTime')),
                    subtitle: Text(context.strings.formatDateTime(occurredAt)),
                    trailing: const Icon(LucideIcons.chevronRight),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: occurredAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (date == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(occurredAt),
                      );
                      if (time == null) return;
                      setSheetState(
                        () => occurredAt = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      final normalized = title.text.trim();
                      if (normalized.isEmpty) return;
                      Navigator.pop(context, (
                        normalized,
                        notes.text.trim(),
                        occurredAt,
                      ));
                    },
                    child: Text(context.tr('save')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    title.dispose();
    notes.dispose();
    if (result == null || !mounted) return;
    try {
      final updated = await context.read<AppController>().updateActivity(
        plotId: widget.plotId,
        activity: activity,
        title: result.$1,
        notes: result.$2,
        occurredAt: result.$3,
      );
      if (mounted) setState(() => _activity = updated);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  Future<void> _delete() async {
    final activity = _activity;
    if (activity == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('deleteActivityQuestion')),
        content: Text(context.tr('deleteActivityBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    try {
      await context.read<AppController>().deleteActivity(
        plotId: widget.plotId,
        activityId: activity.id,
      );
      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = _activity;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('fieldActivity')),
        actions: [
          IconButton(
            tooltip: context.tr('edit'),
            onPressed: activity == null ? null : _edit,
            icon: const Icon(LucideIcons.pencil),
          ),
          IconButton(
            tooltip: context.tr('delete'),
            onPressed: activity == null ? null : _delete,
            icon: const Icon(LucideIcons.trash2),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? AppStateView(
                kind: AppStateKind.loading,
                title: context.tr('loadingActivity'),
                message: context.tr('loadingActivityBody'),
              )
            : _error != null
            ? AppStateView(
                kind: AppStateKind.error,
                title: context.tr('activityLoadFailed'),
                message: _error!.message,
                actionLabel: context.tr('retry'),
                onAction: _load,
              )
            : activity == null
            ? AppStateView(
                kind: AppStateKind.empty,
                title: context.tr('activityNotFound'),
                message: context.tr('recordRemovedBody'),
              )
            : AppContent(
                maxWidth: 760,
                child: ListView(
                  padding: const EdgeInsets.only(top: 10, bottom: 36),
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.leaf.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activity.title,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.strings.formatDateTime(
                                activity.occurredAt.toLocal(),
                              ),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.mutedInk),
                            ),
                            if (activity.notes?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 18),
                              Text(activity.notes!),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SectionHeader(
                      title: context.tr('fieldPhotos'),
                      subtitle: activity.photos.isEmpty
                          ? 'No photos are attached to this record.'
                          : '${activity.photos.length} attached',
                      action: TextButton.icon(
                        onPressed: _addPhotos,
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: Text(context.tr('add')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (activity.photos.isEmpty)
                      AppStateView(
                        kind: AppStateKind.empty,
                        title: context.tr('noFieldPhotos'),
                        message: context.tr('noFieldPhotosBody'),
                        compact: true,
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 600 ? 3 : 2;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: 1,
                                ),
                            itemCount: activity.photos.length,
                            itemBuilder: (context, index) => _ActivityPhotoTile(
                              activity: activity,
                              photo: activity.photos[index],
                              onDelete: _deletePhoto,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ActivityPhotoTile extends StatelessWidget {
  const _ActivityPhotoTile({
    required this.activity,
    required this.photo,
    required this.onDelete,
  });

  final FarmActivity activity;
  final ActivityPhotoModel photo;
  final Future<void> Function(ActivityPhotoModel) onDelete;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<List<int>>(
            future: context.read<AppController>().loadActivityPhoto(
              activity.id,
              photo.id,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Image.memory(
                  Uint8List.fromList(snapshot.data!),
                  fit: BoxFit.cover,
                  semanticLabel: context.tr('fieldActivityPhoto'),
                );
              }
              if (snapshot.hasError) {
                return const ColoredBox(
                  color: AppColors.divider,
                  child: Icon(LucideIcons.imageOff),
                );
              }
              return const ColoredBox(
                color: AppColors.divider,
                child: Center(child: CircularProgressIndicator()),
              );
            },
          ),
          PositionedDirectional(
            top: 6,
            end: 6,
            child: IconButton.filled(
              tooltip: context.tr('removePhoto'),
              onPressed: () => onDelete(photo),
              icon: const Icon(LucideIcons.trash2, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddActivityScreenState extends State<AddActivityScreen> {
  final _notes = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  String _type = 'Irrigation';
  String? _cropId;
  DateTime _occurredAt = DateTime.now();
  bool _saving = false;

  Future<void> _takePhoto() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (image != null && mounted) setState(() => _images.add(image));
  }

  Future<void> _choosePhotos() async {
    final images = await _picker.pickMultiImage(
      imageQuality: 90,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (images.isNotEmpty && mounted) setState(() => _images.addAll(images));
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plot = context.watch<AppController>().plotById(widget.plotId);
    final crops =
        plot?.crops.where((crop) => crop.isActive).toList() ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('addActivity'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 600,
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 32),
            children: [
              Text(
                context.tr('activityType'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                          'Irrigation',
                          'Nutrition',
                          'Spraying',
                          'Weeding',
                          'Harvest',
                          'Observation',
                        ]
                        .map(
                          (type) => ChoiceChip(
                            label: Text(type),
                            selected: _type == type,
                            onSelected: (_) => setState(() => _type = type),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String?>(
                initialValue: _cropId,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('crop')),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.tr('wholePlotNoCrop')),
                  ),
                  ...crops.map(
                    (crop) => DropdownMenuItem<String?>(
                      value: crop.id,
                      child: Text(crop.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _cropId = value),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.calendarClock),
                title: Text(context.tr('activityDateTime')),
                subtitle: Text(context.strings.formatDateTime(_occurredAt)),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _pickOccurredAt,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('notes'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Field photos (optional)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _takePhoto,
                      icon: const Icon(LucideIcons.camera, size: 18),
                      label: Text(context.tr('takePhoto')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _choosePhotos,
                      icon: const Icon(LucideIcons.images, size: 18),
                      label: Text(context.tr('choosePhotos')),
                    ),
                  ),
                ],
              ),
              if (_images.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          child: Image.file(
                            File(_images[index].path),
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                          ),
                        ),
                        PositionedDirectional(
                          top: 4,
                          end: 4,
                          child: IconButton.filled(
                            visualDensity: VisualDensity.compact,
                            tooltip: context.tr('removePhoto'),
                            onPressed: () =>
                                setState(() => _images.removeAt(index)),
                            icon: const Icon(LucideIcons.x, size: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        try {
                          final result = await context
                              .read<AppController>()
                              .addActivity(
                                plotId: widget.plotId,
                                type: _type,
                                notes: _notes.text,
                                occurredAt: _occurredAt,
                                cropId: _cropId,
                                imagePaths: _images
                                    .map((image) => image.path)
                                    .toList(),
                              );
                          if (!context.mounted) return;
                          context.pop();
                          if (result.failedPhotoCount > 0) {
                            showAppSnackBar(
                              context,
                              'Activity saved. ${result.failedPhotoCount} photo${result.failedPhotoCount == 1 ? '' : 's'} could not be uploaded; open the activity to retry.',
                            );
                          }
                        } on ApiException catch (error) {
                          if (context.mounted) {
                            showAppSnackBar(
                              context,
                              context.localizedError(error),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                child: Text(_saving ? 'Saving activity…' : context.tr('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickOccurredAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null || !mounted) return;
    setState(
      () => _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.mutedInk),
      const SizedBox(width: 5),
      Text(text, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _ImageFact extends StatelessWidget {
  const _ImageFact({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: Colors.white),
      const SizedBox(width: 6),
      Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Colors.white),
      ),
    ],
  );
}
