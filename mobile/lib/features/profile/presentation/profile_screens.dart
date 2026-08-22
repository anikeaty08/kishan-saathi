import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_language.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/permissions/app_permission_service.dart';
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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Gradient header band
                  Container(
                    height: 110,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.forest,
                          Color(0xFF1E5038),
                          AppColors.leaf,
                        ],
                      ),
                    ),
                  ),
                  // Avatar + name row positioned overlapping the band
                  Positioned(
                    left: 20,
                    right: 20,
                    top: 56,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.forest.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: controller.hasFarmerName
                                ? InitialAvatar(
                                    name: controller.farmerName,
                                    size: 76,
                                    semanticLabel: controller.farmerName,
                                  )
                                : const SizedBox.square(
                                    dimension: 76,
                                    child: Center(
                                      child: BrandMark(
                                        size: 44,
                                        showName: false,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (controller.hasFarmerName) ...[
                                  Text(
                                    controller.farmerName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                ],
                                Text(
                                  controller.farmerEmail.isNotEmpty
                                      ? controller.farmerEmail
                                      : 'Private farmer account',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.75,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('edit'),
                          onPressed: () => _editName(context, controller),
                          icon: const Icon(
                            LucideIcons.pencil,
                            size: 19,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 158),
                ],
              ),
              const SizedBox(height: 50),
              _SettingsSection(
                title: context.tr('preferences'),
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
                    subtitle: context.tr('notificationPermissionBody'),
                    onTap: () => context.push('/settings/notifications'),
                  ),
                  _SettingsTile(
                    icon: LucideIcons.shieldCheck,
                    title: context.tr('permissionsTitle'),
                    subtitle: context.tr('devicePermissionMatters'),
                    onTap: () => context.push('/settings/permissions'),
                  ),

                  _SettingsTile(
                    icon: LucideIcons.sunMoon,
                    title: context.tr('appearance'),
                    subtitle: switch (controller.themeMode) {
                      ThemeMode.light => context.tr('lightTheme'),
                      ThemeMode.dark => context.tr('darkTheme'),
                      _ => context.tr('systemTheme'),
                    },
                    onTap: () => _showThemeSheet(context, controller),
                  ),
                  _SettingsTile(
                    icon: LucideIcons.ruler,
                    title: context.tr('areaMeasurements'),
                    subtitle: controller.preferredAreaUnit == 'hectare'
                        ? context.tr('hectares')
                        : context.tr('acres'),
                    onTap: () => _showAreaUnitSheet(context, controller),
                  ),
                ],
              ),
              _SettingsSection(
                title: context.tr('dataAndTrust'),
                children: [
                  _SettingsTile(
                    icon: LucideIcons.brain,
                    title: context.tr('memory'),
                    subtitle: context.tr('savedFactsCount', {
                      'count': controller.memories.length,
                    }),
                    onTap: () => context.push('/settings/memory'),
                  ),
                ],
              ),
              _SettingsSection(
                title: context.tr('support'),
                children: [
                  _SettingsTile(
                    icon: LucideIcons.circleHelp,
                    title: context.tr('help'),
                    subtitle: context.tr('supportBody'),
                    onTap: () => context.push('/help'),
                  ),
                  _SettingsTile(
                    icon: LucideIcons.info,
                    title: context.tr('about'),
                    subtitle: context.tr('versionValue', {'version': '1.0.1'}),
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
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          decoration: InputDecoration(labelText: context.tr('nameHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await controller.setFarmerName(text.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } on ApiException catch (error) {
                if (dialogContext.mounted) {
                  showAppSnackBar(
                    dialogContext,
                    dialogContext.localizedError(error),
                  );
                }
              }
            },
            child: Text(context.tr('save')),
          ),
        ],
      ),
    ).whenComplete(text.dispose);
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('signOut')),
        content: Text(context.tr('signOutBody')),
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
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(LucideIcons.sun),
                    label: Text(context.tr('lightTheme')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(LucideIcons.moon),
                    label: Text(context.tr('darkTheme')),
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
                context.tr('areaMeasurements'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('areaMeasurementsBody'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'acre',
                    icon: const Icon(LucideIcons.ruler),
                    label: Text(context.tr('acres')),
                  ),
                  ButtonSegment(
                    value: 'hectare',
                    icon: const Icon(LucideIcons.map),
                    label: Text(context.tr('hectares')),
                  ),
                ],
                selected: {controller.preferredAreaUnit},
                onSelectionChanged: (value) async {
                  try {
                    await controller.setPreferredAreaUnit(value.first);
                    if (context.mounted) Navigator.pop(context);
                  } on ApiException catch (error) {
                    if (context.mounted) {
                      showAppSnackBar(context, context.localizedError(error));
                    }
                  }
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
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.mutedInk,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i < children.length - 1)
                      const Divider(height: 1, indent: 56),
                  ],
                ],
              ),
            ),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: [
              Material(
                clipBehavior: Clip.antiAlias,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < AppLanguage.supported.length; i++) ...[
                      Builder(
                        builder: (context) {
                          final language = AppLanguage.supported[i];
                          final isSelected = selected == language.code;
                          return ListTile(
                            minTileHeight: 60,
                            selected: isSelected,
                            selectedTileColor: AppColors.leaf.withValues(
                              alpha: 0.08,
                            ),
                            leading: const Icon(
                              LucideIcons.languages,
                              color: AppColors.forest,
                            ),
                            title: Text(language.nativeName),
                            subtitle:
                                language.nativeName == language.englishName
                                ? null
                                : Text(language.englishName),
                            trailing: isSelected
                                ? const Icon(
                                    LucideIcons.circleCheck,
                                    color: AppColors.leaf,
                                  )
                                : null,
                            onTap: () async {
                              try {
                                await context.read<AppController>().setLocale(
                                  language.code,
                                );
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
                        },
                      ),
                      if (i < AppLanguage.supported.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ],
                ),
              ),
            ],
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
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      title: Text(context.tr('farmReminders')),
                      subtitle: Text(context.tr('farmRemindersBody')),
                      value: controller.farmReminderNotificationsEnabled,
                      onChanged: (value) async {
                        try {
                          final status = await controller
                              .setFarmReminderNotifications(value);
                          if (context.mounted && value && !status.isAllowed) {
                            showAppSnackBar(
                              context,
                              context.tr('error.permissionDenied'),
                            );
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
                    ),
                    const Divider(height: 1, indent: 16),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      title: Text(context.tr('weatherAlerts')),
                      subtitle: Text(context.tr('weatherAlertsBody')),
                      value: controller.weatherAlertNotificationsEnabled,
                      onChanged: (value) async {
                        try {
                          final status = await controller
                              .setWeatherAlertNotifications(value);
                          if (context.mounted && value && !status.isAllowed) {
                            showAppSnackBar(
                              context,
                              context.tr('error.permissionDenied'),
                            );
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              InlineNotice(
                title: context.tr('devicePermissionMatters'),
                message: context.tr('notificationPermissionBody'),
                icon: LucideIcons.smartphone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionSettingsScreen extends StatelessWidget {
  const PermissionSettingsScreen({super.key});

  Future<void> _handleResult(
    BuildContext context,
    AppPermissionState state,
  ) async {
    if (state.isAllowed || !context.mounted) return;
    if (!state.requiresSettings) {
      showAppSnackBar(context, context.tr('error.permissionDenied'));
      return;
    }
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('permissionBlocked')),
        content: Text(context.tr('permissionBlockedBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('notNow')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('openSettings')),
          ),
        ],
      ),
    );
    if ((shouldOpen ?? false) && context.mounted) {
      await context.read<AppController>().openAppPermissionSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('permissionsTitle'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 680,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: [
              Material(
                clipBehavior: Clip.antiAlias,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(LucideIcons.mapPin),
                      title: Text(context.tr('locationPermission')),
                      value: controller.locationEnabled,
                      onChanged: (value) async {
                        final state = await controller.setLocationEnabled(
                          value,
                        );
                        if (value && context.mounted) {
                          await _handleResult(context, state);
                        }
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(LucideIcons.bell),
                      title: Text(context.tr('notificationPermission')),
                      value: controller.notificationsEnabled,
                      onChanged: (value) async {
                        try {
                          final state = await controller.setNotifications(
                            value,
                          );
                          if (value && context.mounted) {
                            await _handleResult(context, state);
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
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(LucideIcons.camera),
                      title: Text(context.tr('cameraPermission')),
                      value: controller.cameraEnabled,
                      onChanged: (value) async {
                        final state = await controller.setCameraEnabled(value);
                        if (value && context.mounted) {
                          await _handleResult(context, state);
                        }
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(LucideIcons.mic),
                      title: Text(context.tr('voiceWithSaathi')),
                      subtitle: Text(
                        controller.microphonePermission.isAllowed
                            ? context.tr('voiceConversationWithSaathi')
                            : context.tr('error.VOICE_PERMISSION_DENIED'),
                      ),
                      trailing: Icon(
                        controller.microphonePermission.isAllowed
                            ? LucideIcons.circleCheck
                            : LucideIcons.chevronRight,
                        color: controller.microphonePermission.isAllowed
                            ? AppColors.leaf
                            : null,
                      ),
                      onTap: () async {
                        final state = await controller
                            .requestMicrophonePermission();
                        if (context.mounted) {
                          await _handleResult(context, state);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              InlineNotice(
                title: context.tr('devicePermissionMatters'),
                message: context.tr('permissionBlockedBody'),
                icon: LucideIcons.smartphone,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
              InlineNotice(
                title: context.tr('onlyUsefulFactsSaved'),
                message: context.tr('onlyUsefulFactsSavedBody'),
                icon: LucideIcons.brain,
                color: AppColors.leaf,
              ),
              const SizedBox(height: 22),
              if (memories.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: AppStateView(
                    kind: AppStateKind.empty,
                    title: context.tr('noSavedFacts'),
                    message: context.tr('noSavedFactsBody'),
                  ),
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
                      subtitle: Text(
                        '${context.tr(memory.scope)} · ${context.tr(memory.status)}',
                      ),
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
        title: Text(context.tr('deleteMemoryQuestion')),
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
          label: Text(context.tr('addReminder')),
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
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant
                  .withValues(alpha: 0.5),
            ),
          ),
          child: AppStateView(
            kind: AppStateKind.empty,
            title: context.tr('noRemindersHere'),
            message:
                'Accepted and manually created reminders appear in this list.',
          ),
        ),
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
                    tooltip: context.tr('reminderActions'),
                    onSelected: (action) => _act(context, item, action),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'done',
                        child: Text(context.tr('markDone')),
                      ),
                      PopupMenuItem(
                        value: 'skip',
                        child: Text(context.tr('skipReminder')),
                      ),
                      PopupMenuItem(
                        value: 'reschedule',
                        child: Text(context.tr('reschedule')),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text(context.tr('cancelReminder')),
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
          showAppSnackBar(context, context.tr('chooseFutureReminderTime'));
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
      showAppSnackBar(context, context.tr('chooseFutureReminderTime'));
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
      showAppSnackBar(context, context.tr('reminderScheduled'), success: true);
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
                decoration: InputDecoration(labelText: context.tr('task')),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Enter the task to remember'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _plotId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('plotOptional'),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.tr('noPlot')),
                  ),
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
                title: Text(context.tr('dateAndTime')),
                subtitle: Text(context.strings.formatDateTime(_dueAt)),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _pickDateTime,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: _recurrenceDays,
                decoration: InputDecoration(labelText: context.tr('repeat')),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.tr('doesNotRepeat')),
                  ),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(context.tr('everyDay')),
                  ),
                  DropdownMenuItem(
                    value: 7,
                    child: Text(context.tr('everyWeek')),
                  ),
                  DropdownMenuItem(
                    value: 30,
                    child: Text(context.tr('every30Days')),
                  ),
                ],
                onChanged: (value) => setState(() => _recurrenceDays = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('notesOptional'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    context.tr(_saving ? 'scheduling' : 'scheduleReminder'),
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

class _ProposalList extends StatelessWidget {
  const _ProposalList({required this.items});

  final List<ReminderProposalModel> items;

  @override
  Widget build(BuildContext context) {
    final pending = items.where((item) => item.status == 'pending').toList();
    if (pending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant
                  .withValues(alpha: 0.5),
            ),
          ),
          child: AppStateView(
            kind: AppStateKind.empty,
            title: context.tr('noSuggestionsWaiting'),
            message: context.tr('noSuggestionsWaitingBody'),
          ),
        ),
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
                      child: Text(context.tr('notNow')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          _decide(context, proposal.id, accepted: true),
                      child: Text(context.tr('schedule')),
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
          context.tr(accepted ? 'reminderScheduled' : 'suggestionDeclined'),
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
            _HelpTile(
              icon: LucideIcons.scanLine,
              title: context.tr('helpClearLeafPhoto'),
              body: context.tr('helpClearLeafPhotoBody'),
            ),
            _HelpTile(
              icon: LucideIcons.map,
              title: context.tr('helpFarmPlotSetup'),
              body: context.tr('helpFarmPlotSetupBody'),
            ),
            _HelpTile(
              icon: LucideIcons.cloudOff,
              title: context.tr('helpOfflineUse'),
              body: context.tr('helpOfflineUseBody'),
            ),
            _HelpTile(
              icon: LucideIcons.shieldCheck,
              title: context.tr('helpPrivacySharing'),
              body: context.tr('helpPrivacySharingBody'),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _showSupport(context),
              icon: const Icon(LucideIcons.mail),
              label: Text(context.tr('contactSupport')),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(LucideIcons.mapPin),
                title: Text('Koramangala, Bengaluru'),
                subtitle: Text('Karnataka 560034, India'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.phone),
                title: const Text('7903422423'),
                subtitle: Text(context.tr('supportContact')),
                trailing: IconButton(
                  tooltip: context.tr('copyNumber'),
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
            ListTile(
              title: Text(context.tr('version')),
              trailing: const Text('1.0.1 (4)'),
            ),
            const Divider(),
            ListTile(
              title: Text(context.tr('applicationId')),
              trailing: const Text('com.krishisathi.mobile'),
            ),
          ],
        ),
      ),
    ),
  );
}
