import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/localization/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../features/shared/presentation/app_controller.dart';
import 'app_router.dart';

class KrishiSathiApp extends StatefulWidget {
  const KrishiSathiApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<KrishiSathiApp> createState() => _KrishiSathiAppState();
}

class _KrishiSathiAppState extends State<KrishiSathiApp> {
  late final router = createAppRouter(widget.controller);

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: Consumer<AppController>(
        builder: (context, controller, _) {
          return MaterialApp.router(
            title: 'KrishiSathi',
            debugShowCheckedModeBanner: false,
            locale: controller.locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: controller.themeMode,
            routerConfig: router,
            builder: (context, child) {
              return Directionality(
                textDirection: controller.selectedLanguage.rtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
