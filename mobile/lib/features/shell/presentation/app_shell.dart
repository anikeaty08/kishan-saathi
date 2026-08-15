import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/ui/app_ui.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(int index) {
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = [
      _Destination(
        context.tr('home'),
        LucideIcons.house,
        LucideIcons.housePlug,
      ),
      _Destination(
        context.tr('farm'),
        LucideIcons.sprout,
        LucideIcons.treeDeciduous,
      ),
      _Destination(
        context.tr('scan'),
        LucideIcons.scanLine,
        LucideIcons.scanSearch,
      ),
      _Destination(
        context.tr('saathi'),
        LucideIcons.messageCircle,
        LucideIcons.messageCircleMore,
      ),
    ];
    return PopScope<void>(
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && navigationShell.currentIndex != 0) {
          navigationShell.goBranch(0);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= 600;
          final extendedRail = constraints.maxWidth >= 940;
          if (!useRail) {
            return Scaffold(
              body: navigationShell,
              bottomNavigationBar: SafeArea(
                top: false,
                child: NavigationBar(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _select,
                  destinations: destinations
                      .map(
                        (item) => NavigationDestination(
                          icon: Icon(item.icon),
                          selectedIcon: Icon(item.selectedIcon),
                          label: item.label,
                          tooltip: item.label,
                        ),
                      )
                      .toList(),
                ),
              ),
            );
          }
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    extended: extendedRail,
                    minExtendedWidth: 220,
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: _select,
                    leading: Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: BrandMark(showName: extendedRail, size: 40),
                    ),
                    destinations: destinations
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                          ),
                        )
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: navigationShell),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
