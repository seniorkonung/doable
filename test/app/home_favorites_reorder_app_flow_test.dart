import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart'
    as daily_page;
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as catalog_page;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';

// Названия намерений — данные человека: они одинаковы в обеих локалях.

/// Избранные намерения «Избранное 01» … «Избранное 40» на местах 1…40:
/// список Главной длиннее экрана.
const _longFavoriteCount = 40;

/// «Бегать» и «Спать» длинного списка — неизбранные участники связи и
/// дневных выборов каталога дневных выборов.
const _longRun = 41;
const _longSleep = 42;

/// «Гулять», готово к действию, с тегом «Здоровье».
const _walk = 1;

/// «Гулять», не готово к действию, — тёзка [_walk] с одной активной связью.
const _otherWalk = 2;

/// «Читать», готово к действию.
const _read = 3;

/// «Плавать», архивированное готовое действие — скрытое избранное намерение.
const _swim = 4;

/// «Бегать» и «Спать» — активные готовые намерения без отметки.
const _run = 5;
const _sleep = 6;

/// Связь «Бегать» → «Спать» — путь невыполненного дневного выбора.
const _pathRelation = 101;

/// Связь «Бегать» → тёзка «Гулять» вне дневных путей: её связанного
/// участника можно заменить.
const _freeRelation = 103;

/// Невыполненный дневной выбор, из замены пути которого открываются поиски
/// действия и исходного намерения.
const _openChoice = 201;

/// Тег «Здоровье».
const _healthTag = 301;

/// Намерение так, как его показывает строка Главной.
typedef _Intention = ({String title, bool isReady, int relations});

const _intentions = <int, _Intention>{
  _walk: (title: 'Гулять', isReady: true, relations: 0),
  _otherWalk: (title: 'Гулять', isReady: false, relations: 1),
  _read: (title: 'Читать', isReady: true, relations: 0),
  _swim: (title: 'Плавать', isReady: true, relations: 0),
  _run: (title: 'Бегать', isReady: true, relations: 2),
  _sleep: (title: 'Спать', isReady: true, relations: 1),
};

const _message = ValueKey('graph-operation-message');
const _favoriteControl = ValueKey('intention-details-favorite-mark');

/// Позиция прокрутки Главной, которую сценарий задаёт и ожидает сохранённой.
const _homeOffset = 500.0;

/// Куда человек уходит с Главной, пока принятая перестановка выполняется.
enum _Departure {
  dailyChoices(
    'после перехода к дневным выборам',
    daily_page.DailyChoiceCatalogPage,
  ),
  intentionGraph(
    'после перехода к графу намерений',
    catalog_page.IntentionCatalogPage,
  ),
  pageAbove(
    'после открытия страницы намерения поверх Главной и принятого на ней '
    'переименования',
    IntentionDetailsPage,
  );

  const _Departure(this.description, this.page);

  final String description;

  /// Страница, на общей поверхности которой предъявляется отказ.
  final Type page;
}

/// Поиск намерений, открытый поверх Главной во время перестановки.
enum _Search {
  action(DailyChoiceActionPickerPage),
  source(DailyChoiceSourcePickerPage),
  participant(RelationParticipantPickerPage);

  const _Search(this.page);

  final Type page;
}

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    for (final departure in _Departure.values) {
      testWidgets('принятая перестановка ${departure.description} сначала '
          'получает однократный отказ записи на текущей общей поверхности, а '
          'затем сохраняется без сообщения; Главная согласована, а её '
          'прокрутка и параметры каталогов сохранены на $code', (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await _App.start(tester, locale, _seedLongList);
        final l10n = app.l10n;

        // Параметры обоих каталогов и прокрутка Главной.
        await openIntentionGraph(tester, waitFor: _until);
        await tester.enterText(
          find.byKey(const ValueKey('catalog-filter-field')),
          'Бегать',
        );
        await _until(tester, find.text(l10n.catalogTotalCount(1)));
        await tester.pumpAndSettle();
        final graph = _intentionGraphView(tester);
        await openDailyChoices(tester, tap: _tap);
        await _until(tester, find.byKey(const ValueKey('daily-choice-row-1')));
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-completion-filter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.dailyChoiceCatalogIncomplete).last);
        await _until(tester, find.text(l10n.dailyChoiceCatalogTotalCount(1)));
        await tester.pumpAndSettle();
        final dailyChoices = _dailyChoicesView(tester);
        await openHome(tester, waitFor: _until);
        await tester.pumpAndSettle();
        _homePosition(tester).jumpTo(_homeOffset);
        await tester.pumpAndSettle();
        final initial = [
          for (var number = 1; number <= _longFavoriteCount; number++) number,
        ];
        await _expectConfirmedHome(tester, app, initial);
        // Строки, с которыми работает сценарий, видны без прокрутки.
        for (final number in [12, 15, 20]) {
          expect(_homeRow(number).hitTestable(), findsOneWidget);
        }

        // Первая перестановка: «Избранное 12» — на одно место выше. Запись
        // отказывает уже после ухода с Главной.
        app.repository.holdNextMove();
        app.faults.failNextPlaceWrite();
        _moveBySemantics(
          tester,
          _rowLabel(l10n, _longTitle(12)),
          (actions) => actions.reorderItemUp,
        );
        await _waitFor(tester, () => app.repository.isHoldingMove);
        await tester.pumpAndSettle();
        _expectSaving(tester, app, [
          for (var number = 1; number <= 10; number++) number,
          12,
          11,
          for (var number = 13; number <= _longFavoriteCount; number++) number,
        ], moved: 12);

        await _depart(tester, departure);
        const renamed = 'Избранное 20 вечером';
        if (departure == _Departure.pageAbove) {
          // Выполняющаяся перестановка не мешает принять операцию намерения.
          // Её результат публикуется в порядке принятия — после результата
          // перестановки.
          await _submitRename(tester, renamed);
          await _until(tester, find.text(l10n.detailsOperationRunning));
          expect(app.repository.isHoldingMove, isTrue);
        }
        app.repository.releaseMove();
        final failure = find.text(l10n.favoriteOrderUnavailable);
        await _until(tester, failure);
        await tester.pumpAndSettle();
        expect(find.byKey(_message), findsOneWidget);
        expect(
          find.descendant(of: find.byType(departure.page), matching: failure),
          findsOneWidget,
        );
        expect(storedFavoriteMarks(app.raw), _places(initial));
        if (departure == _Departure.pageAbove) {
          await _hideMessage(tester);
          await _until(
            tester,
            find.descendant(
              of: find.byKey(_message),
              matching: find.textContaining(renamed),
            ),
          );
          expect(failure, findsNothing);
          expect(
            find.descendant(
              of: find.byType(IntentionDetailsPage),
              matching: find.text(renamed),
            ),
            findsOneWidget,
          );
        }
        await _closeMessage(tester);

        // Отказ не предъявляется повторно при возвращении на Главную, а
        // Главная показывает последний подтверждённый порядок.
        await _returnHome(tester, departure);
        await _expectConfirmedHome(tester, app, initial);
        expect(_homePosition(tester).pixels, _homeOffset);
        if (departure == _Departure.pageAbove) {
          expect(_homeTitle(app, 20), renamed);
        }

        // Вторая перестановка: «Избранное 15» — на одно место ниже.
        final reordered = [
          for (var number = 1; number <= 14; number++) number,
          16,
          15,
          for (var number = 17; number <= _longFavoriteCount; number++) number,
        ];
        app.repository.holdNextMove();
        _moveBySemantics(
          tester,
          _rowLabel(l10n, _longTitle(15)),
          (actions) => actions.reorderItemDown,
        );
        await _waitFor(tester, () => app.repository.isHoldingMove);
        await tester.pumpAndSettle();
        _expectSaving(tester, app, reordered, moved: 15);

        await _depart(tester, departure);
        app.repository.releaseMove();
        await _waitFor(
          tester,
          () => listEquals(storedFavoriteMarks(app.raw), _places(reordered)),
        );
        // Главная согласуется, пока закрыта, а успех сообщения не получает.
        await _waitFor(tester, () => _isConfirmed(app, reordered));
        await _settle(tester);
        expect(_builtMessages, findsNothing);

        await _returnHome(tester, departure);
        await _expectConfirmedHome(tester, app, reordered);
        expect(_homePosition(tester).pixels, _homeOffset);
        expect(app.repository.moves, 2);

        // Параметры каталогов не изменились.
        await openIntentionGraph(tester, waitFor: _until);
        await tester.pumpAndSettle();
        expect(_intentionGraphView(tester), graph);
        await openDailyChoices(tester, tap: _tap);
        await _until(tester, find.byType(daily_page.DailyChoiceCatalogPage));
        await tester.pumpAndSettle();
        expect(_dailyChoicesView(tester), dailyChoices);
        expect(_builtMessages, findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }

    testWidgets('снятие отметки опорного намерения, принятое раньше '
        'перестановки, даёт ей реальный конфликт: после результата снятия '
        'отказ перестановки предъявляется один раз, а Главная приходит к '
        'актуальному списку; повторная перестановка во время выполнения не '
        'принимается на $code', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _App.start(
        tester,
        locale,
        (database) => _seedGraph(
          database,
          favorites: const [_walk, _read, _otherWalk, _sleep],
        ),
      );
      final l10n = app.l10n;
      await _expectConfirmedHome(tester, app, const [
        _walk,
        _read,
        _otherWalk,
        _sleep,
      ]);

      // Снятие отметки «Читать» принято и выполняется в хранилище, а
      // страница закрыта до его подтверждения: Главная ещё показывает
      // подтверждённый список с «Читать».
      await _openFromHome(tester, _read);
      app.faults.holdNextUnmarkWrite();
      await _tap(tester, find.byKey(_favoriteControl));
      await _waitFor(tester, () => app.faults.isHoldingUnmarkWrite);
      await _closeTop(tester, IntentionDetailsPage);
      await _expectConfirmedHome(tester, app, const [
        _walk,
        _read,
        _otherWalk,
        _sleep,
      ]);

      // «Спать» ставится жестом сразу после «Читать»: перестановка принята
      // и ждёт в хранилище снятия отметки, принятого раньше.
      await _dragHandle(tester, _sleep, -1);
      await _waitFor(tester, () => app.repository.moves == 1);
      await tester.pumpAndSettle();
      const requested = [_walk, _read, _sleep, _otherWalk];
      _expectSaving(tester, app, requested, moved: _sleep);

      // Ручки недоступны: перетаскивание другой строки ничего не отправляет.
      await _dragHandle(tester, _walk, 1);
      await tester.pumpAndSettle();
      _expectSaving(tester, app, requested, moved: _sleep);
      expect(app.repository.moves, 1);
      expect(
        storedFavoriteMarks(app.raw),
        _places(const [_walk, _read, _otherWalk, _sleep]),
      );

      // Сначала предъявляется подтверждённое снятие отметки.
      app.faults.releaseUnmarkWrite();
      await _until(
        tester,
        find.descendant(
          of: find.byKey(_message),
          matching: find.textContaining('Читать'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_message), findsOneWidget);
      await _hideMessage(tester);

      // Затем — один отказ перестановки на общей поверхности Главной.
      final conflict = find.text(l10n.favoriteOrderConflict);
      await _until(tester, conflict);
      await tester.pumpAndSettle();
      expect(find.byKey(_message), findsOneWidget);
      expect(
        find.descendant(of: find.byType(HomePage), matching: conflict),
        findsOneWidget,
      );
      await _expectConfirmedHome(tester, app, const [
        _walk,
        _otherWalk,
        _sleep,
      ], allowMessage: true);
      expect(storedFavoriteMarks(app.raw), [
        (tagFixtureId(_walk), 1),
        (tagFixtureId(_otherWalk), 3),
        (tagFixtureId(_sleep), 4),
      ]);
      await _closeMessage(tester);

      // Отказ не повторяется ни на других пунктах, ни при возвращении.
      await openIntentionGraph(tester, waitFor: _until);
      await _settle(tester);
      expect(_builtMessages, findsNothing);
      await openHome(tester, waitFor: _until);
      await _expectConfirmedHome(tester, app, const [
        _walk,
        _otherWalk,
        _sleep,
      ]);
      expect(app.repository.moves, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('подтверждённая перестановка не меняет состав, порядок, '
        'количество и отметки открытых каталога намерений и трёх поисков, а '
        'намерения, их время, связи, теги и дневные выборы сохраняются на '
        '$code', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _App.start(
        tester,
        locale,
        (database) => _seedGraph(
          database,
          favorites: const [_walk, _read, _otherWalk, _swim],
        ),
      );
      final l10n = app.l10n;
      final stored = _storedGraph(app.raw);
      await _expectConfirmedHome(tester, app, const [_walk, _read, _otherWalk]);

      // Каталог намерений уже открыт, когда перестановка подтверждается.
      await openIntentionGraph(
        tester,
        waitFor: _until,
        content: find.text(l10n.catalogTotalCount(5)),
      );
      await tester.pumpAndSettle();
      final catalog = _searchView(
        tester,
        catalog_page.IntentionCatalogPage,
        l10n,
      );
      expect(catalog['строки'], [
        ('Спать', false),
        ('Бегать', false),
        ('Читать', true),
        ('Гулять', true),
        ('Гулять', true),
      ]);
      await openHome(tester, waitFor: _until);
      await _moveWhileOpen(
        tester,
        app,
        moved: _otherWalk,
        action: (actions) => actions.reorderItemToStart,
        order: const [_otherWalk, _walk, _read, _swim],
        open: () => openIntentionGraph(tester, waitFor: _until),
        page: catalog_page.IntentionCatalogPage,
        expected: catalog,
      );
      await openHome(tester, waitFor: _until);
      await _expectConfirmedHome(tester, app, const [_otherWalk, _walk, _read]);

      // Каждый поиск открыт поверх Главной, когда перестановка
      // подтверждается.
      for (final (search, moved, action, order, rows) in [
        (
          _Search.action,
          _read,
          (WidgetsLocalizations actions) => actions.reorderItemUp,
          const [_otherWalk, _read, _walk, _swim],
          const [
            ('Спать', false),
            ('Бегать', false),
            ('Читать', true),
            ('Гулять', true),
          ],
        ),
        (
          _Search.source,
          _otherWalk,
          (WidgetsLocalizations actions) => actions.reorderItemDown,
          const [_read, _otherWalk, _walk, _swim],
          const [
            ('Спать', false),
            ('Бегать', false),
            ('Читать', true),
            ('Гулять', true),
            ('Гулять', true),
          ],
        ),
        (
          _Search.participant,
          _walk,
          (WidgetsLocalizations actions) => actions.reorderItemToStart,
          const [_walk, _read, _otherWalk, _swim],
          const [
            ('Спать', false),
            ('Читать', true),
            ('Гулять', true),
            ('Гулять', true),
          ],
        ),
      ]) {
        await _moveWhileOpen(
          tester,
          app,
          moved: moved,
          action: action,
          order: order,
          open: () => _openSearch(tester, app, search),
          page: search.page,
          expectedRows: rows,
        );
        await _popToRoot(tester, app);
        await _expectConfirmedHome(tester, app, [
          for (final intention in order)
            if (intention != _swim) intention,
        ]);
      }

      // Перестановка меняет только порядок избранных: намерения с их
      // временем, связи с приоритетами, дневные выборы, теги и их
      // назначения сохранены.
      expect(_storedGraph(app.raw), stored);
      expect(app.repository.moves, 4);
      expect(_builtMessages, findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

/// Запущенное приложение на постоянном хранилище [LocalDatabaseHarness] с
/// удерживаемыми перестановками и управляемыми записями избранного.
final class _App {
  _App(this.raw, this.container, this.repository, this.faults, this.l10n);

  final sqlite.Database raw;
  final ProviderContainer container;
  final _HeldMoves repository;
  final _FavoriteWriteFaults faults;
  final AppLocalizations l10n;

  AppRouter get router => container.read(appRouterProvider);

  HomeState get home => container.read(homeViewModelProvider);

  /// Готовит хранилище, засевает его [seed] и ждёт полученную Главную.
  static Future<_App> start(
    WidgetTester tester,
    Locale locale,
    void Function(sqlite.Database database) seed,
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
    late sqlite.Database raw;
    late _HeldMoves repository;
    final faults = _FavoriteWriteFaults();
    final diagnostics = InMemoryDiagnosticsSink();
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(
          harness.databaseFile,
          setup: (database) => raw = database,
        ),
        faults,
      ),
      diagnosticsSink: diagnostics,
      repositoryFactory: (database) => repository = _HeldMoves(
        DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.now().toUtc(),
          diagnostics,
          relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
        ),
      ),
    );
    addTearDown(() async {
      repository.releaseMove();
      faults.releaseUnmarkWrite();
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
    return _App(raw, ready.container, repository, faults, l10n);
  }
}

/// Длинный список избранных намерений без связей, два неизбранных намерения
/// со связью и их дневные выборы: невыполненный и выполненный.
void _seedLongList(sqlite.Database database) {
  for (var number = 1; number <= _longFavoriteCount; number++) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), _longTitle(number), 1, 0, number, number],
    );
    storeFavoriteMark(
      database,
      intentionId: tagFixtureId(number),
      position: number,
    );
  }
  for (final (number, title) in [(_longRun, 'Бегать'), (_longSleep, 'Спать')]) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, 1, 0, number, number],
    );
  }
  database.execute(
    'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
    [
      tagFixtureId(_pathRelation),
      tagFixtureId(_longRun),
      tagFixtureId(_longSleep),
      'need',
      2,
      0,
    ],
  );
  for (final (number, date, completed) in [
    (_openChoice, '2026-09-25', 0),
    (_openChoice + 1, '2026-09-24', 1),
  ]) {
    database.execute(
      'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(_longRun),
        tagFixtureId(_longSleep),
        date,
        completed,
      ],
    );
    database.execute(
      'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
      [
        tagFixtureId(number + 10),
        tagFixtureId(number),
        tagFixtureId(_pathRelation),
      ],
    );
  }
}

String _longTitle(int number) =>
    'Избранное ${number.toString().padLeft(2, '0')}';

/// Шесть намерений, связи «Бегать», его невыполненный дневной выбор и тег
/// «Гулять»; [favorites] отмечены в этом порядке.
void _seedGraph(sqlite.Database database, {required List<int> favorites}) {
  for (final MapEntry(key: number, value: intention) in _intentions.entries) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        intention.title,
        intention.isReady ? 1 : 0,
        number == _swim ? 1 : 0,
        number,
        number,
      ],
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
  database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagFixtureId(_healthTag),
    'Здоровье',
  ]);
  database.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(_healthTag), tagFixtureId(_walk)],
  );
  for (final (index, intention) in favorites.indexed) {
    storeFavoriteMark(
      database,
      intentionId: tagFixtureId(intention),
      position: index + 1,
    );
  }
}

/// Сохранённые данные графа, которые перестановка не должна менять:
/// намерения с их временем, связи, дневные выборы, теги и их назначения.
Map<String, List<List<Object?>>> _storedGraph(sqlite.Database database) => {
  ...retainedTagFixtureGraph(database),
  for (final table in ['tags', 'tag_assignments'])
    table: database
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

/// Сохранённые места намерений [order] после перезаписи порядка: 1, 2, …
List<(String, int)> _places(List<int> order) => [
  for (final (index, intention) in order.indexed)
    (tagFixtureId(intention), index + 1),
];

/// Удерживает перестановку, пока сценарий уходит со страницы или открывает
/// поиск, выполняет на Главной перемещение [moved] системным действием
/// [action] и после ухода [open] на страницу [page] отпускает запись.
///
/// Подтверждённый порядок [order] — весь единый порядок, включая скрытые
/// архивированные намерения. Страница [page] после подтверждения показывает
/// то же, что до него: [expected] целиком либо, если он не задан, —
/// строки [expectedRows].
Future<void> _moveWhileOpen(
  WidgetTester tester,
  _App app, {
  required int moved,
  required String Function(WidgetsLocalizations actions) action,
  required List<int> order,
  required Future<void> Function() open,
  required Type page,
  _SearchView? expected,
  List<_Row>? expectedRows,
}) async {
  final moves = app.repository.moves;
  app.repository.holdNextMove();
  _moveBySemantics(tester, _homeRowLabel(app.l10n, moved), action);
  await _waitFor(tester, () => app.repository.isHoldingMove);
  await open();
  await _until(tester, find.byType(IntentionSummaryView));
  await tester.pumpAndSettle();
  final before = expected ?? _searchView(tester, page, app.l10n);
  if (expectedRows != null) expect(before['строки'], expectedRows);

  app.repository.releaseMove();
  await _waitFor(
    tester,
    () => listEquals(storedFavoriteMarks(app.raw), _places(order)),
  );
  await _settle(tester);
  expect(_searchView(tester, page, app.l10n), before);
  expect(app.repository.moves, moves + 1);
  expect(_builtMessages, findsNothing);
}

/// Открывает поиск [search] поверх Главной так же, как его открывает
/// человек: замена пути дневного выбора либо изменение связи.
Future<void> _openSearch(WidgetTester tester, _App app, _Search search) async {
  switch (search) {
    case _Search.action || _Search.source:
      unawaited(
        app.router.push(
          DailyChoiceDetailsRoute(
            choiceId: (DailyChoiceId.decode(
              tagFixtureId(_openChoice),
            ) as DailyChoiceIdDecodingSuccess).id,
          ),
        ),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-replace-open')),
      );
      await _tap(
        tester,
        find.byKey(
          ValueKey(
            search == _Search.action
                ? 'daily-choice-replace-bottom-up'
                : 'daily-choice-replace-top-down',
          ),
        ),
      );
    case _Search.participant:
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
  }
  await _until(tester, find.byType(search.page));
}

/// Строка результата поиска: название и наличие звезды так, как они
/// показаны.
typedef _Row = (String title, bool star);

/// Выдача поиска так, как её видит человек: строки со звёздами и все тексты
/// страницы, включая количество найденного.
typedef _SearchView = Map<String, Object?>;

_SearchView _searchView(WidgetTester tester, Type page, AppLocalizations l10n) {
  final rows = find.descendant(
    of: find.byType(page),
    matching: find.byType(IntentionSummaryView),
  );
  return {
    'строки': [
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
    ],
    'тексты': _texts(find.byType(page)),
  };
}

/// Тексты страницы в порядке дерева.
List<String?> _texts(Finder page) => [
  for (final text
      in find.descendant(of: page, matching: find.byType(Text)).evaluate())
    (text.widget as Text).data,
];

/// Граф намерений так, как его видит человек: фильтр названия и выдача.
Map<String, Object?> _intentionGraphView(WidgetTester tester) => {
  'фильтр названия': tester
      .widget<TextField>(find.byKey(const ValueKey('catalog-filter-field')))
      .controller!
      .text,
  'тексты': _texts(find.byType(catalog_page.IntentionCatalogPage)),
};

/// Дневные выборы так, как их видит человек: фильтры и выдача.
Map<String, Object?> _dailyChoicesView(WidgetTester tester) => {
  'тексты': _texts(find.byType(daily_page.DailyChoiceCatalogPage)),
};

/// Сообщения общей поверхности в дереве, включая невыбранные вкладки.
final _builtMessages = find.byKey(_message, skipOffstage: false);

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

/// Строка Главной намерения [number].
Finder _homeRow(int number) => find.descendant(
  of: find.byType(HomePage),
  matching: find.byKey(ValueKey(_intentionId(number))),
);

/// Ручка строки Главной намерения [number].
Finder _handle(int number) => find.descendant(
  of: _homeRow(number),
  matching: find.byIcon(Icons.drag_handle),
);

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

/// Построенные строки Главной в порядке, в котором их видит человек.
List<String> _shownHome(WidgetTester tester) {
  final rows = [
    for (final element in find.byType(HomeIntentionRow).evaluate())
      (
        top: (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
        id: (element.widget as HomeIntentionRow).row.id.toCanonicalString(),
      ),
  ]..sort((a, b) => a.top.compareTo(b.top));
  return [for (final row in rows) row.id];
}

/// Построенные строки Главной идут подряд в порядке [expected]: в длинном
/// списке построена только его прокрученная часть.
void _expectShownInOrder(WidgetTester tester, List<int> expected) {
  final ids = [for (final number in expected) tagFixtureId(number)];
  final shown = _shownHome(tester);
  expect(shown, isNotEmpty);
  final start = ids.indexOf(shown.first);
  expect(start, isNot(-1));
  expect(shown, ids.sublist(start, start + shown.length));
}

String _homeTitle(_App app, int number) => switch (app.home) {
  HomeList(:final items) =>
    items.singleWhere((row) => row.id == _intentionId(number)).title,
  final other => fail('Главная не показывает список: $other'),
};

/// Главная показывает подтверждённый цельным снимком список [expected] без
/// принятой перестановки.
bool _isConfirmed(_App app, List<int> expected) => switch (app.home) {
  HomeList(
    reorder: HomeReorderIdle(),
    freshness: HomeFreshnessCurrent(),
    :final items,
  ) =>
    listEquals(
      [for (final row in items) row.id],
      [for (final number in expected) _intentionId(number)],
    ),
  _ => false,
};

/// Дожидается подтверждённого списка [expected] на открытой Главной и
/// проверяет показанные строки: порядок, отсутствие признака сохранения,
/// доступные ручки и, если не разрешено [allowMessage], отсутствие сообщений.
Future<void> _expectConfirmedHome(
  WidgetTester tester,
  _App app,
  List<int> expected, {
  bool allowMessage = false,
}) async {
  await _waitFor(tester, () => _isConfirmed(app, expected));
  await tester.pumpAndSettle();
  _expectShownInOrder(tester, expected);
  expect(find.text(app.l10n.homeReorderSaving), findsNothing);
  expect(
    find.byType(ReorderableDragStartListener),
    findsNWidgets(find.byType(HomeIntentionRow).evaluate().length),
  );
  if (!allowMessage) expect(_builtMessages, findsNothing);
}

/// Принятая перестановка [moved] ещё не подтверждена: Главная показывает
/// запрошенный порядок [requested] с признаком сохранения только у
/// перемещаемой строки, а ручки и действия перемещения недоступны.
void _expectSaving(
  WidgetTester tester,
  _App app,
  List<int> requested, {
  required int moved,
}) {
  final home = app.home;
  expect(home, isA<HomeList>());
  final list = home as HomeList;
  expect(list.reorder, isA<HomeReorderPending>());
  expect(
    [for (final row in list.displayedItems) row.id],
    [for (final number in requested) _intentionId(number)],
  );
  _expectShownInOrder(tester, requested);
  final saving = find.text(app.l10n.homeReorderSaving);
  expect(saving, findsOneWidget);
  expect(
    find.descendant(of: _homeRow(moved), matching: saving),
    findsOneWidget,
  );
  expect(find.byType(ReorderableDragStartListener), findsNothing);
  expect(find.semantics.byAction(SemanticsAction.customAction), findsNothing);
}

/// Узел семантики строки Главной намерения [number] малого графа.
String _homeRowLabel(AppLocalizations l10n, int number) {
  final intention = _intentions[number]!;
  return _rowLabel(
    l10n,
    intention.title,
    isReady: intention.isReady,
    relations: intention.relations,
  );
}

/// Название, готовность и число активных связей строки — так строку
/// объявляет экранный диктор.
String _rowLabel(
  AppLocalizations l10n,
  String title, {
  bool isReady = true,
  int relations = 0,
}) => [
  title,
  isReady ? l10n.catalogReady : l10n.catalogNotReady,
  l10n.intentionActiveRelationCount(relations),
].join('\n');

/// Выполняет у строки Главной, которую экранный диктор объявляет подписью
/// [label], системное действие перемещения на языке интерфейса.
void _moveBySemantics(
  WidgetTester tester,
  String label,
  String Function(WidgetsLocalizations actions) action,
) {
  tester.semantics.customAction(
    find.semantics.byLabel(label),
    CustomSemanticsAction(
      label: action(
        WidgetsLocalizations.of(tester.element(find.byType(HomePage))),
      ),
    ),
  );
}

/// Перетаскивает строку Главной намерения [number] ручкой на [places] мест:
/// вниз при положительном числе, вверх — при отрицательном.
///
/// Перетаскиваемая строка занимает место соседней, когда её край заходит за
/// середину соседней строки, поэтому смещение на три четверти высоты строки
/// на каждое место однозначно задаёт новое место.
Future<void> _dragHandle(WidgetTester tester, int number, int places) async {
  final rowHeight = tester.getSize(_homeRow(number)).height;
  final distance = (places.abs() - 0.25) * rowHeight * places.sign;
  final gesture = await tester.startGesture(tester.getCenter(_handle(number)));
  const steps = 10;
  for (var step = 0; step < steps; step++) {
    await gesture.moveBy(Offset(0, distance / steps));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// Уходит с Главной: выбирает пункт каталога либо открывает поверх Главной
/// страницу «Избранное 20».
Future<void> _depart(WidgetTester tester, _Departure departure) async {
  switch (departure) {
    case _Departure.dailyChoices:
      await openDailyChoices(tester, tap: _tap);
      await _until(tester, find.byType(daily_page.DailyChoiceCatalogPage));
    case _Departure.intentionGraph:
      await openIntentionGraph(tester, waitFor: _until);
    case _Departure.pageAbove:
      // Строка видна, поэтому нажимается без доведения до видимости: оно
      // прокрутило бы Главную и изменило проверяемую позицию.
      await tester.tap(_homeRow(20));
      await tester.pump();
      await _until(tester, find.byKey(_favoriteControl));
  }
  await tester.pumpAndSettle();
}

/// Возвращается на Главную тем же путём, каким с неё ушёл.
Future<void> _returnHome(WidgetTester tester, _Departure departure) async {
  switch (departure) {
    case _Departure.dailyChoices || _Departure.intentionGraph:
      await openHome(tester, waitFor: _until);
    case _Departure.pageAbove:
      await _closeTop(tester, IntentionDetailsPage);
  }
  await tester.pumpAndSettle();
}

Future<void> _openFromHome(WidgetTester tester, int intention) async {
  await _tap(tester, _homeRow(intention));
  await _until(tester, find.byKey(_favoriteControl));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<IntentionDetailsPage>(find.byType(IntentionDetailsPage))
        .intentionId,
    _intentionId(intention),
  );
}

/// Отправляет новое название намерения открытой страницы, не дожидаясь
/// результата операции.
Future<void> _submitRename(WidgetTester tester, String title) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-edit')));
  final field = find.byKey(const ValueKey('intention-details-edit-title'));
  await _until(tester, field);
  await tester.enterText(field, title);
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-details-edit-submit')),
  );
}

/// Закрывает показанное сообщение; следующее может показаться сразу.
Future<void> _hideMessage(WidgetTester tester) async {
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
}

/// Закрывает показанное сообщение и проверяет, что следующего нет:
/// предъявленный результат не показывается повторно.
Future<void> _closeMessage(WidgetTester tester) async {
  await _hideMessage(tester);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(_builtMessages, findsNothing);
}

Future<void> _popToRoot(WidgetTester tester, _App app) async {
  while (app.router.canPop()) {
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
  }
}

/// Закрывает верхнюю страницу системным действием «назад».
Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

/// Даёт хранилищу и кадрам время: запущенное чтение успело бы завершиться.
Future<void> _settle(WidgetTester tester) async {
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

/// Продвигает кадры и реальное время хранилища, пока не выполнится [done].
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
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

/// Управляет записями избранного на уровне хранилища: отказывает ближайшей
/// записи мест перестановки устранимой недоступностью и задерживает
/// ближайшую запись снятия отметки внутри её транзакции.
///
/// Отказ откатывает транзакцию перестановки самим адаптером. Задержанная
/// запись занимает последовательный исполнитель хранилища, поэтому команды,
/// принятые после неё, ждут её завершения, как и при медленной записи.
/// Остальные чтения и записи не затрагиваются.
final class _FavoriteWriteFaults extends LocalDatabaseConnectionObserver {
  var _failNextPlaceWrite = false;
  Completer<void>? _nextUnmarkHold;
  Completer<void>? _heldUnmark;

  void failNextPlaceWrite() => _failNextPlaceWrite = true;

  void holdNextUnmarkWrite() => _nextUnmarkHold = Completer<void>();

  /// Задержанная запись снятия отметки дошла до хранилища и ждёт
  /// [releaseUnmarkWrite].
  bool get isHoldingUnmarkWrite => _heldUnmark != null;

  void releaseUnmarkWrite() {
    final held = _heldUnmark;
    _heldUnmark = null;
    if (held != null && !held.isCompleted) held.complete();
  }

  @override
  FutureOr<void> beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) return null;
    if (_failNextPlaceWrite &&
        statement.statements.any(
          (sql) => sql.startsWith('UPDATE favorite_intentions'),
        )) {
      _failNextPlaceWrite = false;
      throw sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'Управляемый отказ записи мест перестановки',
      );
    }
    final hold = _nextUnmarkHold;
    if (hold != null &&
        statement.statements.any(
          (sql) => sql.startsWith('DELETE FROM favorite_intentions'),
        )) {
      _nextUnmarkHold = null;
      _heldUnmark = hold;
      return hold.future;
    }
    return null;
  }
}

/// Реальный адаптер, который удерживает перестановку до [releaseMove], как
/// медленную запись.
///
/// Удержание происходит до транзакции, поэтому хранилище тем временем
/// выполняет чтения открываемых страниц. Координатор публикует завершения в
/// порядке принятия: результат операции, принятой после перестановки,
/// приходит только после её результата.
final class _HeldMoves implements PersonalGraphRepository {
  _HeldMoves(this._delegate);

  final PersonalGraphRepository _delegate;
  Completer<void>? _gate;

  /// Перестановки, дошедшие до хранилища.
  var moves = 0;

  /// Перестановка принята координатором и ждёт [releaseMove].
  var isHoldingMove = false;

  void holdNextMove() => _gate = Completer<void>();

  void releaseMove() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is MoveFavoriteIntention) {
      moves++;
      final gate = _gate;
      if (gate != null) {
        isHoldingMove = true;
        await gate.future;
        isHoldingMove = false;
        _gate = null;
      }
    }
    return _delegate.execute(command);
  }

  @override
  Future<FavoriteIntentionsResult> getFavoriteIntentions() =>
      _delegate.getFavoriteIntentions();

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => _delegate.getCatalogPage(query);

  @override
  Future<Result<IntentionCatalogReconciliationOutcome>>
  getCatalogReconciliationPortion(IntentionCatalogReconciliationQuery query) =>
      _delegate.getCatalogReconciliationPortion(query);

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => _delegate.getDailyChoiceCatalogPage(query);

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => _delegate.watchIntention(id);

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => _delegate.getRelationCounts(intentionId);

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => _delegate.getRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _delegate.watchRelation(id);

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => _delegate.getSelectedRelations(query);

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => _delegate.watchSelectedRelations(query);

  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => _delegate.getChoicePathSuggestions(query);

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => _delegate.getChoicePathContinuations(query);

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      _delegate.getDailyChoice(id);

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      _delegate.watchDailyChoice(id);

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) =>
      _delegate.getTagCatalog(mode);

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) =>
      _delegate.getTagAssignments(intentionId);

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    IntentionId intentionId,
  ) => _delegate.getTagAssignmentStatus(tagId, intentionId);

  @override
  Future<TaggedIntentionsPageResult> getTaggedIntentionsPage(
    TaggedIntentionsQuery query,
  ) => _delegate.getTaggedIntentionsPage(query);

  @override
  Stream<TagReadResult> watchTag(TagId id) => _delegate.watchTag(id);
}
