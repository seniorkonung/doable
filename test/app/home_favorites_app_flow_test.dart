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
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

// Названия намерений — данные человека: они одинаковы в обеих локалях.

/// «Гулять», готово к действию — А, первое избранное намерение.
const _walk = 1;

/// «Гулять», не готово к действию — В, тёзка А и третье избранное намерение.
const _otherWalk = 2;

/// «Читать», готово к действию — Б, второе избранное намерение.
const _read = 3;

/// «Плавать», архивированное готовое действие — Г.
const _swim = 4;

/// «Бегать» и «Спать» — активные готовые намерения без отметки.
const _run = 5;
const _sleep = 6;

/// Связь «Бегать» → «Спать» — путь невыполненного дневного выбора.
const _pathRelation = 101;

/// Связь «Бегать» → В вне дневных путей: её связанного участника можно
/// заменить, а у В одна активная связь.
const _freeRelation = 103;

/// Невыполненный дневной выбор, из замены пути которого открываются поиски
/// действия и исходного намерения.
const _openChoice = 201;

/// Избранные намерения «Избранное 01» … «Избранное 40» на местах 1…40:
/// список Главной длиннее экрана.
const _longFavoriteCount = 40;
const _firstLongFavorite = 1001;

const _favoriteControl = ValueKey('intention-details-favorite-mark');
const _message = ValueKey('graph-operation-message');

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets(
      'с пустой Главной человек отмечает намерения и видит их на Главной в '
      'порядке отметок, а строка открывает своё намерение на $code',
      (tester) async {
        final harness = await _harness(tester, locale);
        final app = await _App.start(tester, locale, harness, _seedGraph);
        final l10n = app.l10n;
        final before = retainedTagFixtureGraph(app.raw);

        _expectHomeRoot(tester, app);
        expect(find.text(l10n.homeEmptyNoFavorites), findsOneWidget);

        // Переход пустой Главной открывает граф намерений.
        await _tap(tester, find.text(l10n.homeOpenIntentionGraph));
        await _until(tester, find.byType(IntentionCatalogPage));
        expect(_selected(tester), AppDestination.intentionGraph);
        await _expectRows(tester, IntentionCatalogPage, [
          ('Спать', false),
          ('Бегать', false),
          ('Читать', false),
          ('Гулять', false),
          ('Гулять', false),
        ], l10n);

        // Порядок отметок не совпадает с порядком каталога.
        for (final (row, intention, title) in [
          (4, _walk, 'Гулять'),
          (2, _read, 'Читать'),
          (3, _otherWalk, 'Гулять'),
        ]) {
          await _openFromCatalog(tester, row: row, intention: intention);
          await _toggleMark(
            tester,
            l10n.graphOperationMessage(
              l10n.graphOperationMarkFavorite,
              title,
              l10n.detailsFavoriteMarked,
            ),
          );
          await _closeTop(tester, IntentionDetailsPage);
        }
        expect(storedFavoriteMarks(app.raw), [
          (tagFixtureId(_walk), 1),
          (tagFixtureId(_read), 2),
          (tagFixtureId(_otherWalk), 3),
        ]);

        // Каталог и поиски показывают отметку звездой в собственном порядке
        // выдачи: порядок избранных на него не влияет.
        await _expectSearches(tester, app);

        await _select(tester, AppDestination.home);
        await _expectHome(tester, [
          _homeRow(l10n, _walk, 'Гулять', ready: true, relations: 0),
          _homeRow(l10n, _read, 'Читать', ready: true, relations: 0),
          _homeRow(l10n, _otherWalk, 'Гулять', ready: false, relations: 1),
        ]);
        // Неотмеченные и архивированные намерения на Главной не показаны.
        for (final title in ['Бегать', 'Спать', 'Плавать']) {
          expect(
            find.descendant(
              of: find.byType(HomePage),
              matching: find.text(title),
            ),
            findsNothing,
          );
        }

        // Строка открывает именно своё намерение, в том числе второе из
        // одноимённых, а закрытие страницы возвращает на Главную.
        for (final (row, intention) in [(2, _otherWalk), (0, _walk)]) {
          await _openFromHome(tester, row: row, intention: intention);
          expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
          await _closeTop(tester, IntentionDetailsPage);
          _expectHomeRoot(tester, app);
        }

        // Отметки не меняют намерения, связи и дневные выборы.
        expect(retainedTagFixtureGraph(app.raw), before);
        expect(find.byKey(_message), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Главная отражает подтверждённые изменения графа без нового запуска '
      'на $code',
      (tester) async {
        final harness = await _harness(tester, locale);
        final app = await _App.start(
          tester,
          locale,
          harness,
          (database) =>
              _seedGraph(database, favorites: const [_walk, _read, _otherWalk]),
        );
        final l10n = app.l10n;
        final a = _homeRow(l10n, _walk, 'Гулять', ready: true, relations: 0);
        final b = _homeRow(l10n, _read, 'Читать', ready: true, relations: 0);
        final c = _homeRow(
          l10n,
          _otherWalk,
          'Гулять',
          ready: false,
          relations: 1,
        );
        final d = _homeRow(l10n, _swim, 'Плавать', ready: true, relations: 0);
        await _expectHome(tester, [a, b, c]);

        // Архивирование Б скрывает его, а страница Б показывает его избранным.
        await _openFromHome(tester, row: 1, intention: _read);
        await _archive(tester);
        expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
        await _closeTop(tester, IntentionDetailsPage);
        _expectHomeRoot(tester, app);
        await _expectHome(tester, [a, c]);

        // Восстановление возвращает Б на его место.
        await _select(tester, AppDestination.intentionGraph);
        await _selectScope(tester, l10n.catalogScopeArchived);
        await _expectRows(tester, IntentionCatalogPage, [
          ('Плавать', false),
          ('Читать', true),
        ], l10n);
        await _openFromCatalog(tester, row: 1, intention: _read);
        await _restore(tester);
        await _closeTop(tester, IntentionDetailsPage);
        await _select(tester, AppDestination.home);
        await _expectHome(tester, [a, b, c]);

        // Снятая и поставленная заново отметка А ставит его последним.
        await _openFromHome(tester, row: 0, intention: _walk);
        await _toggleMark(tester, null);
        expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
        await _toggleMark(tester, null);
        await _closeTop(tester, IntentionDetailsPage);
        await _expectHome(tester, [b, c, a]);

        // Отметка архивированного Г проявляется последней только после его
        // восстановления.
        await _select(tester, AppDestination.intentionGraph);
        await _expectRows(tester, IntentionCatalogPage, [
          ('Плавать', false),
        ], l10n);
        await _openFromCatalog(tester, row: 0, intention: _swim);
        await _toggleMark(tester, null);
        await _closeTop(tester, IntentionDetailsPage);
        await _select(tester, AppDestination.home);
        await _expectHome(tester, [b, c, a]);
        await _select(tester, AppDestination.intentionGraph);
        await _expectRows(tester, IntentionCatalogPage, [
          ('Плавать', true),
        ], l10n);
        await _openFromCatalog(tester, row: 0, intention: _swim);
        await _restore(tester);
        await _closeTop(tester, IntentionDetailsPage);
        await _select(tester, AppDestination.home);
        await _expectHome(tester, [b, c, a, d]);

        // Переименование и изменение готовности обновляют строку без
        // изменения порядка.
        await _openFromHome(tester, row: 1, intention: _otherWalk);
        await _rename(tester, 'Гулять вечером');
        await _enableReadiness(tester);
        await _closeTop(tester, IntentionDetailsPage);
        final renamed = _homeRow(
          l10n,
          _otherWalk,
          'Гулять вечером',
          ready: true,
          relations: 1,
        );
        await _expectHome(tester, [b, renamed, a, d]);

        // Физическое удаление убирает строку.
        await _openFromHome(tester, row: 3, intention: _swim);
        await _delete(tester);
        _expectHomeRoot(tester, app);
        await _expectHome(tester, [b, renamed, a]);

        // Новая долговременная связь меняет число активных связей строки.
        await _openFromHome(tester, row: 0, intention: _read);
        await _createNeedRelation(tester, relatedTitle: 'Спать');
        await _closeTop(tester, IntentionDetailsPage);
        await _expectHome(tester, [
          _homeRow(l10n, _read, 'Читать', ready: true, relations: 1),
          renamed,
          a,
        ]);
        expect(storedFavoriteMarks(app.raw), [
          (tagFixtureId(_read), 2),
          (tagFixtureId(_otherWalk), 3),
          (tagFixtureId(_walk), 4),
        ]);

        // Каталог по-прежнему показывает отметку звездой в своём порядке.
        await _select(tester, AppDestination.intentionGraph);
        await _selectScope(tester, l10n.catalogScopeActive);
        await _expectRows(tester, IntentionCatalogPage, [
          ('Спать', false),
          ('Бегать', false),
          ('Читать', true),
          ('Гулять вечером', true),
          ('Гулять', true),
        ], l10n);
        expect(find.byKey(_message), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'обновление списка не сбрасывает позицию прокрутки Главной на $code',
      (tester) async {
        final harness = await _harness(tester, locale);
        final app = await _App.start(tester, locale, harness, _seedLongList);
        final l10n = app.l10n;
        await _until(tester, find.byType(HomeIntentionRow));
        _homePosition(tester).jumpTo(500);
        await tester.pumpAndSettle();
        expect(_homePosition(tester).pixels, 500);

        // Строки, с которыми работает сценарий, видны без прокрутки.
        await _openFromHome(
          tester,
          row: _shownHomeTitles(tester).indexOf(_longTitle(10)),
          intention: _longFavorite(10),
        );
        await _rename(tester, 'Избранное 10 вечером');
        await _closeTop(tester, IntentionDetailsPage);
        await _waitFor(
          tester,
          () => _shownHomeTitles(tester).contains('Избранное 10 вечером'),
        );
        await tester.pumpAndSettle();
        expect(_homePosition(tester).pixels, 500);
        expect(_neighbours(tester, 'Избранное 10 вечером'), (
          _longTitle(9),
          _longTitle(11),
        ));

        await _openFromHome(
          tester,
          row: _shownHomeTitles(tester).indexOf(_longTitle(12)),
          intention: _longFavorite(12),
        );
        await _archive(tester);
        await _closeTop(tester, IntentionDetailsPage);
        await _waitFor(
          tester,
          () => !_shownHomeTitles(tester).contains(_longTitle(12)),
        );
        await tester.pumpAndSettle();
        expect(_homePosition(tester).pixels, 500);
        expect(_neighbours(tester, _longTitle(11)), (
          'Избранное 10 вечером',
          _longTitle(13),
        ));

        // Восстановление на странице, открытой из каталога, возвращает
        // строку на место, а Главная остаётся в прежней позиции.
        await _select(tester, AppDestination.intentionGraph);
        await _selectScope(tester, l10n.catalogScopeArchived);
        await _expectRows(tester, IntentionCatalogPage, [
          (_longTitle(12), true),
        ], l10n);
        await _openFromCatalog(tester, row: 0, intention: _longFavorite(12));
        await _restore(tester);
        await _closeTop(tester, IntentionDetailsPage);
        await _select(tester, AppDestination.home);
        await _waitFor(
          tester,
          () => _shownHomeTitles(tester).contains(_longTitle(12)),
        );
        await tester.pumpAndSettle();
        expect(_homePosition(tester).pixels, 500);
        expect(_neighbours(tester, _longTitle(12)), (
          _longTitle(11),
          _longTitle(13),
        ));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

/// Запуск приложения на постоянном хранилище [LocalDatabaseHarness].
final class _App {
  _App(this.runtime, this.raw, this.router, this.l10n);

  final AppRuntime runtime;
  final sqlite.Database raw;
  final AppRouter router;
  final AppLocalizations l10n;

  /// Готовит хранилище, засевает его [seed] и ждёт полученную Главную.
  static Future<_App> start(
    WidgetTester tester,
    Locale locale,
    LocalDatabaseHarness harness,
    void Function(sqlite.Database database) seed,
  ) async {
    late sqlite.Database raw;
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () => openFileBackedLocalDatabase(
        harness.databaseFile,
        setup: (database) => raw = database,
      ),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    seed(raw);
    await tester.pumpWidget(MainApp(runtime: runtime));
    final l10n = lookupAppLocalizations(locale);
    await _until(tester, find.byType(HomePage));
    await _waitFor(
      tester,
      () => find.text(l10n.homeLoading).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    return _App(runtime, raw, ready.container.read(appRouterProvider), l10n);
  }
}

Future<LocalDatabaseHarness> _harness(
  WidgetTester tester,
  Locale locale,
) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  addTearDown(harness.dispose);
  return harness;
}

/// Шесть намерений, связи «Бегать» и его невыполненный дневной выбор;
/// [favorites] отмечены в этом порядке.
void _seedGraph(sqlite.Database database, {List<int> favorites = const []}) {
  for (final (number, title, ready, archived) in [
    (_walk, 'Гулять', 1, 0),
    (_otherWalk, 'Гулять', 0, 0),
    (_read, 'Читать', 1, 0),
    (_swim, 'Плавать', 1, 1),
    (_run, 'Бегать', 1, 0),
    (_sleep, 'Спать', 1, 0),
  ]) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, ready, archived, number, number],
    );
  }
  for (final (number, related) in [
    (_pathRelation, _sleep),
    (_freeRelation, _otherWalk),
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

/// Длинный список избранных намерений без связей.
void _seedLongList(sqlite.Database database) {
  for (var number = 1; number <= _longFavoriteCount; number++) {
    final intention = _longFavorite(number);
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(intention), _longTitle(number), 1, 0, number, number],
    );
    storeFavoriteMark(
      database,
      intentionId: tagFixtureId(intention),
      position: number,
    );
  }
}

int _longFavorite(int number) => _firstLongFavorite + number - 1;

String _longTitle(int number) =>
    'Избранное ${number.toString().padLeft(2, '0')}';

/// Проверяет звёзды отмеченных А, Б и В в каталоге намерений и в поисках
/// действия, исходного намерения и участника связи. Каждая выдача сохраняет
/// собственный порядок, а не порядок избранных «Гулять», «Читать», «Гулять».
Future<void> _expectSearches(WidgetTester tester, _App app) async {
  final l10n = app.l10n;
  await _expectRows(tester, IntentionCatalogPage, [
    ('Спать', false),
    ('Бегать', false),
    ('Читать', true),
    ('Гулять', true),
    ('Гулять', true),
  ], l10n);

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
  await _expectRows(tester, DailyChoiceActionPickerPage, [
    ('Спать', false),
    ('Бегать', false),
    ('Читать', true),
    ('Гулять', true),
  ], l10n);
  await _tap(tester, find.byKey(const ValueKey('daily-choice-action-cancel')));
  await _gone(tester, DailyChoiceActionPickerPage);

  // Поиск исходного намерения: активные независимо от готовности.
  await _tap(
    tester,
    find.byKey(const ValueKey('daily-choice-replace-top-down')),
  );
  await _until(tester, find.byType(DailyChoiceSourcePickerPage));
  await _expectRows(tester, DailyChoiceSourcePickerPage, [
    ('Спать', false),
    ('Бегать', false),
    ('Читать', true),
    ('Гулять', true),
    ('Гулять', true),
  ], l10n);
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
  await _expectRows(tester, RelationParticipantPickerPage, [
    ('Спать', false),
    ('Читать', true),
    ('Гулять', true),
    ('Гулять', true),
  ], l10n);
  await _tap(tester, find.byKey(const ValueKey('participant-picker-cancel')));
  await _gone(tester, RelationParticipantPickerPage);
  await _popToRoot(tester, app);
  expect(find.byType(IntentionCatalogPage), findsOneWidget);
}

/// Строка Главной так, как она показана: намерение, название, готовность к
/// действию и число активных связей.
typedef _HomeRow = (
  int intention,
  String title,
  String readiness,
  String relations,
);

_HomeRow _homeRow(
  AppLocalizations l10n,
  int intention,
  String title, {
  required bool ready,
  required int relations,
}) => (
  intention,
  title,
  ready ? l10n.catalogReady : l10n.catalogNotReady,
  l10n.intentionActiveRelationCount(relations),
);

final _homeRows = find.descendant(
  of: find.byType(HomePage),
  matching: find.byType(HomeIntentionRow),
);

/// Построенные строки Главной в порядке списка. Намерение строки читается из
/// её данных, остальное — из показанных подписей.
List<_HomeRow> _shownHomeRows(WidgetTester tester) => [
  for (var index = 0; index < _homeRows.evaluate().length; index++)
    switch ([
      for (final text in tester.widgetList<Text>(
        find.descendant(of: _homeRows.at(index), matching: find.byType(Text)),
      ))
        text.data,
    ]) {
      [final String title, final String readiness, final String relations] => (
        _intentionNumber(tester.widget<HomeIntentionRow>(_homeRows.at(index))),
        title,
        readiness,
        relations,
      ),
      final texts => fail('Недопустимое содержимое строки Главной: $texts'),
    },
];

List<String> _shownHomeTitles(WidgetTester tester) => [
  for (final (_, title, _, _) in _shownHomeRows(tester)) title,
];

/// Соседние строки строки [title] в списке Главной.
(String, String) _neighbours(WidgetTester tester, String title) {
  final titles = _shownHomeTitles(tester);
  final index = titles.indexOf(title);
  expect(index, greaterThan(0), reason: title);
  expect(index, lessThan(titles.length - 1), reason: title);
  return (titles[index - 1], titles[index + 1]);
}

int _intentionNumber(HomeIntentionRow row) {
  final id = row.row.id.toCanonicalString();
  final number = int.parse(id.substring(id.length - 12), radix: 16);
  expect(tagFixtureId(number), id);
  return number;
}

/// Дожидается, пока Главная покажет ровно [expected], и проверяет, что строки
/// не несут звезды и не предлагают действий с отметкой.
Future<void> _expectHome(WidgetTester tester, List<_HomeRow> expected) async {
  await _pumpUntil(tester, () => listEquals(_shownHomeRows(tester), expected));
  await tester.pumpAndSettle();
  expect(_shownHomeRows(tester), expected);
  expect(
    find.descendant(of: _homeRows, matching: find.byIcon(Icons.star)),
    findsNothing,
  );
  expect(
    find.descendant(
      of: _homeRows,
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton || widget is ButtonStyleButton,
      ),
    ),
    findsNothing,
  );
  for (final view in tester.widgetList<IntentionSummaryView>(
    find.descendant(of: _homeRows, matching: find.byType(IntentionSummaryView)),
  )) {
    expect(view.confirmedFavoriteMark, isNull);
    expect(view.confirmedTags, isNull);
  }
}

/// Открыта Главная: страниц поверх нет, панель видна, выбран пункт
/// «Главная».
void _expectHomeRoot(WidgetTester tester, _App app) {
  expect(app.router.canPop(), isFalse);
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

/// Открывает страницу намерения строкой Главной с номером [row] и
/// подтверждает, что открыто именно намерение [intention], а страница
/// закрывает панель.
///
/// Строка уже видна, поэтому нажимается без доведения до видимости: оно
/// прокрутило бы Главную и изменило проверяемую позицию.
Future<void> _openFromHome(
  WidgetTester tester, {
  required int row,
  required int intention,
}) async {
  await _until(tester, _homeRows.at(row));
  await tester.pumpAndSettle();
  await tester.tap(_homeRows.at(row));
  await tester.pump();
  await _expectDetails(tester, intention);
}

/// Открывает страницу намерения строкой каталога с номером [row].
Future<void> _openFromCatalog(
  WidgetTester tester, {
  required int row,
  required int intention,
}) async {
  await _tap(tester, _rows(IntentionCatalogPage).at(row));
  await _expectDetails(tester, intention);
}

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
  expect(find.byType(AppNavigationBar), findsOneWidget);
  for (final page in _rootPages.values) {
    expect(find.byType(page), findsNothing);
  }
}

String? _controlTooltip(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(_favoriteControl)).tooltip;

/// Нажимает управление отметкой и дожидается ровно одного сообщения общей
/// поверхности; [message] — его ожидаемый текст, если он проверяется.
Future<void> _toggleMark(WidgetTester tester, String? message) async {
  final before = _controlTooltip(tester);
  await _tap(tester, find.byKey(_favoriteControl));
  await _waitFor(tester, () => _controlTooltip(tester) != before);
  await _acceptMessage(tester, message);
}

Future<void> _archive(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-archive')));
  await _until(tester, find.byKey(const ValueKey('intention-details-restore')));
  await _acceptMessage(tester, null);
}

Future<void> _restore(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-restore')));
  await _until(tester, find.byKey(const ValueKey('intention-details-archive')));
  await _acceptMessage(tester, null);
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
  await _acceptMessage(tester, null);
}

Future<void> _enableReadiness(WidgetTester tester) async {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(IntentionDetailsPage)),
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-details-enable-readiness')),
  );
  await _tap(
    tester,
    find.widgetWithText(FilledButton, l10n.detailsConfirmReadinessAction),
  );
  await _until(
    tester,
    find.byKey(const ValueKey('intention-details-disable-readiness')),
  );
  await _acceptMessage(tester, null);
}

/// Удаляет намерение открытой страницы; страница закрывается сама, а
/// результат предъявляется на корневой странице.
Future<void> _delete(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-delete')));
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-details-confirm-delete')),
  );
  await _gone(tester, IntentionDetailsPage);
  await _acceptMessage(tester, null);
}

Future<void> _createNeedRelation(
  WidgetTester tester, {
  required String relatedTitle,
}) async {
  await _tap(
    tester,
    find.byKey(const ValueKey('relation-neighborhood-create-relation')),
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('relation-editor-select-related')),
  );
  await _until(tester, find.byType(RelationParticipantPickerPage));
  await _tap(
    tester,
    find.descendant(
      of: find.byType(RelationParticipantPickerPage),
      matching: find.text(relatedTitle),
    ),
  );
  await _gone(tester, RelationParticipantPickerPage);
  await _tap(tester, find.byKey(const ValueKey('relation-editor-type-need')));
  await _tap(tester, find.byKey(const ValueKey('relation-editor-priority-p2')));
  await tester.enterText(
    find.byKey(const ValueKey('relation-editor-description')),
    'Перед сном',
  );
  final submit = find.byKey(const ValueKey('relation-editor-submit'));
  await _tap(tester, submit);
  await _waitFor(tester, () => submit.evaluate().isEmpty);
  await _until(tester, find.byKey(const ValueKey('relation-details-phrase')));
  expect(find.text('Перед сном'), findsOneWidget);
  await _closeTop(tester, RelationDetailsPage);
  await _until(tester, find.byKey(_favoriteControl));
  await _acceptMessage(tester, null);
}

/// Дожидается ровно одного сообщения общей поверхности о подтверждённой
/// операции и закрывает его; [message] — ожидаемый текст, если он
/// проверяется.
Future<void> _acceptMessage(WidgetTester tester, String? message) async {
  await _until(tester, find.byKey(_message));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsOneWidget);
  if (message != null) expect(find.text(message), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  // Предъявленный результат не показывается повторно.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsNothing);
}

Finder _rows(Type page) => find.descendant(
  of: find.byType(page),
  matching: find.byType(IntentionSummaryView),
);

/// Строка результата поиска: название и наличие звезды так, как они
/// показаны.
typedef _Row = (String title, bool star);

/// Видимые результаты поиска страницы в порядке выдачи. Звезда читается из
/// показанного значка и обязана нести локализованное название отметки.
List<_Row> _shownRows(WidgetTester tester, Type page, AppLocalizations l10n) {
  final rows = _rows(page);
  return [
    for (var index = 0; index < rows.evaluate().length; index++)
      (
        tester.widget<IntentionSummaryView>(rows.at(index)).title,
        switch (tester
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
      ),
  ];
}

Future<void> _expectRows(
  WidgetTester tester,
  Type page,
  List<_Row> expected,
  AppLocalizations l10n,
) async {
  await _pumpUntil(
    tester,
    () => listEquals(_shownRows(tester, page, l10n), expected),
  );
  await tester.pumpAndSettle();
  expect(_shownRows(tester, page, l10n), expected);
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

ScrollPosition _homePosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(
              const PageStorageKey<String>('home-favorite-intentions'),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _popToRoot(WidgetTester tester, _App app) async {
  while (app.router.canPop()) {
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
  }
}

/// Закрывает верхнюю страницу системным действием «назад».
Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _gone(tester, page);
}

Future<void> _gone(WidgetTester tester, Type page) async {
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
