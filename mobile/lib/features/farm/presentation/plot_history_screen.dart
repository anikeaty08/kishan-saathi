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

class PlotHistoryScreen extends StatefulWidget {
  const PlotHistoryScreen({super.key, required this.plotId});

  final String plotId;

  @override
  State<PlotHistoryScreen> createState() => _PlotHistoryScreenState();
}

class _PlotHistoryScreenState extends State<PlotHistoryScreen> {
  static const _pageSize = 30;
  final _categories = <String>{};
  final _items = <TimelineEventModel>[];
  String? _cropId;
  DateTimeRange? _dates;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = await context.read<AppController>().fetchPlotTimeline(
        widget.plotId,
        cropId: _cropId,
        categories: _categories,
        dateFrom: _dates?.start,
        dateTo: _dates == null
            ? null
            : DateTime(
                _dates!.end.year,
                _dates!.end.month,
                _dates!.end.day,
                23,
                59,
                59,
                999,
              ),
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _hasMore = page.hasMore;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plot = context.watch<AppController>().plotById(widget.plotId);
    if (plot == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const AppStateView(
          kind: AppStateKind.error,
          title: 'Plot not found',
          message: 'This plot may have been removed.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('${plot.name} history')),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 900,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 14),
                  child: _FilterPanel(
                    plot: plot,
                    selectedCategories: _categories,
                    cropId: _cropId,
                    dates: _dates,
                    onCategoryChanged: (category, selected) {
                      setState(() {
                        selected
                            ? _categories.add(category)
                            : _categories.remove(category);
                      });
                      _load(reset: true);
                    },
                    onCropChanged: (value) {
                      setState(() => _cropId = value);
                      _load(reset: true);
                    },
                    onChooseDates: _chooseDates,
                    onClear: () {
                      setState(() {
                        _categories.clear();
                        _cropId = null;
                        _dates = null;
                      });
                      _load(reset: true);
                    },
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppStateView(
                    kind: AppStateKind.loading,
                    title: 'Loading plot history',
                    message: 'Combining leaf checks, chats and field records.',
                  ),
                )
              else if (_error != null && _items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppStateView(
                    kind: AppStateKind.error,
                    title: 'History could not be loaded',
                    message: _error!.message,
                    actionLabel: context.tr('retry'),
                    onAction: () => _load(reset: true),
                  ),
                )
              else if (_items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppStateView(
                    kind: AppStateKind.empty,
                    title: 'No matching history',
                    message: 'Try clearing a filter, or add a leaf check, conversation, reminder or field activity.',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _items.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: _loadingMore
                                ? null
                                : () => _load(reset: false),
                            icon: _loadingMore
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.chevronsDown),
                            label: Text(
                              _loadingMore ? 'Loading…' : 'Load older records',
                            ),
                          ),
                        ),
                      );
                    }
                    return _HistoryEventTile(
                      event: _items[index],
                      plotId: plot.id,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseDates() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      initialDateRange: _dates,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (selected == null || !mounted) return;
    setState(() => _dates = selected);
    await _load(reset: true);
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.plot,
    required this.selectedCategories,
    required this.cropId,
    required this.dates,
    required this.onCategoryChanged,
    required this.onCropChanged,
    required this.onChooseDates,
    required this.onClear,
  });

  final PlotModel plot;
  final Set<String> selectedCategories;
  final String? cropId;
  final DateTimeRange? dates;
  final void Function(String category, bool selected) onCategoryChanged;
  final ValueChanged<String?> onCropChanged;
  final VoidCallback onChooseDates;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    const categories = <(String, String, IconData)>[
      ('diagnosis', 'Leaf checks', LucideIcons.scanLine),
      ('chat', 'Chats', LucideIcons.messagesSquare),
      ('reminder', 'Reminders', LucideIcons.bell),
      ('activity', 'Activities', LucideIcons.clipboardCheck),
      ('crop_stage', 'Crop stages', LucideIcons.sprout),
      ('crop_cycle', 'Crop cycles', LucideIcons.refreshCw),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter history',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (selectedCategories.isNotEmpty ||
                    cropId != null ||
                    dates != null)
                  TextButton(onPressed: onClear, child: const Text('Clear')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: categories
                  .map(
                    (category) => FilterChip(
                      avatar: Icon(category.$3, size: 15),
                      label: Text(category.$2),
                      selected: selectedCategories.contains(category.$1),
                      onSelected: (selected) =>
                          onCategoryChanged(category.$1, selected),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final crop = DropdownButtonFormField<String?>(
                  initialValue: cropId,
                  decoration: const InputDecoration(
                    labelText: 'Crop',
                    prefixIcon: Icon(LucideIcons.wheat),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All crops'),
                    ),
                    ...plot.crops.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item.id,
                        child: Text(
                          item.isActive ? item.name : '${item.name} (closed)',
                        ),
                      ),
                    ),
                  ],
                  onChanged: onCropChanged,
                );
                final date = OutlinedButton.icon(
                  onPressed: onChooseDates,
                  icon: const Icon(LucideIcons.calendarRange),
                  label: Text(
                    dates == null
                        ? 'Any date'
                        : '${context.strings.formatShortDate(dates!.start)} – ${context.strings.formatShortDate(dates!.end)}',
                  ),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [crop, const SizedBox(height: 10), date],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: crop),
                    const SizedBox(width: 12),
                    Expanded(child: date),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEventTile extends StatelessWidget {
  const _HistoryEventTile({required this.event, required this.plotId});

  final TimelineEventModel event;
  final String plotId;

  @override
  Widget build(BuildContext context) {
    final route = switch (event.category) {
      'activity' => '/plot/$plotId/activity/${event.referenceId}',
      'diagnosis' => '/scan/result/${event.referenceId}',
      'chat' => '/saathi/chat/${event.referenceId}',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            onTap: route == null ? null : () => context.push(route),
            leading: CircleAvatar(
              backgroundColor: _categoryColor(event.category)
                  .withValues(alpha: 0.12),
              child: Icon(
                _categoryIcon(event.category),
                color: _categoryColor(event.category),
                size: 19,
              ),
            ),
            title: Text(event.title),
            subtitle: Text(
              context.strings.formatDateTime(event.occurredAt.toLocal()),
            ),
            trailing: route == null
                ? null
                : const Icon(LucideIcons.chevronRight, size: 18),
          ),
        ),
      ),
    );
  }
}

IconData _categoryIcon(String category) => switch (category) {
  'diagnosis' => LucideIcons.scanLine,
  'chat' => LucideIcons.messagesSquare,
  'reminder' => LucideIcons.bell,
  'crop_stage' || 'crop_cycle' => LucideIcons.sprout,
  _ => LucideIcons.clipboardCheck,
};

Color _categoryColor(String category) => switch (category) {
  'diagnosis' => AppColors.amber,
  'chat' => AppColors.sky,
  'reminder' => AppColors.soil,
  _ => AppColors.leaf,
};
