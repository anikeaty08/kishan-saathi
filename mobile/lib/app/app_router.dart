import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/ui/app_ui.dart';
import '../features/farm/presentation/farm_screens.dart';
import '../features/farm/presentation/plot_history_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/weather_screen.dart';
import '../features/onboarding/presentation/onboarding_screens.dart';
import '../features/profile/presentation/profile_screens.dart';
import '../features/saathi/presentation/saathi_screens.dart';
import '../features/scan/presentation/scan_screens.dart';
import '../features/shared/presentation/app_controller.dart';
import '../features/shell/presentation/app_shell.dart';

GoRouter createAppRouter(AppController controller) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: controller.onboardingComplete ? '/home' : '/welcome',
    refreshListenable: controller,
    redirect: (context, state) {
      final path = state.uri.path;
      final onboardingPath =
          path == '/welcome' ||
          path == '/auth' ||
          path.startsWith('/onboarding/');
      final mainPath =
          path == '/home' ||
          path == '/farm' ||
          path == '/scan' ||
          path == '/saathi';
      if (!controller.onboardingComplete && mainPath) return '/welcome';
      if (controller.onboardingComplete && path == '/welcome') return '/home';
      if (!controller.onboardingComplete || onboardingPath) return null;
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/onboarding/profile',
        builder: (_, state) => ProfileSetupScreen(
          preview: state.uri.queryParameters['preview'] == 'true',
        ),
      ),
      GoRoute(
        path: '/onboarding/language',
        builder: (_, state) => LanguageSetupScreen(
          preview: state.uri.queryParameters['preview'] == 'true',
        ),
      ),
      GoRoute(
        path: '/onboarding/permissions',
        builder: (_, state) => PermissionsSetupScreen(
          preview: state.uri.queryParameters['preview'] == 'true',
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/farm', builder: (_, _) => const FarmScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/scan',
                builder: (_, state) => ScanScreen(
                  key: ValueKey(state.uri.toString()),
                  initialPlotId: state.uri.queryParameters['plot'],
                  retakeCaseId: state.uri.queryParameters['retake'],
                  initialImageSource: state.uri.queryParameters['source'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/saathi', builder: (_, _) => const SaathiScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/weather',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const WeatherScreen(),
      ),
      GoRoute(
        path: '/profile',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/reminders',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const RemindersScreen(),
      ),
      GoRoute(
        path: '/farm/add',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const AddFarmScreen(),
      ),
      GoRoute(
        path: '/farm/:farmId',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            FarmDetailScreen(farmId: state.pathParameters['farmId']!),
      ),
      GoRoute(
        path: '/farm/:farmId/edit',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            EditFarmScreen(farmId: state.pathParameters['farmId']!),
      ),
      GoRoute(
        path: '/farm/:farmId/plot/add',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            AddPlotScreen(farmId: state.pathParameters['farmId']!),
      ),
      GoRoute(
        path: '/plot/:plotId',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            PlotDetailScreen(plotId: state.pathParameters['plotId']!),
      ),
      GoRoute(
        path: '/plot/:plotId/edit',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            EditPlotScreen(plotId: state.pathParameters['plotId']!),
      ),
      GoRoute(
        path: '/plot/:plotId/history',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            PlotHistoryScreen(plotId: state.pathParameters['plotId']!),
      ),
      GoRoute(
        path: '/plot/:plotId/crops',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            ManageCropsScreen(plotId: state.pathParameters['plotId']!),
      ),
      GoRoute(
        path: '/plot/:plotId/activity/add',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            AddActivityScreen(plotId: state.pathParameters['plotId']!),
      ),
      GoRoute(
        path: '/plot/:plotId/activity/:activityId',
        parentNavigatorKey: rootKey,
        builder: (_, state) => ActivityDetailScreen(
          plotId: state.pathParameters['plotId']!,
          activityId: state.pathParameters['activityId']!,
        ),
      ),
      GoRoute(
        path: '/scan/result/:diagnosisId',
        parentNavigatorKey: rootKey,
        builder: (_, state) => DiagnosisResultScreen(
          diagnosisId: state.pathParameters['diagnosisId']!,
        ),
      ),
      GoRoute(
        path: '/scan/queue',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const QueuedScansScreen(),
      ),
      GoRoute(
        path: '/saathi/new',
        parentNavigatorKey: rootKey,
        builder: (_, state) => NewChatScreen(
          initialPrompt: state.uri.queryParameters['prompt'],
          initialScope: state.uri.queryParameters['scope'],
          initialContextId: state.uri.queryParameters['context'],
        ),
      ),
      GoRoute(
        path: '/saathi/chat/:chatId',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            ChatDetailScreen(chatId: state.pathParameters['chatId']!),
      ),
      GoRoute(
        path: '/settings/language',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const LanguageSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/notifications',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/privacy',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const PrivacyScreen(),
      ),
      GoRoute(
        path: '/settings/memory',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const MemoryScreen(),
      ),
      GoRoute(
        path: '/help',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const HelpScreen(),
      ),
      GoRoute(
        path: '/about',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const AboutScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: AppStateView(
        kind: AppStateKind.error,
        title: 'Screen not found',
        message: state.error?.toString() ?? 'This route is not available.',
        actionLabel: 'Go home',
        onAction: () => context.go('/home'),
      ),
    ),
  );
}
