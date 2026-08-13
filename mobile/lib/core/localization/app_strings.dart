import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_language.dart';
import 'translations.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const delegate = _AppStringsDelegate();
  static final supportedLocales = AppLanguage.supported
      .map((item) => item.locale)
      .toList();

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        const AppStrings(Locale('en'));
  }

  String text(String key, [Map<String, Object?> values = const {}]) {
    var value =
        translations[locale.languageCode]?[key] ?? englishStrings[key] ?? key;
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return value;
  }
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppLanguage.supported.any(
    (language) => language.code == locale.languageCode,
  );

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
  String tr(String key, [Map<String, Object?> values = const {}]) =>
      strings.text(key, values);
}
