import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const russianMessages = [
    'Быстрое создание',
    'Новое намерение',
    'Новая связь',
    'Дневной выбор от намерения',
    'Дневной выбор от действия',
    'Сменить режим',
    'Режим быстрого создания',
    'Нажмите и удерживайте, чтобы сменить режим',
  ];
  const englishMessages = [
    'Quick create',
    'New intention',
    'New relation',
    'Daily choice from an intention',
    'Daily choice from an action',
    'Change mode',
    'Quick creation mode',
    'Touch and hold to change mode',
  ];

  for (final (name, platformLocales, expectedLocale, expectedMessages) in [
    (
      'русский',
      const [Locale('ru', 'RU')],
      const Locale('ru'),
      russianMessages,
    ),
    (
      'английский',
      const [Locale('en', 'GB')],
      const Locale('en'),
      englishMessages,
    ),
    (
      'английский fallback при нерусской основной локали',
      const [Locale('de', 'DE'), Locale('ru', 'RU')],
      const Locale('en'),
      englishMessages,
    ),
  ]) {
    test('быстрое создание: $name — все названия в порядке режимов', () async {
      final locale = resolveAppLocale(
        platformLocales,
        AppLocalizations.supportedLocales,
      );
      final localizations = await AppLocalizations.delegate.load(locale);

      expect(locale, expectedLocale);
      expect([
        localizations.quickCreationLabel,
        ...QuickCreationMode.values.map((mode) => mode.title(localizations)),
        localizations.quickCreationChangeMode,
        localizations.quickCreationMenuTitle,
        localizations.quickCreationLongPressHint,
      ], expectedMessages);
    });
  }

  test('четыре режима сохраняют порядок и различимые значки направлений', () {
    expect(QuickCreationMode.values, const [
      QuickCreationMode.intention,
      QuickCreationMode.relation,
      QuickCreationMode.dailyChoiceFromIntention,
      QuickCreationMode.dailyChoiceFromAction,
    ]);
    expect(QuickCreationMode.values.map((mode) => mode.icon), const [
      Icons.circle_outlined,
      Icons.link,
      Icons.arrow_downward,
      Icons.arrow_upward,
    ]);
    expect(quickCreationChangeModeIcon, Icons.unfold_more);
  });
}
