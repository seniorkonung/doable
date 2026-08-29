import 'package:flutter/widgets.dart';

/// Выбирает локаль приложения для `MaterialApp.localeListResolutionCallback`.
///
/// Контракт callback: https://api.flutter.dev/flutter/widgets/WidgetsApp/localeListResolutionCallback.html
Locale resolveAppLocale(
  List<Locale>? platformLocales,
  Iterable<Locale> supportedLocales,
) {
  final String? languageCode = switch (platformLocales) {
    [final Locale primaryLocale, ...] =>
      primaryLocale.languageCode.toLowerCase(),
    _ => null,
  };
  final String resolvedLanguageCode = languageCode == 'ru' ? 'ru' : 'en';

  for (final Locale locale in supportedLocales) {
    if (locale.languageCode.toLowerCase() == resolvedLanguageCode) {
      return locale;
    }
  }

  return const Locale('en');
}
