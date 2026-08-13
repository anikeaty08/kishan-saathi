import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 44,
    this.showName = true,
    this.dark = false,
  });

  final double size;
  final bool showName;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: Image.asset(
            'assets/branding/app_icon.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            semanticLabel: context.tr('appName'),
          ),
        ),
        if (showName) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              context.tr('appName'),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: dark ? Colors.white : AppColors.forest,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class AppContent extends StatelessWidget {
  const AppContent({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.mutedInk),
                ),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

enum AppStateKind { loading, empty, error, success }

class AppStateView extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final AppStateKind kind;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      AppStateKind.loading => (LucideIcons.loaderCircle, AppColors.sky),
      AppStateKind.empty => (LucideIcons.sprout, AppColors.leaf),
      AppStateKind.error => (LucideIcons.triangleAlert, AppColors.danger),
      AppStateKind.success => (LucideIcons.circleCheck, AppColors.leaf),
    };
    return Semantics(
      liveRegion: true,
      label: '$title. $message',
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 24 : 48,
          horizontal: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind == AppStateKind.loading)
              const SizedBox.square(
                dimension: 34,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedInk),
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.title,
    required this.message,
    this.icon = LucideIcons.info,
    this.color = AppColors.sky,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppColors.mutedInk),
                  ),
                  if (action != null) ...[const SizedBox(height: 8), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImageBand extends StatelessWidget {
  const ImageBand({
    super.key,
    required this.asset,
    required this.child,
    this.height = 210,
    this.alignment = Alignment.center,
  });

  final String asset;
  final Widget child;
  final double height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final accessibleHeight = height + ((textScale - 1).clamp(0.0, 1.5) * 150);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: SizedBox(
        height: accessibleHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(asset, fit: BoxFit.cover, alignment: alignment),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1A000000), Color(0xC9000000)],
                  stops: [0.2, 1],
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(20), child: child),
          ],
        ),
      ),
    );
  }
}

class MetricCell extends StatelessWidget {
  const MetricCell({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = AppColors.forest,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.mutedInk),
          ),
        ],
      ),
    );
  }
}

void showAppSnackBar(
  BuildContext context,
  String message, {
  bool success = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? LucideIcons.circleCheck : LucideIcons.info,
              color: Colors.white,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
    );
}
