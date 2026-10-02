import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';

/// Активное готовое намерение «Гулять», которое человек отмечает.
const _walk = 1;

/// Одноимённое активное намерение без готовности: отметку не получает.
const _otherWalk = 2;
const _read = 3;

/// Архивированное готовое действие выполненного дневного выбора.
const _swim = 4;

/// Связь вне дневных путей: её связанного участника можно заменить.
const _freeRelation = 103;

/// Невыполненный дневной выбор, из замены пути которого открываются поиски
/// действия и исходного намерения.
const _openChoice = 201;

const _favoriteControl = ValueKey('intention-details-favorite-mark');
const _message = ValueKey('graph-operation-message');

/// Строка результата: название и наличие звезды так, как они показаны.
typedef _Row = (String title, bool star);

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets(
      'отметка активного намерения видна в четырёх поисках и исчезает после снятия на $code',
      (tester) async {
        final harness = await _harness(tester, locale);
        final app = await _App.start(tester, locale, harness, seed: true);
        final l10n = app.l10n;
        final before = retainedTagFixtureGraph(app.raw);

        await _expectSearches(tester, app, marked: false);

        // Одноимённые намерения различаются идентификатором: отмечается
        // открытое, а не первое с таким названием.
        await _openDetails(tester, row: 3, intention: _walk);
        expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
        await _toggleMark(
          tester,
          l10n.graphOperationMessage(
            l10n.graphOperationMarkFavorite,
            'Гулять',
            l10n.detailsFavoriteMarked,
          ),
        );
        expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
        expect(storedFavoriteMarks(app.raw), [(tagFixtureId(_walk), 1)]);
        await _closeTop(tester, IntentionDetailsPage);
        await _expectNoLateMessage(tester);

        await _expectSearches(tester, app, marked: true);

        await _openDetails(tester, row: 3, intention: _walk);
        await _toggleMark(
          tester,
          l10n.graphOperationMessage(
            l10n.graphOperationUnmarkFavorite,
            'Гулять',
            l10n.detailsFavoriteUnmarked,
          ),
        );
        expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
        expect(storedFavoriteMarks(app.raw), isEmpty);
        await _closeTop(tester, IntentionDetailsPage);
        await _expectNoLateMessage(tester);

        await _expectSearches(tester, app, marked: false);

        // Отметка и её снятие не меняют намерения, связи и дневные выборы.
        expect(retainedTagFixtureGraph(app.raw), before);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'отметка архивированного намерения и отсутствие отметок сохраняются после нового запуска на $code',
      (tester) async {
        final harness = await _harness(tester, locale);
        var app = await _App.start(tester, locale, harness, seed: true);
        final l10n = app.l10n;
        final before = retainedTagFixtureGraph(app.raw);
        const catalog = IntentionCatalogPage;

        // Архивированное действие выполненного дневного выбора отмечается
        // без восстановления.
        await _selectScope(tester, l10n.catalogScopeArchived);
        await _expectRows(tester, catalog, [('Плавать', false)], l10n);
        await _openDetails(tester, row: 0, intention: _swim);
        await _toggleMark(
          tester,
          l10n.graphOperationMessage(
            l10n.graphOperationMarkFavorite,
            'Плавать',
            l10n.detailsFavoriteMarked,
          ),
        );
        expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
        expect(
          find.byKey(const ValueKey('intention-details-restore')),
          findsOneWidget,
        );
        expect(storedFavoriteMarks(app.raw), [(tagFixtureId(_swim), 1)]);
        // Готовность, архивное состояние, связи и дневной выбор прежние.
        expect(retainedTagFixtureGraph(app.raw), before);
        await _closeTop(tester, IntentionDetailsPage);

        // Архивный охват сообщает архивное состояние самим охватом, охват
        // всех — строкой результата.
        await _expectRows(tester, catalog, [('Плавать', true)], l10n);
        await _selectScope(tester, l10n.catalogScopeAll);
        await _expectRows(tester, catalog, [
          ('Бегать', false),
          ('Плавать', true),
          ('Читать', false),
          ('Гулять', false),
          ('Гулять', false),
        ], l10n);
        expect(
          find.descendant(
            of: _rows(catalog).at(1),
            matching: find.text(l10n.detailsArchived),
          ),
          findsOneWidget,
        );

        // Активное намерение получает следующее место, а подтверждённое
        // снятие отметки третьего намерения места не оставляет.
        await _selectScope(tester, l10n.catalogScopeActive);
        await _openDetails(tester, row: 3, intention: _walk);
        await _toggleMark(tester, null);
        await _closeTop(tester, IntentionDetailsPage);
        await _openDetails(tester, row: 1, intention: _read);
        await _toggleMark(tester, null);
        await _toggleMark(tester, null);
        expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
        await _closeTop(tester, IntentionDetailsPage);
        final marks = [(tagFixtureId(_swim), 1), (tagFixtureId(_walk), 2)];
        expect(storedFavoriteMarks(app.raw), marks);

        // Полное завершение и новый запуск на том же хранилище.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(app.runtime.shutdown);
        app = await _App.start(
          tester,
          locale,
          harness,
          seed: false,
          // Приложение открывается на Главной без ранее открытых страниц.
          onStartPage: () {
            expect(find.byType(HomePage), findsOneWidget);
            expect(find.byType(catalog), findsNothing);
            expect(find.byType(IntentionDetailsPage), findsNothing);
          },
        );

        expect(find.byType(catalog), findsOneWidget);
        expect(find.byType(IntentionDetailsPage), findsNothing);
        expect(app.router.canPop(), isFalse);
        expect(storedFavoriteMarks(app.raw), marks);
        expect(retainedTagFixtureGraph(app.raw), before);
        await _expectRows(tester, catalog, [
          ('Бегать', false),
          ('Читать', false),
          ('Гулять', false),
          ('Гулять', true),
        ], l10n);
        await _selectScope(tester, l10n.catalogScopeArchived);
        await _expectRows(tester, catalog, [('Плавать', true)], l10n);
        await _openDetails(tester, row: 0, intention: _swim);
        expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
        await _closeTop(tester, IntentionDetailsPage);
        await _selectScope(tester, l10n.catalogScopeActive);
        await _openDetails(tester, row: 1, intention: _read);
        expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
        expect(find.byKey(_message), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'быстрое повторное нажатие до снимка даёт одну команду и одно сообщение об успехе на $code',
      (tester) async {
        final harness = await _harness(tester, locale);
        final gate = _SnapshotReadGate();
        final app = await _App.start(
          tester,
          locale,
          harness,
          seed: true,
          observer: gate,
        );
        final l10n = app.l10n;
        final kinds = <IntentionCommandKind>[];
        final completions = app.coordinator.intentionCompletions.listen(
          (completion) => kinds.add(completion.kind),
        );
        addTearDown(completions.cancel);

        await _openDetails(tester, row: 3, intention: _walk);
        await _toggleMarkTwice(
          tester,
          gate,
          l10n.graphOperationMessage(
            l10n.graphOperationMarkFavorite,
            'Гулять',
            l10n.detailsFavoriteMarked,
          ),
        );
        expect(kinds, [IntentionCommandKind.markFavorite]);
        expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
        expect(storedFavoriteMarks(app.raw), [(tagFixtureId(_walk), 1)]);

        await _toggleMarkTwice(
          tester,
          gate,
          l10n.graphOperationMessage(
            l10n.graphOperationUnmarkFavorite,
            'Гулять',
            l10n.detailsFavoriteUnmarked,
          ),
        );
        expect(kinds, [
          IntentionCommandKind.markFavorite,
          IntentionCommandKind.unmarkFavorite,
        ]);
        expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
        expect(storedFavoriteMarks(app.raw), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

/// Задерживает чтение подробных данных намерения: после подтверждённой
/// операции страница остаётся с прежним снимком до [release].
final class _SnapshotReadGate extends LocalDatabaseConnectionObserver {
  Completer<void>? _release;
  var isHolding = false;

  void hold() => _release = Completer<void>();

  void release() {
    _release?.complete();
    _release = null;
    isHolding = false;
  }

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    final release = _release;
    if (release == null || !_readsIntentionDetails(statement)) {
      return;
    }
    isHolding = true;
    await release.future;
  }

  static bool _readsIntentionDetails(LocalDatabaseSqlStatement statement) =>
      statement.operation == LocalDatabaseSqlOperation.select &&
      statement.statements.single.contains('FROM intentions') &&
      statement.statements.single.contains('description,') &&
      // Команда читает строку намерения вместе с поисковым ключом.
      !statement.statements.single.contains('title_search_key') &&
      statement.statements.single.contains('WHERE id = ?');
}

/// Запуск приложения на постоянном хранилище [LocalDatabaseHarness].
final class _App {
  _App(this.runtime, this.raw, this.router, this.coordinator, this.l10n);

  final AppRuntime runtime;
  final sqlite.Database raw;
  final AppRouter router;
  final GraphCommandCoordinator coordinator;
  final AppLocalizations l10n;

  static Future<_App> start(
    WidgetTester tester,
    Locale locale,
    LocalDatabaseHarness harness, {
    required bool seed,
    LocalDatabaseConnectionObserver? observer,
    VoidCallback? onStartPage,
  }) async {
    late sqlite.Database raw;
    final runtime = AppRuntime(
      connectionFactory: () {
        final connection = openFileBackedLocalDatabase(
          harness.databaseFile,
          setup: (database) => raw = database,
        );
        return switch (observer) {
          null => connection,
          final observer => observeConfiguredLocalDatabaseConnection(
            connection,
            observer,
          ),
        };
      },
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    if (seed) _seed(raw);
    await tester.pumpWidget(MainApp(runtime: runtime));
    if (onStartPage != null) {
      // Начальная страница проверяется до перехода к графу намерений.
      await _until(tester, find.byType(HomePage));
      onStartPage();
    }
    await openIntentionGraph(tester, waitFor: _until);
    await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));
    await _until(tester, find.byType(IntentionSummaryView));
    await tester.pumpAndSettle();
    return _App(
      runtime,
      raw,
      ready.container.read(appRouterProvider),
      ready.container.read(graphCommandCoordinatorProvider.notifier),
      lookupAppLocalizations(locale),
    );
  }
}

Future<LocalDatabaseHarness> _harness(
  WidgetTester tester,
  Locale locale,
) async {
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

/// Пять намерений, связи третьего намерения и два его дневных выбора:
/// невыполненный с активным путём и выполненный с архивированным действием.
void _seed(sqlite.Database database) {
  for (final (number, title, ready, archived) in [
    (_walk, 'Гулять', 1, 0),
    (_otherWalk, 'Гулять', 0, 0),
    (_read, 'Читать', 1, 0),
    (_swim, 'Плавать', 1, 1),
    (5, 'Бегать', 1, 0),
  ]) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, ready, archived, number, number],
    );
  }
  for (final (number, related, archived) in [
    (101, 5, 0),
    (102, _swim, 1),
    (_freeRelation, _otherWalk, 0),
  ]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(_read),
        tagFixtureId(related),
        'need',
        2,
        archived,
      ],
    );
  }
  for (final (number, selected, date, completed, step, relation) in [
    (_openChoice, 5, '2026-09-25', 0, 211, 101),
    (202, _swim, '2026-09-24', 1, 212, 102),
  ]) {
    database.execute(
      'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(_read),
        tagFixtureId(selected),
        date,
        completed,
      ],
    );
    database.execute(
      'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
      [tagFixtureId(step), tagFixtureId(number), tagFixtureId(relation)],
    );
  }
}

/// Проверяет звезду намерения «Гулять» в каталоге намерений и в поисках
/// действия, исходного намерения и участника связи.
Future<void> _expectSearches(
  WidgetTester tester,
  _App app, {
  required bool marked,
}) async {
  final l10n = app.l10n;
  await _expectRows(tester, IntentionCatalogPage, [
    ('Бегать', false),
    ('Читать', false),
    ('Гулять', false),
    ('Гулять', marked),
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
    ('Бегать', false),
    ('Читать', false),
    ('Гулять', marked),
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
    ('Бегать', false),
    ('Читать', false),
    ('Гулять', false),
    ('Гулять', marked),
  ], l10n);
  await _tap(tester, find.byKey(const ValueKey('daily-choice-source-cancel')));
  await _gone(tester, DailyChoiceSourcePickerPage);
  await _popToCatalog(tester, app);

  // Поиск участника связи: второй участник «Читать» исключён.
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
    ('Бегать', false),
    ('Гулять', false),
    ('Гулять', marked),
  ], l10n);
  await _tap(tester, find.byKey(const ValueKey('participant-picker-cancel')));
  await _gone(tester, RelationParticipantPickerPage);
  await _popToCatalog(tester, app);
}

Finder _rows(Type page) => find.descendant(
  of: find.byType(page),
  matching: find.byType(IntentionSummaryView),
);

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
  await _waitFor(
    tester,
    () => _shownRows(tester, page, l10n).length == expected.length,
  );
  await tester.pumpAndSettle();
  expect(_shownRows(tester, page, l10n), expected);
  // Отметка не становится действием результата поиска.
  expect(
    find.descendant(of: _rows(page), matching: find.byType(IconButton)),
    findsNothing,
  );
}

/// Открывает страницу намерения строкой каталога с номером [row] и
/// подтверждает, что открыто именно намерение [intention].
Future<void> _openDetails(
  WidgetTester tester, {
  required int row,
  required int intention,
}) async {
  await _tap(tester, _rows(IntentionCatalogPage).at(row));
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

String? _controlTooltip(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(_favoriteControl)).tooltip;

/// Нажимает управление отметкой и дожидается ровно одного сообщения общей
/// поверхности; [message] — его ожидаемый текст, если он проверяется.
Future<void> _toggleMark(WidgetTester tester, String? message) async {
  final before = _controlTooltip(tester);
  await _tap(tester, find.byKey(_favoriteControl));
  await _until(tester, find.byKey(_message));
  await _waitFor(tester, () => _controlTooltip(tester) != before);
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsOneWidget);
  if (message != null) expect(find.text(message), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await _expectNoLateMessage(tester);
}

/// Нажимает управление отметкой и нажимает его снова в окне между
/// подтверждением операции и снимком подробных данных, которое удерживает
/// [gate]. Общая поверхность показывает ровно одно сообщение [message].
Future<void> _toggleMarkTwice(
  WidgetTester tester,
  _SnapshotReadGate gate,
  String message,
) async {
  final before = _controlTooltip(tester);
  gate.hold();
  addTearDown(gate.release);
  await _tap(tester, find.byKey(_favoriteControl));
  await _waitFor(tester, () => gate.isHolding);
  await _until(tester, find.byKey(_message));
  // Задержанное чтение держит индикаторы обновления: кадры не устоятся.
  await tester.pump(const Duration(milliseconds: 500));

  // Операция подтверждена, а страница ещё показывает прежнюю отметку.
  expect(_controlTooltip(tester), before);
  expect(
    tester.widget<IconButton>(find.byKey(_favoriteControl)).onPressed,
    isNull,
  );
  await tester.tap(find.byKey(_favoriteControl), warnIfMissed: false);
  await tester.pump();

  gate.release();
  await _waitFor(tester, () => _controlTooltip(tester) != before);
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsOneWidget);
  expect(find.text(message), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await _expectNoLateMessage(tester);
}

/// Предъявленный результат не показывается повторно.
Future<void> _expectNoLateMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsNothing);
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _popToCatalog(WidgetTester tester, _App app) async {
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
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
