import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('разрешение системной локали', () {
    test('выбирает русский по language code основной локали', () {
      final locale = resolveAppLocale(const <Locale>[
        Locale('ru', 'RU'),
      ], AppLocalizations.supportedLocales);

      expect(locale, const Locale('ru'));
    });

    test('выбирает английский по language code основной локали', () {
      final locale = resolveAppLocale(const <Locale>[
        Locale('en', 'GB'),
      ], AppLocalizations.supportedLocales);

      expect(locale, const Locale('en'));
    });

    test('использует английский fallback для другой локали', () {
      final locale = resolveAppLocale(const <Locale>[
        Locale('de', 'DE'),
      ], AppLocalizations.supportedLocales);

      expect(locale, const Locale('en'));
    });

    test('использует английский fallback без данных платформы', () {
      expect(
        resolveAppLocale(null, AppLocalizations.supportedLocales),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(const <Locale>[], AppLocalizations.supportedLocales),
        const Locale('en'),
      );
    });
  });

  test(
    'generated-каталоги содержат начальные английские и русские строки',
    () async {
      final english = await AppLocalizations.delegate.load(const Locale('en'));
      final russian = await AppLocalizations.delegate.load(const Locale('ru'));

      expect(AppLocalizations.supportedLocales, const <Locale>[
        Locale('en'),
        Locale('ru'),
      ]);
      expect(english.appTitle, 'Doable');
      expect(russian.appTitle, 'Doable');
      expect(english.navigationActiveIntentions, 'Active intentions');
      expect(russian.navigationActiveIntentions, 'Активные намерения');
      expect(english.navigationArchive, 'Archive');
      expect(russian.navigationArchive, 'Архив');
      expect(english.commonLoading, 'Loading…');
      expect(russian.commonLoading, 'Загрузка…');
      expect(english.commonEmpty, 'Nothing here yet');
      expect(russian.commonEmpty, 'Пока здесь ничего нет');
      expect(english.commonError, 'Something went wrong');
      expect(russian.commonError, 'Что-то пошло не так');
      expect(english.commonRetry, 'Try again');
      expect(russian.commonRetry, 'Повторить');
      expect(english.bootstrapLoading, 'Preparing local data…');
      expect(russian.bootstrapLoading, 'Подготавливаем локальные данные…');
      expect(
        english.bootstrapMigrationFailure,
        'Local data couldn’t be prepared. Your data wasn’t changed. Try again.',
      );
      expect(
        russian.bootstrapMigrationFailure,
        'Не удалось подготовить локальные данные. Данные не изменены. '
        'Повторите попытку.',
      );
      expect(
        english.bootstrapIncompatibleSchema,
        'Install a compatible Doable update to continue.',
      );
      expect(
        russian.bootstrapIncompatibleSchema,
        'Чтобы продолжить, установите совместимое обновление Doable.',
      );
    },
  );

  testWidgets('приложение применяет русскую локаль платформы', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale('ru', 'RU'),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const MainApp());
    final context = tester.element(find.byType(Scaffold));

    expect(Localizations.localeOf(context), const Locale('ru'));
    expect(AppLocalizations.of(context).commonRetry, 'Повторить');
  });

  testWidgets('приложение применяет английский fallback платформы', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale('de', 'DE'),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const MainApp());
    final context = tester.element(find.byType(Scaffold));

    expect(Localizations.localeOf(context), const Locale('en'));
    expect(AppLocalizations.of(context).commonRetry, 'Try again');
  });
}
