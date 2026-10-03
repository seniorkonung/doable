import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/presentation/favorite_order_failure_message.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));
  final en = lookupAppLocalizations(const Locale('en'));

  final scenarios =
      <({FavoriteOrderCommandFailure failure, String ru, String en})>[
        (
          failure: const FavoriteOrderConflictFailure(),
          ru:
              'Новый порядок избранных намерений не сохранён, потому что '
              'список изменился.',
          en:
              'The new order of favorite intentions wasn’t saved because the '
              'list changed.',
        ),
        (
          failure: const FavoriteOrderInputFailure(),
          ru:
              'Новый порядок избранных намерений не сохранён: недопустимое '
              'перемещение.',
          en:
              'The new order of favorite intentions wasn’t saved: the move '
              'isn’t valid.',
        ),
        (
          failure: const FavoriteOrderUnavailableFailure(),
          ru:
              'Не удалось сохранить новый порядок избранных намерений. '
              'Повторите попытку.',
          en:
              'The new order of favorite intentions couldn’t be saved. '
              'Try again.',
        ),
        (
          failure: const FavoriteOrderCorruptionFailure(),
          ru:
              'Сохранённые данные избранных намерений повреждены. Новый порядок '
              'не сохранён.',
          en:
              'Stored favorite intention data is damaged. The new order wasn’t '
              'saved.',
        ),
        (
          failure: const FavoriteOrderUnexpectedFailure(),
          ru:
              'Не удалось сохранить новый порядок избранных намерений из-за '
              'непредвиденной ошибки.',
          en:
              'The new order of favorite intentions couldn’t be saved because '
              'of an unexpected error.',
        ),
      ];

  group('сообщение отказа перестановки избранных намерений', () {
    for (final scenario in scenarios) {
      test('${scenario.failure.category.name} получает русский текст', () {
        expect(favoriteOrderFailureMessage(ru, scenario.failure), scenario.ru);
      });

      test('${scenario.failure.category.name} получает английский текст', () {
        expect(favoriteOrderFailureMessage(en, scenario.failure), scenario.en);
      });
    }

    test(
      'каждая категория отказа получает собственный текст в обеих локалях',
      () {
        for (final localizations in [ru, en]) {
          final messages = {
            for (final scenario in scenarios)
              favoriteOrderFailureMessage(localizations, scenario.failure),
          };

          expect(messages, hasLength(scenarios.length));
        }
      },
    );

    test('неподдерживаемая системная локаль получает английский текст', () {
      final fallback = lookupAppLocalizations(
        resolveAppLocale(const [
          Locale('de', 'DE'),
        ], AppLocalizations.supportedLocales),
      );

      for (final scenario in scenarios) {
        expect(
          favoriteOrderFailureMessage(fallback, scenario.failure),
          scenario.en,
        );
      }
    });

    test('тексты не раскрывают SQL, исключения, идентификаторы и места', () {
      final forbidden = RegExp(
        r'\d|select|update|insert|delete|transaction|sqlite|drift|favorite_|'
        r'intention_id|exception|error:|failure|stack',
        caseSensitive: false,
      );

      for (final localizations in [ru, en]) {
        for (final scenario in scenarios) {
          final message = favoriteOrderFailureMessage(
            localizations,
            scenario.failure,
          );

          expect(message, isNot(contains(forbidden)));
          expect(message.trim(), isNotEmpty);
        }
      }
    });
  });
}
