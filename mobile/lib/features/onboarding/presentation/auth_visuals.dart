import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';

class AuthSurface extends StatelessWidget {
  const AuthSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final foreground = Colors.white.withValues(alpha: 0.94);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF07150D).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 42,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Theme(
        data: base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: AppColors.youngLeaf,
            onPrimary: AppColors.forest,
            surface: const Color(0xFF12251A),
            onSurface: foreground,
          ),
          textTheme: base.textTheme.apply(
            bodyColor: foreground,
            displayColor: foreground,
          ),
          inputDecorationTheme: base.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
            prefixIconColor: Colors.white.withValues(alpha: 0.72),
            suffixIconColor: Colors.white.withValues(alpha: 0.72),
            enabledBorder: fieldBorder,
            border: fieldBorder,
          ),
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.forest
                    : foreground,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.youngLeaf
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: child,
        ),
      ),
    );
  }
}

class AuthStory extends StatelessWidget {
  const AuthStory({super.key});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandMark(size: 48, dark: true),
            const SizedBox(height: 20),
            Text(
              'Your fields, understood.',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Private crop records, local weather and practical guidance—kept together for every farm.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.84),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthHero extends StatelessWidget {
  const AuthHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('auth-hero-image'),
      image: true,
      label: 'Healthy Indian crops growing in a sunlit field',
      child: Image.asset(
        'assets/images/auth_field_hero.webp',
        alignment: const Alignment(0.05, 0),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
