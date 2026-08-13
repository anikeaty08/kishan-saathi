import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const forest = Color(0xFF173B2C);
  static const leaf = Color(0xFF2E7D4F);
  static const youngLeaf = Color(0xFF71A858);
  static const mineral = Color(0xFFF3F6EF);
  static const surface = Color(0xFFFBFCF8);
  static const ink = Color(0xFF17201B);
  static const mutedInk = Color(0xFF647067);
  static const soil = Color(0xFF5C4938);
  static const amber = Color(0xFFD5A43B);
  static const sky = Color(0xFF397B9D);
  static const danger = Color(0xFFB34E48);
  static const divider = Color(0xFFDDE4DA);
  static const darkSurface = Color(0xFF14231B);
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class AppRadius {
  static const small = 4.0;
  static const medium = 8.0;
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.leaf,
      brightness: Brightness.light,
      primary: AppColors.forest,
      secondary: AppColors.amber,
      surface: AppColors.surface,
      error: AppColors.danger,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.mineral,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.mineral,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.leaf.withValues(alpha: 0.13),
        height: 68,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.forest
                : AppColors.mutedInk,
            size: 23,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: Color(0x1F2E7D4F),
        selectedIconTheme: IconThemeData(color: AppColors.forest),
        unselectedIconTheme: IconThemeData(color: AppColors.mutedInk),
        groupAlignment: -0.75,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.youngLeaf,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
      error: const Color(0xFFFFB4AB),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0E1812),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E1812),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final textTheme = Typography.material2021().black
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          fontFamilyFallback: const [
            'Noto Sans',
            'Noto Sans Devanagari',
            'Noto Sans Bengali',
            'Noto Sans Gujarati',
            'Noto Sans Gurmukhi',
            'Noto Sans Tamil',
            'Noto Sans Telugu',
            'Noto Sans Kannada',
            'Noto Sans Malayalam',
            'Noto Sans Oriya',
            'Noto Sans Ol Chiki',
            'Noto Sans Meetei Mayek',
            'Noto Nastaliq Urdu',
          ],
        )
        .copyWith(
          displaySmall: const TextStyle(
            fontSize: 34,
            height: 1.08,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          headlineLarge: const TextStyle(
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          headlineMedium: const TextStyle(
            fontSize: 23,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          titleLarge: const TextStyle(
            fontSize: 19,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            height: 1.45,
            letterSpacing: 0,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.45,
            letterSpacing: 0,
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelLarge,
      ),
    );
  }
}
