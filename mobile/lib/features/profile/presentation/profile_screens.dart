import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_language.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../shared/presentation/app_controller.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 700,
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      child: Image.asset(
                        'assets/images/farmer_portrait.jpg',
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.farmerName,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            controller.isAuthenticated
                                ? 'Private farmer account'
                                : context.tr('demoMode'),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.mutedInk),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: context.tr('edit'),
                      onPressed: () => _editName(context, controller),
                      icon: const Icon(LucideIcons.pencil, size: 19),
                    ),
                  ],
                ),
              ),
              if (controller.previewMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: InlineNotice(
                    title: context.tr('demoMode'),
                    message: context.tr('demoModeBody'),
                    icon: LucideIcons.flaskConical,
                    color: AppColors.amber,
                  ),
                ),
              _SettingsSection(
                title: 'Preferences',
                children: [
                  _SettingsTile(
                    icon: LucideIcons.languages,
                    title: context.tr('language'),
                    subtitle: controller.selectedLanguage.nativeName,
                    onTap: () => context.push('/settings/language'),
                  ),
                  _SettingsTile(
                    icon: LucideIcons.bell,
                    title: context.tr('notifications'),
                    subtitle: controller.notificationsEnabled
                        ? 'Enabled'
                        : 'Disabled',
                    onTap: () => context.push('/settings/notifications'),
                  ),
                  _SettingsTile(
                    icon: LucideIcons.sunMoon,
                    title: context.tr('appearance'),
                    subtitle: switch (controller.themeMode) {
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                      _ => context.tr('systemTheme'),
                    },
                    onTap: () => _showThemeSheet(context, controller),
                  ),
                  _SettingsTile(
                    icon: LucideIcons.ruler,
                    title: 'Area measurements',
                    subtitle: controller.preferredAreaUnit == 'hectare'
                        ? 'Hectares'
                        : 'Acres',
                    onTap: () => _showAreaUnitSheet(context, controller),
                  ),
                ],
              ),
              _SettingsSection(
                title: 'Data and trust',
                children: [
                  _SettingsTile(
                    icon: LucideIcons.shieldCheck,
                    title: context.tr('privacy'),
                    subtitle: 'Sharing, reports and pending deletion',
                    onTap: () => context.push('/settings/privacy'),
                  ),
                  _SettingsTile(
                    icon: LucideIcons.brain,
                    title: context.tr('memory'),
                    subtitle: '${controller.memories.length} saved facts',
                    onTap: () => context.push('/settings/memory'),
                  ),
                ],
              ),
              _SettingsSection(
                title: 'Support',
                children: [
                  _SettingsTile(
                    icon: LucideIcons.circleHelp,
                    title: context.tr('help'),
                    subtitle: 'Guides, contact and troubleshooting',
                    onTap: () => context.push('/help'),
                  ),
                  _SettingsTile(
                    icon: LucideIcons.info,
                    title: context.tr('about'),
                    subtitle: 'Version 1.0.0',
                    onTap: () => context.push('/about'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: OutlinedButton.icon(
                  onPressed: () => _confirmSignOut(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  icon: const Icon(LucideIcons.logOut, size: 18),
                  label: Text(context.tr('signOut')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editName(BuildContext context, AppController controller) {
    final text = TextEditingController(text: controller.farmerName);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('yourName')),
        content: TextField(
          controller: text,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: context.tr('nameHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await controller.setFarmerName(text.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(context.tr('save')),
          ),
        ],
      ),
    ).whenComplete(text.dispose);
  }

  void _showThemeSheet(BuildContext context, AppController controller) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('appearance'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(LucideIcons.monitorSmartphone),
                    label: Text(context.tr('systemTheme')),
                  ),
                  const ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(LucideIcons.sun),
                    label: Text('Light'),
                  ),
                  const ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(LucideIcons.moon),
                    label: Text('Dark'),
                  ),
                ],
                selected: {controller.themeMode},
                onSelectionChanged: (value) {
                  controller.setThemeMode(value.first);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('signOut')),
        content: const Text(
          'You can sign in again to restore private server data. Local preview data will reset.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await context.read<AppController>().signOut();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) context.go('/welcome');
            },
            child: Text(context.tr('signOut')),
          ),
        ],
      ),
    );
  }

  void _showAreaUnitSheet(BuildContext context, AppController controller) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Area measurements',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Existing plot values are converted for display. New plot forms start with this unit.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'acre',
                    icon: Icon(LucideIcons.ruler),
                    label: Text('Acres'),
                  ),
                  ButtonSegment(
                    value: 'hectare',
                    icon: Icon(LucideIcons.map),
                    label: Text('Hectares'),
                  ),
                ],
                selected: {controller.preferredAreaUnit},
                onSelectionChanged: (value) async {
                  await controller.setPreferredAreaUnit(value.first);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.mutedInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
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
    return ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, color: AppColors.forest, size: 21),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(LucideIcons.chevronRight, size: 20),
      onTap: onTap,
    );
  }
}

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<AppController>().locale.languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('language'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 680,
          padding: EdgeInsets.zero,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
            itemCount: AppLanguage.supported.length,
            separatorBuilder: (_, _) => const Divider(indent: 64),
            itemBuilder: (context, index) {
              final language = AppLanguage.supported[index];
              final isSelected = selected == language.code;
              return ListTile(
                minTileHeight: 60,
                selected: isSelected,
                selectedTileColor: AppColors.leaf.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                leading: const Icon(
                  LucideIcons.languages,
                  color: AppColors.forest,
                ),
                title: Text(language.nativeName),
                subtitle: language.nativeName == language.englishName
                    ? null
                    : Text(language.englishName),
                trailing: isSelected
                    ? const Icon(LucideIcons.circleCheck, color: AppColors.leaf)
                    : null,
                onTap: () =>
                    context.read<AppController>().setLocale(language.code),
              );
            },
          ),
        ),
      ),
    );
  }
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notifications'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 680,
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Farm reminders'),
                subtitle: const Text(
                  'Accepted tasks, due times and recurring work',
                ),
                value: controller.notificationsEnabled,
                onChanged: controller.setNotifications,
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Weather alerts'),
                subtitle: const Text('Important rain, heat and wind changes'),
                value: controller.notificationsEnabled,
                onChanged: controller.setNotifications,
              ),
              const SizedBox(height: 18),
              const InlineNotice(
                title: 'Device permission matters',
                message: 'These preferences do not override notification permission in Android or iPhone Settings.',
                icon: LucideIcons.smartphone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final activeReports = controller.diagnosisReports
        .where((report) => report.isActive)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('privacy'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 36),
            children: [
              Text(
                'Your data stays under your control',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Farm records, images and conversations are private to your authenticated account. Sharing is explicit and temporary.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 24),
              const _PrivacyRow(
                icon: LucideIcons.image,
                title: 'Private images',
                body:
                    'Diagnosis and activity images require your access token.',
              ),
              const _PrivacyRow(
                icon: LucideIcons.link,
                title: 'Approved reports',
                body: 'You choose every field and image before a temporary link is created.',
              ),
              const _PrivacyRow(
                icon: LucideIcons.rotateCcwKey,
                title: 'Revocable access',
                body: 'Shared diagnosis reports can be revoked immediately.',
              ),
              const SizedBox(height: 26),
              SectionHeader(title: 'Active shared reports'),
              const SizedBox(height: 10),
              if (activeReports.isEmpty)
                const AppStateView(
                  kind: AppStateKind.empty,
                  title: 'No active links',
                  message: 'Reports you approve will appear here with their expiry and revoke action.',
                  compact: true,
                )
              else
                ...activeReports.map(
                  (report) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const Icon(
                        LucideIcons.fileCheck2,
                        color: AppColors.forest,
                      ),
                      title: Text(report.title),
                      subtitle: Text(
                        context.tr('date.expires', {
                          'date': context.strings.formatDateTime(
                            report.expiresAt.toLocal(),
                          ),
                        }),
                      ),
                      trailing: TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => _revoke(context, report.id),
                        child: const Text('Revoke'),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              SectionHeader(title: 'Pending deletion'),
              const SizedBox(height: 10),
              InlineNotice(
                title: 'Object cleanup is healthy',
                message: 'Private image cleanup is retried automatically. You can also request a retry now.',
                icon: LucideIcons.circleCheck,
                color: AppColors.leaf,
                action: TextButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => _retryCleanup(context),
                  icon: const Icon(LucideIcons.refreshCw, size: 17),
                  label: const Text('Retry pending deletion'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _revoke(BuildContext context, String reportId) async {
    try {
      await context.read<AppController>().revokeDiagnosisReport(reportId);
      if (context.mounted) {
        showAppSnackBar(context, 'Report access revoked.', success: true);
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }

  Future<void> _retryCleanup(BuildContext context) async {
    try {
      await context.read<AppController>().retryObjectDeletions();
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Pending image cleanup retried.',
          success: true,
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.leaf.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Icon(icon, color: AppColors.forest, size: 20),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedInk),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final memories = context.watch<AppController>().memories;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('memory'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              const InlineNotice(
                title: 'Only useful facts are saved',
                message: 'Saathi memory is evidence-based, scoped to a farm or plot, and can be removed at any time.',
                icon: LucideIcons.brain,
                color: AppColors.leaf,
              ),
              const SizedBox(height: 22),
              if (memories.isEmpty)
                const AppStateView(
                  kind: AppStateKind.empty,
                  title: 'No saved facts',
                  message: 'Facts accepted from future conversations will appear here.',
                )
              else
                ...memories.map(
                  (memory) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      minTileHeight: 72,
                      leading: const Icon(
                        LucideIcons.brain,
                        color: AppColors.forest,
                      ),
                      title: Text(memory.text),
                      subtitle: Text('${memory.scope} · ${memory.status}'),
                      trailing: IconButton(
                        tooltip: context.tr('delete'),
                        onPressed: () => _confirmDelete(context, memory),
                        icon: const Icon(LucideIcons.trash2, size: 20),
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

  void _confirmDelete(BuildContext context, MemoryFactModel memory) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this memory?'),
        content: Text(memory.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await context.read<AppController>().deleteMemory(memory.id);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } on ApiException catch (error) {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  showAppSnackBar(context, context.localizedError(error));
                }
              }
            },
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }
}

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final reminders = controller.reminders;
    final pending = reminders
        .where((item) => item.status == ReminderStatus.pending)
        .toList();
    final completed = reminders
        .where((item) => item.status != ReminderStatus.pending)
        .toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('reminders')),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
              Tab(text: 'Suggested'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => const _ManualReminderSheet(),
          ),
          icon: const Icon(LucideIcons.plus),
          label: const Text('Add reminder'),
        ),
        body: SafeArea(
          top: false,
          child: AppContent(
            maxWidth: 760,
            padding: EdgeInsets.zero,
            child: TabBarView(
              children: [
                _ReminderList(items: pending),
                _ReminderList(items: completed),
                _ProposalList(items: controller.reminderProposals),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderList extends StatelessWidget {
  const _ReminderList({required this.items});
  final List<FarmReminder> items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppStateView(
        kind: AppStateKind.empty,
        title: 'No reminders here',
        message: 'Accepted and manually created reminders appear in this list.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: ListTile(
            minTileHeight: 76,
            leading: Icon(
              item.status == ReminderStatus.done
                  ? LucideIcons.circleCheck
                  : LucideIcons.clock3,
              color: item.status == ReminderStatus.done
                  ? AppColors.leaf
                  : AppColors.amber,
            ),
            title: Text(item.title),
            subtitle: Text(
              '${item.plotName} · ${context.strings.formatDateTime(item.dueAt)}',
            ),
            trailing: item.status == ReminderStatus.pending
                ? PopupMenuButton<String>(
                    tooltip: 'Reminder actions',
                    onSelected: (action) => _act(context, item, action),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'done', child: Text('Mark done')),
                      PopupMenuItem(
                        value: 'skip',
                        child: Text('Skip this reminder'),
                      ),
                      PopupMenuItem(
                        value: 'reschedule',
                        child: Text('Reschedule'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text('Cancel reminder'),
                      ),
                    ],
                  )
                : Text(
                    item.status.name,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: AppColors.mutedInk),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _act(
    BuildContext context,
    FarmReminder reminder,
    String action,
  ) async {
    DateTime? dueAt;
    if (action == 'reschedule') {
      final initial = reminder.dueAt.isAfter(DateTime.now())
          ? reminder.dueAt.toLocal()
          : DateTime.now().add(const Duration(hours: 1));
      final date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (date == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (time == null) return;
      dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (!dueAt.isAfter(DateTime.now())) {
        if (context.mounted) {
          showAppSnackBar(context, 'Choose a future reminder time.');
        }
        return;
      }
    }
    if (!context.mounted) return;
    try {
      await context.read<AppController>().actOnReminder(
        reminder.id,
        action: action,
        dueAt: dueAt,
      );
      if (context.mounted) {
        showAppSnackBar(context, switch (action) {
          'done' => 'Reminder marked done.',
          'skip' => 'Reminder skipped.',
          'cancel' => 'Reminder cancelled.',
          _ => 'Reminder rescheduled.',
        }, success: true);
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }
}

class _ManualReminderSheet extends StatefulWidget {
  const _ManualReminderSheet();

  @override
  State<_ManualReminderSheet> createState() => _ManualReminderSheetState();
}

class _ManualReminderSheetState extends State<_ManualReminderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  DateTime _dueAt = DateTime.now().add(const Duration(hours: 1));
  String? _plotId;
  int? _recurrenceDays;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
    );
    if (time == null) return;
    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_dueAt.isAfter(DateTime.now())) {
      showAppSnackBar(context, 'Choose a future reminder time.');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppController>().createReminder(
        title: _title.text,
        dueAt: _dueAt,
        notes: _notes.text,
        plotId: _plotId,
        recurrenceDays: _recurrenceDays,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnackBar(context, 'Reminder scheduled.', success: true);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plots = context
        .watch<AppController>()
        .farms
        .expand((farm) => farm.plots)
        .toList();
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
                'Add reminder',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Task'),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Enter the task to remember'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _plotId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Plot (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('No plot')),
                  ...plots.map(
                    (plot) => DropdownMenuItem(
                      value: plot.id,
                      child: Text(plot.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _plotId = value),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.calendarClock),
                title: const Text('Date and time'),
                subtitle: Text(context.strings.formatDateTime(_dueAt)),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _pickDateTime,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: _recurrenceDays,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Does not repeat')),
                  DropdownMenuItem(value: 1, child: Text('Every day')),
                  DropdownMenuItem(value: 7, child: Text('Every week')),
                  DropdownMenuItem(value: 30, child: Text('Every 30 days')),
                ],
                onChanged: (value) => setState(() => _recurrenceDays = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Scheduling...' : 'Schedule reminder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProposalList extends StatelessWidget {
  const _ProposalList({required this.items});

  final List<ReminderProposalModel> items;

  @override
  Widget build(BuildContext context) {
    final pending = items.where((item) => item.status == 'pending').toList();
    if (pending.isEmpty) {
      return const AppStateView(
        kind: AppStateKind.empty,
        title: 'No suggestions waiting',
        message: 'Saathi can suggest a reminder, but it is scheduled only after you accept it.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      itemCount: pending.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final proposal = pending[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proposal.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  context.strings.formatDateTime(proposal.dueAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.mutedInk),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () =>
                          _decide(context, proposal.id, accepted: false),
                      child: const Text('Not now'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          _decide(context, proposal.id, accepted: true),
                      child: const Text('Schedule'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _decide(
    BuildContext context,
    String proposalId, {
    required bool accepted,
  }) async {
    try {
      await context.read<AppController>().decideReminderProposal(
        proposalId,
        accepted: accepted,
      );
      if (context.mounted) {
        showAppSnackBar(
          context,
          accepted ? 'Reminder scheduled.' : 'Suggestion declined.',
          success: true,
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
    }
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('help'))),
    body: SafeArea(
      top: false,
      child: AppContent(
        maxWidth: 700,
        child: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            const _HelpTile(
              icon: LucideIcons.scanLine,
              title: 'Taking a clear leaf photo',
              body: 'Use daylight, fill the frame and avoid wet leaves.',
            ),
            const _HelpTile(
              icon: LucideIcons.map,
              title: 'Setting up a farm and plot',
              body: 'A plot needs a location and at least one crop.',
            ),
            const _HelpTile(
              icon: LucideIcons.cloudOff,
              title: 'Using KrishiSathi offline',
              body: 'Farm records remain readable; scans can be held locally for later.',
            ),
            const _HelpTile(
              icon: LucideIcons.shieldCheck,
              title: 'Privacy and report sharing',
              body: 'Nothing is shared until you approve specific fields.',
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _showSupport(context),
              icon: const Icon(LucideIcons.mail),
              label: const Text('Contact support'),
            ),
          ],
        ),
      ),
    ),
  );

  void _showSupport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team Spidey',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(LucideIcons.mapPin),
                title: Text('Koramangala, Bengaluru'),
                subtitle: Text('Karnataka 560034, India'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.phone),
                title: const Text('7903422423'),
                subtitle: const Text('Support contact'),
                trailing: IconButton(
                  tooltip: 'Copy number',
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: '7903422423'),
                    );
                    if (context.mounted) {
                      showAppSnackBar(
                        context,
                        'Support number copied.',
                        success: true,
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.copy, size: 19),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  const _HelpTile({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: const EdgeInsets.symmetric(vertical: 4),
    childrenPadding: const EdgeInsetsDirectional.fromSTEB(56, 0, 12, 18),
    leading: Icon(icon, color: AppColors.forest),
    title: Text(title),
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.mutedInk),
        ),
      ),
    ],
  );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('about'))),
    body: SafeArea(
      top: false,
      child: AppContent(
        maxWidth: 620,
        child: ListView(
          padding: const EdgeInsets.only(top: 24),
          children: [
            const Center(child: BrandMark(size: 88)),
            const SizedBox(height: 24),
            Text(
              'Clear decisions for every field',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'KrishiSathi brings farm records, weather, leaf checks and scoped AI guidance into one privacy-conscious mobile app.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: AppColors.mutedInk),
            ),
            const SizedBox(height: 28),
            const Divider(),
            const ListTile(title: Text('Version'), trailing: Text('1.0.0 (1)')),
            const Divider(),
            const ListTile(
              title: Text('Application ID'),
              trailing: Text('com.krishisathi.mobile'),
            ),
          ],
        ),
      ),
    ),
  );
}
