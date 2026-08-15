import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/localization/app_language.dart';
import 'package:krishisathi/core/localization/app_strings.dart';
import 'package:krishisathi/core/network/api_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('locale registry includes English and all 22 scheduled languages', () {
    expect(AppLanguage.supported, hasLength(23));
    expect(
      AppLanguage.supported.map((language) => language.code).toSet(),
      hasLength(23),
    );
    expect(
      AppLanguage.supported
          .where((language) => language.rtl)
          .map((item) => item.code),
      containsAll(<String>['ks', 'sd', 'ur']),
    );
  });

  test('every language has a complete bundled offline catalog', () async {
    final english = await AppStrings.load(const Locale('en'));
    for (final language in AppLanguage.supported) {
      final strings = await AppStrings.load(language.locale);
      expect(strings.text('appName'), isNotEmpty);
      expect(strings.text('error.SCAN_IMAGE_TOO_SMALL'), isNotEmpty);
      expect(strings.text('month.long.8'), isNotEmpty);
      expect(strings.text('weekday.long.1'), isNotEmpty);
      expect(
        strings.text('definitely.not.a.real.key'),
        'definitely.not.a.real.key',
      );
      expect(english.text('appName'), 'KrishiSathi');
    }
  });

  test('localized dates translate names but always use 0-9 digits', () async {
    final hindi = await AppStrings.load(const Locale('hi'));
    final urdu = await AppStrings.load(const Locale('ur'));
    final value = DateTime(2026, 8, 12, 9, 5);

    expect(hindi.formatDate(value), '12 अगस्त 2026');
    expect(urdu.formatDate(value), '12 اگست 2026');
    expect(hindi.formatTime(value), '09:05');
    expect(
      RegExp(r'[٠-٩۰-۹०-९০-৯]').hasMatch(urdu.formatDateTime(value)),
      isFalse,
    );
  });

  test('API errors use local message codes and preserve support ID', () async {
    final strings = await AppStrings.load(const Locale('en'));
    final message = strings.apiError(
      const ApiException(
        code: 'LEAF_MODEL_NOT_CONFIGURED',
        message: 'provider details that must not reach the farmer',
        statusCode: 503,
        requestId: 'req-123',
      ),
    );

    expect(message, contains('Leaf analysis is not connected yet'));
    expect(message, contains('req-123'));
    expect(message, isNot(contains('provider details')));
  });

  test(
    'unknown API errors fall back by status without provider prose',
    () async {
      final strings = await AppStrings.load(const Locale('hi'));
      final message = strings.apiError(
        const ApiException(
          code: 'NEW_PROVIDER_FAILURE',
          message: 'raw provider exception',
          statusCode: 502,
        ),
      );

      expect(message, isNotEmpty);
      expect(message, isNot('raw provider exception'));
    },
  );
}
