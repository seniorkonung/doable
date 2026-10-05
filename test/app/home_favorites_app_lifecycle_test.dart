import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionSaved;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';

// Названия намерений — данные человека: они одинаковы в обеих локалях.

/// «Гулять», готово к действию.
const _walk = 1;

/// «Читать», готово к действию.
const _read = 2;

/// «Плавать», не готово к действию.
const _swim = 3;

/// «Бегать», готово к действию: источник обеих связей и невыполненного
/// дневного выбора.
const _run = 4;

/// «Спать», готово к действию: выбранное действие дневного выбора.
const _sleep = 5;

/// «Петь», готово к действию: связанный участник связи вне дневных путей.
const _sing = 6;

const _titles = {
  _walk: 'Гулять',
  _read: 'Читать',
  _swim: 'Плавать',
  _run: 'Бегать',
  _sleep: 'Спать',
  _sing: 'Петь',
};

/// Связь «Бегать» → «Спать» — путь невыполненного дневного выбора.
const _pathRelation = 101;

/// Связь «Бегать» → «Петь» вне дневных путей: её связанного участника можно
/// заменить.
const _freeRelation = 102;

/// Невыполненный дневной выбор, из замены пути которого открываются поиски
/// действия и исходного намерения.
const _openChoice = 201;

/// Идентификатор, которому не соответствует ни одно намерение.
const _missing = 99;

/// Тег «Дом», который получает намерение, созданное с полным начальным
/// состоянием.
const _homeTag = 301;

const _favoriteControl = ValueKey('intention-details-favorite-mark');
const _message = ValueKey('graph-operation-message');

/// Следующее подтверждённое изменение после отказа обновления Главной.
enum _NextChange {
  /// Отметка «Бегать» — изменение, затрагивающее избранное.
  favorite('отметка другого намерения'),

  /// Переименование неизбранного «Спать» — изменение, избранного не
  /// затрагивающее.
  unrelated('переименование неизбранного намерения');

  const _NextChange(this.description);

  final String description;
}

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets('после полного перезапуска Главная показывает те же избранные '
        'намерения в том же порядке, архивированное остаётся скрытым и после '
        'восстановления встаёт на своё место, а снятая отметка не возвращается '
        'на $code', (tester) async {
      final install = await _install(tester, locale);
      final l10n = install.l10n;
      final first = await _launch(
        tester,
        install,
        seed: (database) =>
            _seedGraph(database, favorites: const [_swim, _walk, _read, _run]),
      );
      await _expectHome(tester, l10n, const [_swim, _walk, _read, _run]);

      // Подтверждённые операции первого запуска: отметка, архивирование
      // избранного намерения и снятие отметки.
      await _select(tester, AppDestination.intentionGraph);
      await _openFromCatalog(tester, _sleep);
      await _toggleMark(tester);
      await _closeDetails(tester);
      await _openFromCatalog(tester, _read);
      await _archive(tester);
      await _closeDetails(tester);
      await _openFromCatalog(tester, _run);
      await _toggleMark(tester);
      await _closeDetails(tester);
      await _select(tester, AppDestination.home);
      await _expectHome(tester, l10n, const [_swim, _walk, _sleep]);
      final marks = [
        (tagFixtureId(_swim), 1),
        (tagFixtureId(_walk), 2),
        (tagFixtureId(_read), 3),
        (tagFixtureId(_sleep), 5),
      ];
      expect(storedFavoriteMarks(first.raw), marks);

      // Полное завершение и новый запуск на том же хранилище.
      await first.shutdown(tester);
      final second = await _launch(tester, install);
      _expectHomeRoot(tester, second);
      await _expectHome(tester, l10n, const [_swim, _walk, _sleep]);
      expect(storedFavoriteMarks(second.raw), marks);

      // Подтверждённое снятие отметки не вернулось: каталог показывает
      // «Бегать» без звезды, а его страница предлагает отметить.
      await _select(tester, AppDestination.intentionGraph);
      await _expectStars(
        tester,
        IntentionCatalogPage,
        l10n,
        shown: const [_walk, _swim, _run, _sleep, _sing],
        favorites: const {_walk, _swim, _sleep},
      );
      await _openFromCatalog(tester, _run);
      expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
      await _closeDetails(tester);

      // Архивированное избранное намерение сохранило отметку и после
      // восстановления встаёт на своё место.
      await _selectScope(tester, l10n.catalogScopeArchived);
      await _expectStars(
        tester,
        IntentionCatalogPage,
        l10n,
        shown: const [_read],
        favorites: const {_read},
      );
      await _openFromCatalog(tester, _read);
      expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
      await _restore(tester);
      await _closeDetails(tester);
      await _select(tester, AppDestination.home);
      await _expectHome(tester, l10n, const [_swim, _walk, _read, _sleep]);
      expect(storedFavoriteMarks(second.raw), marks);
      expect(find.byKey(_message), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'хранилище с намерениями, связями, тегами и дневными выборами без '
      'отметок показывает, что избранных намерений нет, и отметки не '
      'создаются ни при запуске, ни после перезапуска на $code',
      (tester) async {
        final install = await _install(tester, locale);
        final l10n = install.l10n;
        late Map<String, List<List<Object?>>> stored;
        final first = await _launch(
          tester,
          install,
          seed: (database) {
            seedTagStorageFixture(database);
            stored = _storedGraph(database);
          },
        );
        expect(stored['intentions'], hasLength(3));
        for (final table in [
          'long_term_relations',
          'daily_choices',
          'tags',
          'tag_assignments',
        ]) {
          expect(stored[table], isNotEmpty, reason: table);
        }
        _expectEmptyHome(tester, l10n, l10n.homeEmptyNoFavorites);
        expect(storedFavoriteMarks(first.raw), isEmpty);
        expect(_storedGraph(first.raw), stored);

        await first.shutdown(tester);
        final second = await _launch(tester, install);
        _expectHomeRoot(tester, second);
        _expectEmptyHome(tester, l10n, l10n.homeEmptyNoFavorites);
        expect(storedFavoriteMarks(second.raw), isEmpty);
        expect(_storedGraph(second.raw), stored);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'единственное избранное намерение, архивированное до перезапуска, '
      'даёт и после него состояние «все избранные намерения в архиве» на '
      '$code',
      (tester) async {
        final install = await _install(tester, locale);
        final l10n = install.l10n;
        final first = await _launch(tester, install, seed: _seedGraph);
        _expectEmptyHome(tester, l10n, l10n.homeEmptyNoFavorites);

        await _select(tester, AppDestination.intentionGraph);
        await _openFromCatalog(tester, _walk);
        await _toggleMark(tester);
        await _archive(tester);
        await _closeDetails(tester);
        await _select(tester, AppDestination.home);
        await _until(tester, _homeText(l10n.homeEmptyAllArchived));
        await tester.pumpAndSettle();
        _expectEmptyHome(tester, l10n, l10n.homeEmptyAllArchived);

        await first.shutdown(tester);
        final second = await _launch(tester, install);
        _expectHomeRoot(tester, second);
        _expectEmptyHome(tester, l10n, l10n.homeEmptyAllArchived);
        expect(storedFavoriteMarks(second.raw), [(tagFixtureId(_walk), 1)]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('место без существующего намерения даёт на Главной отдельное '
        'неповторяемое повреждение, а каталог намерений, поиски и страница '
        'намерения продолжают работать с целостными отметками на $code', (
      tester,
    ) async {
      final install = await _install(tester, locale);
      final l10n = install.l10n;
      final app = await _launch(
        tester,
        install,
        seed: (database) {
          _seedGraph(database, favorites: const [_walk, _read]);
          storeFavoritePlaceWithoutIntention(
            database,
            intentionId: tagFixtureId(_missing),
            position: 3,
          );
        },
      );
      _expectCorruption(tester, l10n);
      // Повреждение не исправляется: место без намерения остаётся.
      final marks = [
        (tagFixtureId(_walk), 1),
        (tagFixtureId(_read), 2),
        (tagFixtureId(_missing), 3),
      ];
      expect(storedFavoriteMarks(app.raw), marks);

      // Каталог намерений и три поиска показывают целостные отметки.
      await _select(tester, AppDestination.intentionGraph);
      await _expectSearches(tester, app, l10n);

      // Страница избранного намерения показывает его отметку, а отметка
      // другого намерения подтверждается и видна в каталоге.
      await _openFromCatalog(tester, _walk);
      expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
      await _closeDetails(tester);
      final reads = install.faults.reads;
      await _openFromCatalog(tester, _run);
      expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
      await _toggleMark(tester);
      expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
      await _closeDetails(tester);
      await _expectStars(
        tester,
        IntentionCatalogPage,
        l10n,
        shown: _titles.keys.toList(),
        favorites: const {_walk, _read, _run},
      );
      expect(storedFavoriteMarks(app.raw), [...marks, (tagFixtureId(_run), 4)]);

      // Подтверждённое изменение избранного перечитывает список, и
      // повреждение остаётся отдельным результатом, а не списком с
      // пропуском.
      await _waitFor(tester, () => install.faults.reads > reads);
      await _select(tester, AppDestination.home);
      _expectCorruption(tester, l10n);
      expect(find.byKey(_message), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('устранимая недоступность первоначального получения показывает '
        'сообщение с повтором, а успешный повтор — актуальный список без '
        'прежнего сообщения на $code', (tester) async {
      final install = await _install(tester, locale);
      final l10n = install.l10n;
      install.faults.failNextRead();
      await _launch(
        tester,
        install,
        seed: (database) =>
            _seedGraph(database, favorites: const [_read, _walk]),
      );

      // Отказ не выдаётся за пустой список, а повтор сам не запускается.
      await _settleStorage(tester);
      expect(install.faults.reads, 1);
      expect(_homeText(l10n.homeUnavailable), findsOneWidget);
      expect(_retry(l10n), findsOneWidget);
      expect(_homeRows, findsNothing);
      for (final text in [
        l10n.homeEmptyNoFavorites,
        l10n.homeEmptyAllArchived,
        l10n.homeOpenIntentionGraph,
      ]) {
        expect(_homeText(text), findsNothing);
      }

      await _tap(tester, _retry(l10n));
      await _expectHome(tester, l10n, const [_read, _walk]);
      expect(_homeText(l10n.homeUnavailable), findsNothing);
      expect(install.faults.reads, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'отказ обновления после подтверждённого изменения сохраняет прежний '
      'список с пометкой и повтором, а успешный повтор восстанавливает '
      'актуальность на $code',
      (tester) async {
        final install = await _install(tester, locale);
        final l10n = install.l10n;
        await _launch(
          tester,
          install,
          seed: (database) =>
              _seedGraph(database, favorites: const [_walk, _read]),
        );
        await _expectHome(tester, l10n, const [_walk, _read]);

        await _openFromHome(tester, _read);
        install.faults.failNextRead();
        final reads = install.faults.reads;
        await _rename(tester, 'Читать книги');
        await _closeDetails(tester);
        await _until(tester, _homeText(l10n.homeRefreshUnavailable));
        await tester.pumpAndSettle();

        // Прежний подтверждённый список остаётся с пометкой и повтором, а
        // повтор сам не запускается.
        await _settleStorage(tester);
        expect(install.faults.reads, reads + 1);
        expect(_shownHome(tester), ['Гулять', 'Читать']);
        expect(_homeText(l10n.homeRefreshUnavailable), findsOneWidget);
        expect(_retry(l10n), findsOneWidget);

        await _tap(tester, _retry(l10n));
        await _pumpUntil(
          tester,
          () => listEquals(_shownHome(tester), ['Гулять', 'Читать книги']),
        );
        await tester.pumpAndSettle();
        expect(_shownHome(tester), ['Гулять', 'Читать книги']);
        _expectCurrent(tester, l10n);
        expect(install.faults.reads, reads + 2);
        expect(tester.takeException(), isNull);
      },
    );

    for (final next in _NextChange.values) {
      testWidgets('отказ обновления, пока Главная не выбрана, восстанавливает '
          'следующее подтверждённое изменение — ${next.description} — до '
          'возврата на Главную на $code', (tester) async {
        final install = await _install(tester, locale);
        final l10n = install.l10n;
        final app = await _launch(
          tester,
          install,
          seed: (database) =>
              _seedGraph(database, favorites: const [_walk, _read]),
        );
        await _expectHome(tester, l10n, const [_walk, _read]);

        // Архивирование избранного «Читать» при выбранном графе намерений:
        // обновление Главной отказывает.
        await _select(tester, AppDestination.intentionGraph);
        await _openFromCatalog(tester, _read);
        install.faults.failNextRead();
        await _archive(tester);
        await _closeDetails(tester);
        // Скрытая Главная не перестраивается, пока её не выберут, поэтому
        // её состояние читается у модели.
        await _waitFor(
          tester,
          () => switch (_homeState(app)) {
            HomeList(freshness: HomeFreshnessStale()) => true,
            _ => false,
          },
        );
        await _settleStorage(tester);
        expect(_selected(tester), AppDestination.intentionGraph);
        expect(
          _homeState(app),
          isA<HomeList>()
              .having(_titlesOf, 'items', ['Гулять', 'Читать'])
              .having(
                (state) => state.freshness,
                'freshness',
                isA<HomeFreshnessStale>().having(
                  (freshness) => freshness.canRetry,
                  'canRetry',
                  isTrue,
                ),
              ),
        );
        final reads = install.faults.reads;

        final expected = switch (next) {
          _NextChange.favorite => ['Гулять', 'Бегать'],
          _NextChange.unrelated => ['Гулять'],
        };
        switch (next) {
          case _NextChange.favorite:
            await _openFromCatalog(tester, _run);
            await _toggleMark(tester);
          case _NextChange.unrelated:
            await _openFromCatalog(tester, _sleep);
            await _rename(tester, 'Спать днём');
        }
        await _closeDetails(tester);

        // Главная обновилась, пока выбран граф намерений.
        await _waitFor(
          tester,
          () => switch (_homeState(app)) {
            final HomeList state =>
              listEquals(_titlesOf(state), expected) &&
                  state.freshness is HomeFreshnessCurrent,
            _ => false,
          },
        );
        expect(_selected(tester), AppDestination.intentionGraph);
        expect(install.faults.reads, greaterThan(reads));

        // Возврат на Главную показывает актуальный список без нового
        // чтения и без пометки.
        final readsBeforeReturn = install.faults.reads;
        await _select(tester, AppDestination.home);
        expect(_shownHome(tester), expected);
        _expectCurrent(tester, l10n);
        await _settleStorage(tester);
        expect(install.faults.reads, readsBeforeReturn);
        expect(tester.takeException(), isNull);
      });
    }

    for (final mark in FavoriteMark.values) {
      testWidgets(
        switch (mark) {
          FavoriteMark.favorite =>
            'намерение, созданное сразу избранным, пока Главная не выбрана, '
                'встаёт в её конец после архивированного места без отдельной '
                'отметки ещё до возврата на Главную на $code',
          FavoriteMark.notFavorite =>
            'намерение, созданное без отметки, пока Главная не выбрана, не '
                'появляется на ней и не вызывает её чтения на $code',
        },
        (tester) async {
          final install = await _install(tester, locale);
          final l10n = install.l10n;
          // Единый порядок: «Гулять», архивированное «Читать», «Плавать».
          final app = await _launch(
            tester,
            install,
            seed: (database) {
              _seedGraph(database, favorites: const [_walk, _read, _swim]);
              database.execute(
                'UPDATE intentions SET is_archived = 1 WHERE id = ?',
                [tagFixtureId(_read)],
              );
              database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
                tagFixtureId(_homeTag),
                'Дом',
              ]);
            },
          );
          await _expectHome(tester, l10n, const [_walk, _swim]);
          final marks = [
            (tagFixtureId(_walk), 1),
            (tagFixtureId(_read), 2),
            (tagFixtureId(_swim), 3),
          ];
          expect(storedFavoriteMarks(app.raw), marks);

          await _select(tester, AppDestination.intentionGraph);
          await _settleStorage(tester);
          final shown = _homeState(app);
          final reads = install.faults.reads;
          final events = app.diagnostics.events.length;
          final completions = <GraphCommandCompletion>[];
          final subscription = app.coordinator.completions.listen(
            completions.add,
          );
          addTearDown(subscription.cancel);

          // Всё начальное состояние принимается координатором одной командой,
          // как её отправит форма создания.
          final accepted = app.coordinator.acceptCreation(
            IntentionCreationFormKey(),
            CreateIntention.withInitialState(
              title: 'Рисовать',
              description: null,
              readiness: IntentionReadiness.ready,
              favoriteMark: mark,
              tagIds: [
                (TagId.decode(
                  tagFixtureId(_homeTag),
                ) as TagIdDecodingSuccess).id,
              ],
            ),
          ) as IntentionCommandAccepted;
          IntentionCommandCompletion? completion;
          unawaited(accepted.future.then((value) => completion = value));
          await _waitFor(tester, () => completion != null);
          final created = switch (completion!.result) {
            GraphResultSuccess(value: IntentionSaved(:final intention)) =>
              intention.id.toCanonicalString(),
            final result => fail('Создание не подтверждено: $result'),
          };

          switch (mark) {
            case FavoriteMark.favorite:
              // Скрытая Главная согласуется до закрытия сообщения об успехе.
              await _waitFor(
                tester,
                () => switch (_homeState(app)) {
                  final HomeList state =>
                    listEquals(_titlesOf(state), [
                          'Гулять',
                          'Плавать',
                          'Рисовать',
                        ]) &&
                        state.freshness is HomeFreshnessCurrent,
                  _ => false,
                },
              );
              final list = _homeState(app) as HomeList;
              expect(
                [for (final row in list.items) row.id.toCanonicalString()],
                [tagFixtureId(_walk), tagFixtureId(_swim), created],
              );
              expect(list.items.last.readiness, IntentionReadiness.ready);
              expect(install.faults.reads, greaterThan(reads));
              expect(storedFavoriteMarks(app.raw), [...marks, (created, 4)]);
            case FavoriteMark.notFavorite:
              await _settleStorage(tester);
              expect(_homeState(app), same(shown));
              expect(install.faults.reads, reads);
              expect(storedFavoriteMarks(app.raw), marks);
          }
          expect(_selected(tester), AppDestination.intentionGraph);

          // Создание — одна команда с одним исходом: самостоятельные отметка,
          // готовность и назначение тега не выполнялись.
          expect(completions, [same(completion)]);
          expect(
            app.diagnostics.events
                .skip(events)
                .where(
                  (event) =>
                      event is IntentionCommandDiagnosticsEvent ||
                      event is TagCommandDiagnosticsEvent ||
                      event is FavoriteOrderCommandDiagnosticsEvent,
                ),
            [
              isA<IntentionCommandDiagnosticsEvent>()
                  .having(
                    (event) => event.commandType,
                    'команда',
                    IntentionCommandDiagnosticsType.create,
                  )
                  .having(
                    (event) => event.status,
                    'статус',
                    isA<DiagnosticsSucceeded>(),
                  ),
            ],
          );
          await _acceptMessage(tester);

          // Возврат на Главную показывает согласованный список без нового
          // чтения.
          final readsBeforeReturn = install.faults.reads;
          await _select(tester, AppDestination.home);
          expect(_shownHome(tester), switch (mark) {
            FavoriteMark.favorite => ['Гулять', 'Плавать', 'Рисовать'],
            FavoriteMark.notFavorite => ['Гулять', 'Плавать'],
          });
          _expectCurrent(tester, l10n);
          await _settleStorage(tester);
          expect(install.faults.reads, readsBeforeReturn);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

/// Установка приложения: постоянное хранилище, переживающее перезапуски, и
/// управляемые отказы чтения списка Главной.
final class _Install {
  _Install(this.harness, this.l10n);

  final LocalDatabaseHarness harness;
  final AppLocalizations l10n;
  final faults = _HomeReadFaults();
}

Future<_Install> _install(WidgetTester tester, Locale locale) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  addTearDown(harness.dispose);
  return _Install(harness, lookupAppLocalizations(locale));
}

/// Один запуск приложения на хранилище установки.
final class _Launch {
  _Launch(this.runtime, this.raw, this.container, this.diagnostics);

  final AppRuntime runtime;
  final sqlite.Database raw;
  final ProviderContainer container;
  final InMemoryDiagnosticsSink diagnostics;

  AppRouter get router => container.read(appRouterProvider);

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  /// Полное завершение: дерево приложения снято, хранилище закрыто.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.shutdown);
  }
}

/// Запускает приложение на хранилище [install], засевает его [seed] и ждёт,
/// пока Главная закончит первоначальное получение.
Future<_Launch> _launch(
  WidgetTester tester,
  _Install install, {
  void Function(sqlite.Database database)? seed,
}) async {
  late sqlite.Database raw;
  final diagnostics = InMemoryDiagnosticsSink();
  final runtime = AppRuntime(
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(
        install.harness.databaseFile,
        setup: (database) => raw = database,
      ),
      install.faults,
    ),
    diagnosticsSink: diagnostics,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  seed?.call(raw);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.text(install.l10n.homeLoading).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return _Launch(runtime, raw, ready.container, diagnostics);
}

/// Шесть активных намерений, связи «Бегать» и его невыполненный дневной
/// выбор; [favorites] отмечены в этом порядке на местах 1, 2, …
void _seedGraph(sqlite.Database database, {List<int> favorites = const []}) {
  for (final MapEntry(key: number, value: title) in _titles.entries) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, number == _swim ? 0 : 1, 0, number, number],
    );
  }
  for (final (number, related) in [
    (_pathRelation, _sleep),
    (_freeRelation, _sing),
  ]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(_run),
        tagFixtureId(related),
        'need',
        2,
        0,
      ],
    );
  }
  database.execute(
    'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
    [
      tagFixtureId(_openChoice),
      tagFixtureId(_run),
      tagFixtureId(_sleep),
      '2026-09-25',
      0,
    ],
  );
  database.execute(
    'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
    [
      tagFixtureId(_openChoice + 10),
      tagFixtureId(_openChoice),
      tagFixtureId(_pathRelation),
    ],
  );
  for (final (index, intention) in favorites.indexed) {
    storeFavoriteMark(
      database,
      intentionId: tagFixtureId(intention),
      position: index + 1,
    );
  }
}

/// Сохранённые данные графа, которые Главная и запуск не должны менять:
/// намерения, связи, дневные выборы, теги и их назначения.
Map<String, List<List<Object?>>> _storedGraph(sqlite.Database database) => {
  ...retainedTagFixtureGraph(database),
  for (final table in ['tags', 'tag_assignments'])
    table: database
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

/// Элементы Главной, в том числе пока она закрыта другим пунктом или
/// страницей поверх оболочки.
Finder _onHome(Finder matching) => find.descendant(
  of: find.byType(HomePage, skipOffstage: false),
  matching: matching,
  skipOffstage: false,
);

/// Текст [text] на Главной.
Finder _homeText(String text) => _onHome(find.text(text, skipOffstage: false));

final _homeRows = _onHome(find.byType(HomeIntentionRow, skipOffstage: false));

/// Повтор получения на Главной.
Finder _retry(AppLocalizations l10n) => _onHome(
  find.widgetWithText(FilledButton, l10n.commonRetry, skipOffstage: false),
);

/// Названия строк Главной в порядке списка.
List<String> _shownHome(WidgetTester tester) => [
  for (final row in tester.widgetList<HomeIntentionRow>(_homeRows))
    row.row.title,
];

HomeState _homeState(_Launch app) => app.container.read(homeViewModelProvider);

List<String> _titlesOf(HomeList state) => [
  for (final row in state.items) row.title,
];

/// Дожидается, пока Главная покажет ровно намерения [expected] в порядке
/// списка, и подтверждает, что список актуален.
Future<void> _expectHome(
  WidgetTester tester,
  AppLocalizations l10n,
  List<int> expected,
) async {
  final titles = [for (final number in expected) _titles[number]!];
  await _pumpUntil(tester, () => listEquals(_shownHome(tester), titles));
  await tester.pumpAndSettle();
  expect(_shownHome(tester), titles);
  expect(
    [
      for (final row in tester.widgetList<HomeIntentionRow>(_homeRows))
        row.row.id.toCanonicalString(),
    ],
    [for (final number in expected) tagFixtureId(number)],
  );
  _expectCurrent(tester, l10n);
}

/// Показанный снимок актуален: пометки «не обновлён», отказа получения и
/// повтора нет.
void _expectCurrent(WidgetTester tester, AppLocalizations l10n) {
  for (final text in [
    l10n.homeRefreshUnavailable,
    l10n.homeRefreshCorruption,
    l10n.homeRefreshUnexpected,
    l10n.homeUnavailable,
    l10n.homeCorruption,
    l10n.homeUnexpected,
  ]) {
    expect(_homeText(text), findsNothing, reason: text);
  }
  expect(_retry(l10n), findsNothing);
}

/// Главная показывает пустое состояние [message] с переходом к графу
/// намерений, а не загрузку, отказ или другое пустое состояние.
void _expectEmptyHome(
  WidgetTester tester,
  AppLocalizations l10n,
  String message,
) {
  expect(_homeText(message), findsOneWidget);
  for (final other in [l10n.homeEmptyNoFavorites, l10n.homeEmptyAllArchived]) {
    if (other != message) expect(_homeText(other), findsNothing);
  }
  expect(_homeText(l10n.homeOpenIntentionGraph), findsOneWidget);
  expect(_homeRows, findsNothing);
  expect(_homeText(l10n.homeLoading), findsNothing);
  _expectCurrent(tester, l10n);
}

/// Главная показывает отдельный неповторяемый результат повреждения: не
/// пустое состояние, не список с пропуском и не обычный повтор.
void _expectCorruption(WidgetTester tester, AppLocalizations l10n) {
  expect(_homeText(l10n.homeCorruption), findsOneWidget);
  expect(_homeRows, findsNothing);
  expect(_retry(l10n), findsNothing);
  for (final text in [
    l10n.homeEmptyNoFavorites,
    l10n.homeEmptyAllArchived,
    l10n.homeOpenIntentionGraph,
    l10n.homeUnavailable,
    l10n.homeLoading,
  ]) {
    expect(_homeText(text), findsNothing, reason: text);
  }
}

/// Открыта Главная: страниц поверх нет, панель видна, выбран пункт
/// «Главная».
void _expectHomeRoot(WidgetTester tester, _Launch app) {
  expect(app.router.canPop(), isFalse);
  expect(app.router.topRoute.name, HomeRoute.name);
  expect(find.byType(HomePage), findsOneWidget);
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(_selected(tester), AppDestination.home);
}

AppDestination _selected(WidgetTester tester) => tester
    .widget<AppNavigationBar>(
      find.byType(AppNavigationBar, skipOffstage: false),
    )
    .selected;

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await _tap(
    tester,
    find.descendant(
      of: find.byType(AppNavigationBar),
      matching: find.byIcon(
        _selected(tester) == destination
            ? destination.selectedIcon
            : destination.icon,
      ),
    ),
  );
  await _until(tester, find.byType(_rootPages[destination]!));
  await tester.pumpAndSettle();
  expect(_selected(tester), destination);
}

const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: DailyChoiceCatalogPage,
  AppDestination.intentionGraph: IntentionCatalogPage,
};

Finder _catalogRow(int intention) => find.descendant(
  of: find.byType(IntentionCatalogPage),
  matching: find.widgetWithText(IntentionSummaryView, _titles[intention]!),
);

Future<void> _openFromCatalog(WidgetTester tester, int intention) async {
  await _tap(tester, _catalogRow(intention));
  await _expectDetails(tester, intention);
}

Future<void> _openFromHome(WidgetTester tester, int intention) async {
  await _tap(
    tester,
    find.descendant(
      of: find.byType(HomePage),
      matching: find.widgetWithText(HomeIntentionRow, _titles[intention]!),
    ),
  );
  await _expectDetails(tester, intention);
}

/// Открыта страница именно намерения [intention].
Future<void> _expectDetails(WidgetTester tester, int intention) async {
  await _until(tester, find.byKey(_favoriteControl));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<IntentionDetailsPage>(find.byType(IntentionDetailsPage))
        .intentionId
        .toCanonicalString(),
    tagFixtureId(intention),
  );
}

/// Закрывает страницу намерения системным действием «назад».
Future<void> _closeDetails(WidgetTester tester) =>
    _closeTop(tester, IntentionDetailsPage);

Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _gone(tester, page);
}

String? _controlTooltip(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(_favoriteControl)).tooltip;

/// Нажимает управление отметкой и дожидается подтверждённого результата.
Future<void> _toggleMark(WidgetTester tester) async {
  final before = _controlTooltip(tester);
  await _tap(tester, find.byKey(_favoriteControl));
  await _waitFor(tester, () => _controlTooltip(tester) != before);
  await _acceptMessage(tester);
}

Future<void> _archive(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-archive')));
  await _until(tester, find.byKey(const ValueKey('intention-details-restore')));
  await _acceptMessage(tester);
}

Future<void> _restore(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-restore')));
  await _until(tester, find.byKey(const ValueKey('intention-details-archive')));
  await _acceptMessage(tester);
}

Future<void> _rename(WidgetTester tester, String title) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-edit')));
  final field = find.byKey(const ValueKey('intention-details-edit-title'));
  await _until(tester, field);
  await tester.enterText(field, title);
  final submit = find.byKey(const ValueKey('intention-details-edit-submit'));
  await _tap(tester, submit);
  await _waitFor(tester, () => submit.evaluate().isEmpty);
  await _until(
    tester,
    find.descendant(
      of: find.byType(IntentionDetailsPage),
      matching: find.text(title),
    ),
  );
  await _acceptMessage(tester);
}

/// Дожидается ровно одного сообщения общей поверхности о подтверждённой
/// операции и закрывает его.
Future<void> _acceptMessage(WidgetTester tester) async {
  await _until(tester, find.byKey(_message));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  // Предъявленный результат не показывается повторно.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsNothing);
}

/// Проверяет звёзды целостных отметок в каталоге намерений и в поисках
/// действия, исходного намерения и участника связи.
Future<void> _expectSearches(
  WidgetTester tester,
  _Launch app,
  AppLocalizations l10n,
) async {
  const favorites = {_walk, _read};
  await _expectStars(
    tester,
    IntentionCatalogPage,
    l10n,
    shown: _titles.keys.toList(),
    favorites: favorites,
  );

  // Поиск действия: только активные готовые намерения.
  unawaited(
    app.router.push(
      DailyChoiceDetailsRoute(
        choiceId: (DailyChoiceId.decode(
          tagFixtureId(_openChoice),
        ) as DailyChoiceIdDecodingSuccess).id,
      ),
    ),
  );
  await _tap(tester, find.byKey(const ValueKey('daily-choice-replace-open')));
  await _tap(
    tester,
    find.byKey(const ValueKey('daily-choice-replace-bottom-up')),
  );
  await _until(tester, find.byType(DailyChoiceActionPickerPage));
  await _expectStars(
    tester,
    DailyChoiceActionPickerPage,
    l10n,
    shown: const [_walk, _read, _run, _sleep, _sing],
    favorites: favorites,
  );
  await _tap(tester, find.byKey(const ValueKey('daily-choice-action-cancel')));
  await _gone(tester, DailyChoiceActionPickerPage);

  // Поиск исходного намерения: активные независимо от готовности.
  await _tap(
    tester,
    find.byKey(const ValueKey('daily-choice-replace-top-down')),
  );
  await _until(tester, find.byType(DailyChoiceSourcePickerPage));
  await _expectStars(
    tester,
    DailyChoiceSourcePickerPage,
    l10n,
    shown: _titles.keys.toList(),
    favorites: favorites,
  );
  await _tap(tester, find.byKey(const ValueKey('daily-choice-source-cancel')));
  await _gone(tester, DailyChoiceSourcePickerPage);
  await _popToRoot(tester, app);

  // Поиск участника связи: второй участник «Бегать» исключён.
  unawaited(
    app.router.push(
      RelationDetailsRoute(
        relationId: (LongTermRelationId.decode(
          tagFixtureId(_freeRelation),
        ) as LongTermRelationIdDecodingSuccess).id,
      ),
    ),
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('relation-details-edit-relation')),
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('relation-editor-change-related')),
  );
  await _until(tester, find.byType(RelationParticipantPickerPage));
  await _expectStars(
    tester,
    RelationParticipantPickerPage,
    l10n,
    shown: const [_walk, _read, _swim, _sleep, _sing],
    favorites: favorites,
  );
  await _tap(tester, find.byKey(const ValueKey('participant-picker-cancel')));
  await _gone(tester, RelationParticipantPickerPage);
  await _popToRoot(tester, app);
  expect(find.byType(IntentionCatalogPage), findsOneWidget);
}

/// Дожидается, пока выдача страницы [page] покажет ровно намерения [shown], и
/// проверяет звезду каждого: она есть только у [favorites] и несёт
/// локализованное название отметки.
Future<void> _expectStars(
  WidgetTester tester,
  Type page,
  AppLocalizations l10n, {
  required List<int> shown,
  required Set<int> favorites,
}) async {
  final expected = {
    for (final number in shown) _titles[number]!: favorites.contains(number),
  };
  await _pumpUntil(
    tester,
    () => mapEquals(_shownStars(tester, page, l10n), expected),
  );
  await tester.pumpAndSettle();
  expect(_shownStars(tester, page, l10n), expected);
}

/// Видимые результаты поиска страницы: название и наличие звезды так, как
/// они показаны.
Map<String, bool> _shownStars(
  WidgetTester tester,
  Type page,
  AppLocalizations l10n,
) {
  final rows = find.descendant(
    of: find.byType(page),
    matching: find.byType(IntentionSummaryView),
  );
  return {
    for (var index = 0; index < rows.evaluate().length; index++)
      tester.widget<IntentionSummaryView>(rows.at(index)).title: switch (tester
          .widgetList<Icon>(
            find.descendant(
              of: rows.at(index),
              matching: find.byIcon(Icons.star),
            ),
          )
          .toList()) {
        [] => false,
        [final star]
            when star.semanticLabel == l10n.intentionSummaryFavoriteMark =>
          true,
        final stars => fail('Недопустимая отметка строки: $stars'),
      },
  };
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _popToRoot(WidgetTester tester, _Launch app) async {
  while (app.router.canPop()) {
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
  }
}

Future<void> _gone(WidgetTester tester, Type page) async {
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

/// Даёт хранилищу и кадрам время: запущенное чтение успело бы завершиться.
Future<void> _settleStorage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  await _pumpUntil(tester, done);
  expect(done(), isTrue);
}

/// Продвигает кадры и реальное время хранилища, пока не выполнится [done]
/// или не истечёт срок; результат проверяет вызывающий.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Нажимает элемент [finder], прокручивая к нему, только если он не
/// принимает нажатие: прокрутка к видимой строке выдачи увела бы параметры
/// поиска каталога намерений за верхний край страницы.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pump();
}

/// Наблюдает чтения списка Главной и по требованию отказывает ближайшему из
/// них устранимой недоступностью хранилища; транзакция чтения откатывается
/// самим адаптером, а остальные чтения и записи не затрагиваются.
final class _HomeReadFaults extends LocalDatabaseConnectionObserver {
  var _failNext = false;

  /// Число чтений списка Главной, дошедших до хранилища.
  var reads = 0;

  void failNextRead() => _failNext = true;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.any(
          (sql) => sql.contains('FROM favorite_intentions f'),
        )) {
      return;
    }
    reads++;
    if (!_failNext) return;
    _failNext = false;
    throw sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'Управляемый отказ чтения списка Главной',
    );
  }
}
