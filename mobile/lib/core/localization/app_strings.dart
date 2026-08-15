import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../network/api_exception.dart';
import 'app_language.dart';

class AppStrings {
  const AppStrings._(this.locale, this._values, this._englishValues);

  final Locale locale;
  final Map<String, String> _values;
  final Map<String, String> _englishValues;
  static final Map<String, AppStrings> _cache = {};

  static const delegate = _AppStringsDelegate();
  static final supportedLocales = AppLanguage.supported
      .map((item) => item.locale)
      .toList();

  static AppStrings of(BuildContext context) {
    final strings = Localizations.of<AppStrings>(context, AppStrings);
    assert(strings != null, 'AppStrings delegate is missing from MaterialApp.');
    return strings!;
  }

  static Future<AppStrings> load(Locale locale, {AssetBundle? bundle}) async {
    final assetBundle = bundle ?? rootBundle;
    final language = AppLanguage.byCode(locale.languageCode);
    final existing = _cache[language.code];
    if (existing != null) return existing;
    // English is the fallback for every locale. Reuse its immutable catalog
    // after the first load instead of issuing another root-bundle request for
    // every language switch.
    final english =
        _cache['en']?._values ?? await _loadBundle('en', assetBundle);
    final selected = language.code == 'en'
        ? english
        : await _loadBundle(language.code, assetBundle);
    final strings = AppStrings._(language.locale, selected, english);
    _cache[language.code] = strings;
    return strings;
  }

  static AppStrings? cached(Locale locale) => _cache[locale.languageCode];

  static Future<Map<String, String>> _loadBundle(
    String languageCode,
    AssetBundle bundle,
  ) async {
    final raw = await bundle.loadString('lib/l10n/app_$languageCode.arb');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Invalid language bundle: $languageCode');
    }
    return Map.unmodifiable({
      for (final entry in decoded.entries)
        if (!entry.key.startsWith('@') && entry.value is String)
          entry.key: entry.value as String,
    });
  }

  String text(String key, [Map<String, Object?> values = const {}]) {
    var value = _values[key] ?? _englishValues[key] ?? key;
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return value;
  }

  /// Use translated month names while keeping every numeric glyph as 0-9.
  String formatDate(DateTime value) =>
      '${value.day} ${text('month.long.${value.month}')} ${value.year}';

  String formatShortDate(DateTime value) =>
      '${value.day} ${text('month.short.${value.month}')}';

  String formatWeekdayDate(DateTime value) =>
      '${text('weekday.long.${value.weekday}')}, ${formatShortDate(value)}';

  String formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String formatDateTime(DateTime value) =>
      '${formatDate(value)} · ${formatTime(value)}';

  String apiError(ApiException error) {
    final key = 'error.${error.code}';
    var value = _values[key] ?? _englishValues[key];
    value ??= switch (error.statusCode) {
      401 => text('error.authenticationRequired'),
      403 => text('error.permissionDenied'),
      404 => text('error.recordNotFound'),
      409 => text('error.conflict'),
      413 => text('error.uploadTooLarge'),
      422 => text('error.validation'),
      final status when status != null && status >= 500 => text(
        'error.serviceUnavailable',
      ),
      _ => text('errorBody'),
    };
    if (error.requestId case final requestId?) {
      return '$value\n${text('requestId', {'id': requestId})}';
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
  Future<AppStrings> load(Locale locale) {
    final cached = AppStrings.cached(locale);
    return cached == null
        ? AppStrings.load(locale)
        : SynchronousFuture<AppStrings>(cached);
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
  String tr(String key, [Map<String, Object?> values = const {}]) =>
      strings.text(key, values);
  String localizedError(ApiException error) => strings.apiError(error);
}
