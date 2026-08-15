import 'package:flutter/widgets.dart';

class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.englishName,
    required this.nativeName,
    this.rtl = false,
  });

  final String code;
  final String englishName;
  final String nativeName;
  final bool rtl;

  Locale get locale => Locale(code);

  static const supported = <AppLanguage>[
    AppLanguage(code: 'en', englishName: 'English', nativeName: 'English'),
    AppLanguage(code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी'),
    AppLanguage(code: 'as', englishName: 'Assamese', nativeName: 'অসমীয়া'),
    AppLanguage(code: 'bn', englishName: 'Bengali', nativeName: 'বাংলা'),
    AppLanguage(code: 'brx', englishName: 'Bodo', nativeName: 'बड़ो'),
    AppLanguage(code: 'doi', englishName: 'Dogri', nativeName: 'डोगरी'),
    AppLanguage(code: 'gu', englishName: 'Gujarati', nativeName: 'ગુજરાતી'),
    AppLanguage(code: 'kn', englishName: 'Kannada', nativeName: 'ಕನ್ನಡ'),
    AppLanguage(
      code: 'ks',
      englishName: 'Kashmiri',
      nativeName: 'کٲشُر',
      rtl: true,
    ),
    AppLanguage(code: 'kok', englishName: 'Konkani', nativeName: 'कोंकणी'),
    AppLanguage(code: 'mai', englishName: 'Maithili', nativeName: 'मैथिली'),
    AppLanguage(code: 'ml', englishName: 'Malayalam', nativeName: 'മലയാളം'),
    AppLanguage(code: 'mni', englishName: 'Manipuri', nativeName: 'ꯃꯤꯇꯩ ꯂꯣꯟ'),
    AppLanguage(code: 'mr', englishName: 'Marathi', nativeName: 'मराठी'),
    AppLanguage(code: 'ne', englishName: 'Nepali', nativeName: 'नेपाली'),
    AppLanguage(code: 'or', englishName: 'Odia', nativeName: 'ଓଡ଼ିଆ'),
    AppLanguage(code: 'pa', englishName: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ'),
    AppLanguage(code: 'sa', englishName: 'Sanskrit', nativeName: 'संस्कृतम्'),
    AppLanguage(code: 'sat', englishName: 'Santali', nativeName: 'ᱥᱟᱱᱛᱟᱲᱤ'),
    AppLanguage(
      code: 'sd',
      englishName: 'Sindhi',
      nativeName: 'سنڌي',
      rtl: true,
    ),
    AppLanguage(code: 'ta', englishName: 'Tamil', nativeName: 'தமிழ்'),
    AppLanguage(code: 'te', englishName: 'Telugu', nativeName: 'తెలుగు'),
    AppLanguage(code: 'ur', englishName: 'Urdu', nativeName: 'اردو', rtl: true),
  ];

  static AppLanguage byCode(String code) => supported.firstWhere(
    (language) => language.code == code,
    orElse: () => supported.first,
  );
}
