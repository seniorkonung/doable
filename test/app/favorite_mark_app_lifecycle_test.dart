import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as catalog_page;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';

/// Намерение «Гулять», отметка которого меняется.
const _walk = 1;

/// Другое намерение: его страница открыта, когда приходит результат.
const _read = 2;

const _walkTitle = 'Гулять';
const _readTitle = 'Читать';

const _favoriteControl = ValueKey('intention-details-favorite-mark');
const _message = ValueKey('graph-operation-message');
const _pageFailure = ValueKey('intention-details-favorite-mark-failure');
const _pageRetry = ValueKey('intention-details-favorite-mark-retry');

/// Сообщение области действий: отказ отметки в ней не повторяется.
const _actionsFailure = ValueKey('intention-details-state-change-failure');

/// Описание в пределах допустимой длины, при котором область действий лежит
/// далеко за видимой частью.
final _longDescription = List.filled(200, 'Строка описания.').join('\n');

/// Положение прокрутки внутри длинного описания.
const _scrolledOffset = 400.0;

/// Остальные действия страницы намерения, изменяющие это намерение.
const _otherActions = [
  ValueKey('intention-details-edit'),
  ValueKey('intention-details-enable-readiness'),
  ValueKey('intention-details-archive'),
  ValueKey('intention-details-delete'),
];

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    for (final markedBefore in [false, true]) {
      final code = locale.languageCode;
      final operation = markedBefore ? 'снятие отметки' : 'отметка';

      for (final failWriting in [false, true]) {
        testWidgets(
          failWriting
              ? '$operation: отказ после ухода со страницы предъявляется общей поверхностью один раз на $code'
              : '$operation: принятая до ухода операция сохраняется и предъявляется один раз на $code',
          (tester) async {
            final app = await _App.start(tester, locale, marked: markedBefore);
            final l10n = app.l10n;
            final markedAfter = failWriting ? markedBefore : !markedBefore;
            final marksBefore = storedFavoriteMarks(app.raw);

            await _openDetails(tester, _walkTitle);
            expect(_controlTooltip(tester), _action(l10n, markedBefore));
            app.repository.holdNextMarkCommand();
            if (failWriting) app.faults.failNextMarkWrite();
            await _tap(tester, find.byKey(_favoriteControl));
            await _waitFor(tester, () => app.repository.isHolding);

            // Пока отметка выполняется, страница показывает подтверждённое
            // состояние, а действия этого намерения недоступны.
            _expectActionsEnabled(tester, false);
            expect(_controlTooltip(tester), _action(l10n, markedBefore));
            expect(storedFavoriteMarks(app.raw), marksBefore);

            await _closeDetails(tester);
            expect(_catalogStar(tester, _walkTitle), markedBefore);

            // Ограничение переживает закрытие и повторное открытие страницы.
            await _openDetails(tester, _walkTitle, running: true);
            _expectActionsEnabled(tester, false);
            expect(_controlTooltip(tester), _action(l10n, markedBefore));
            await _closeDetails(tester);

            // Операция другого намерения не ограничена.
            await _openDetails(tester, _readTitle);
            _expectActionsEnabled(tester, true);
            expect(find.byKey(_message), findsNothing);

            app.repository.releaseMarkCommand();
            await _until(tester, find.byKey(_message));
            await tester.pumpAndSettle();

            // Результат предъявлен один раз на странице другого намерения.
            expect(find.byKey(_message), findsOneWidget);
            expect(
              find.text(
                l10n.graphOperationMessage(
                  markedBefore
                      ? l10n.graphOperationUnmarkFavorite
                      : l10n.graphOperationMarkFavorite,
                  _walkTitle,
                  failWriting
                      ? l10n.detailsFavoriteMarkUnavailable
                      : markedBefore
                      ? l10n.detailsFavoriteUnmarked
                      : l10n.detailsFavoriteMarked,
                ),
              ),
              findsOneWidget,
            );
            expect(find.byKey(_pageFailure), findsNothing);
            expect(app.repository.markCommands, 1);
            expect(
              storedFavoriteMarks(app.raw),
              markedAfter ? [(tagFixtureId(_walk), 1)] : isEmpty,
            );
            await _dismissMessage(tester);

            await _closeDetails(tester);
            expect(_catalogStar(tester, _walkTitle), markedAfter);
            expect(_catalogStar(tester, _readTitle), isFalse);

            await _openDetails(tester, _walkTitle);
            expect(_controlTooltip(tester), _action(l10n, markedAfter));
            _expectActionsEnabled(tester, true);
            expect(find.byKey(_pageFailure), findsNothing);
            await _expectNoLateMessage(tester);
            expect(app.repository.markCommands, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets(
        '$operation: отказ при открытой прокрученной странице показывается под шапкой один раз без общей поверхности на $code',
        (tester) async {
          final app = await _App.start(
            tester,
            locale,
            marked: markedBefore,
            walkDescription: _longDescription,
          );
          final l10n = app.l10n;
          final marksBefore = storedFavoriteMarks(app.raw);

          await _openDetails(tester, _walkTitle);
          // Страница прокручена внутри длинного описания: область действий
          // находится вне видимой части.
          final scroll = tester.state<ScrollableState>(_detailsScrollable);
          scroll.position.jumpTo(_scrolledOffset);
          await tester.pumpAndSettle();
          expect(find.byKey(_otherActions.first).hitTestable(), findsNothing);

          app.faults.failNextMarkWrite();
          await _tap(tester, find.byKey(_favoriteControl));
          await _until(tester, find.byKey(_pageFailure));
          await tester.pumpAndSettle();

          // Отказ и повтор видны под шапкой без прокрутки, а её положение
          // прежнее; область действий отказ не повторяет.
          expect(
            find.text(l10n.detailsFavoriteMarkUnavailable),
            findsOneWidget,
          );
          expect(
            find.text(l10n.detailsFavoriteMarkUnavailable).hitTestable(),
            findsOneWidget,
          );
          expect(find.byKey(_pageRetry).hitTestable(), findsOneWidget);
          final contentTop = tester.getRect(_detailsScrollable).top;
          expect(
            tester.getRect(find.byKey(_pageFailure)).bottom,
            lessThanOrEqualTo(contentTop),
          );
          expect(
            tester.getRect(find.byKey(_pageRetry)).bottom,
            lessThanOrEqualTo(contentTop),
          );
          expect(scroll.position.pixels, _scrolledOffset);
          expect(find.byKey(_actionsFailure), findsNothing);
          await _expectNoLateMessage(tester);

          // Страница и хранилище показывают прежнее подтверждённое состояние.
          expect(_controlTooltip(tester), _action(l10n, markedBefore));
          _expectActionsEnabled(tester, true);
          expect(storedFavoriteMarks(app.raw), marksBefore);
          expect(app.repository.markCommands, 1);

          // Уход со страницы не предъявляет показанный отказ повторно.
          await _closeDetails(tester);
          await _expectNoLateMessage(tester);
          expect(_catalogStar(tester, _walkTitle), markedBefore);

          await _openDetails(tester, _walkTitle);
          expect(_controlTooltip(tester), _action(l10n, markedBefore));
          expect(find.byKey(_pageFailure), findsNothing);
          await _expectNoLateMessage(tester);
          expect(app.repository.markCommands, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

/// Название действия управления отметкой при подтверждённом состоянии.
String _action(AppLocalizations l10n, bool marked) =>
    marked ? l10n.detailsUnmarkFavoriteAction : l10n.detailsMarkFavoriteAction;

/// Запуск приложения на реальном хранилище с удерживаемой командой отметки
/// и управляемым отказом её записи.
final class _App {
  _App(this.raw, this.repository, this.faults, this.l10n);

  final sqlite.Database raw;
  final _HeldMarkCommands repository;
  final _MarkWriteFaults faults;
  final AppLocalizations l10n;

  static Future<_App> start(
    WidgetTester tester,
    Locale locale, {
    required bool marked,
    String? walkDescription,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late sqlite.Database raw;
    late _HeldMarkCommands repository;
    final faults = _MarkWriteFaults();
    final diagnostics = InMemoryDiagnosticsSink();
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (database) => raw = database),
        faults,
      ),
      diagnosticsSink: diagnostics,
      repositoryFactory: (database) => repository = _HeldMarkCommands(
        DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 10, 2),
          diagnostics,
        ),
      ),
    );
    addTearDown(() async {
      repository.releaseMarkCommand();
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    await tester.runAsync(runtime.bootstrap);
    for (final (number, title) in [(_walk, _walkTitle), (_read, _readTitle)]) {
      raw.execute(
        'INSERT INTO intentions (id, title, description, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, 0, 0, ?, ?)',
        [
          tagFixtureId(number),
          title,
          number == _walk ? walkDescription : null,
          number,
          number,
        ],
      );
    }
    if (marked) {
      storeFavoriteMark(raw, intentionId: tagFixtureId(_walk), position: 1);
    }
    await tester.pumpWidget(MainApp(runtime: runtime));
    await _until(tester, find.byType(IntentionSummaryView));
    await tester.pumpAndSettle();
    return _App(raw, repository, faults, lookupAppLocalizations(locale));
  }
}

Finder _catalogRow(String title) => find.descendant(
  of: find.byType(catalog_page.IntentionCatalogPage),
  matching: find.widgetWithText(IntentionSummaryView, title),
);

/// Показывает ли строка открытого каталога звезду избранного намерения.
bool _catalogStar(WidgetTester tester, String title) {
  expect(_catalogRow(title), findsOneWidget);
  return find
      .descendant(of: _catalogRow(title), matching: find.byIcon(Icons.star))
      .evaluate()
      .isNotEmpty;
}

/// Открывает страницу намерения строкой каталога. При [running] страница
/// показывает бесконечный индикатор выполняющейся операции, поэтому покоя
/// кадров не наступает и переход дожидается фиксированным временем.
Future<void> _openDetails(
  WidgetTester tester,
  String title, {
  bool running = false,
}) async {
  await _tap(tester, _catalogRow(title));
  await _until(tester, find.byKey(_favoriteControl));
  if (running) {
    await tester.pump(const Duration(seconds: 1));
  } else {
    await tester.pumpAndSettle();
  }
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('intention-details-title')))
        .data,
    title,
  );
}

/// Закрывает страницу намерения системным действием «назад».
Future<void> _closeDetails(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _waitFor(
    tester,
    () => find.byType(IntentionDetailsPage).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

/// Прокрутка содержимого страницы намерения.
final _detailsScrollable = find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

String? _controlTooltip(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(_favoriteControl)).tooltip;

/// Проверяет доступность управления отметкой и остальных действий
/// намерения открытой страницы.
void _expectActionsEnabled(WidgetTester tester, bool enabled) {
  expect(
    tester.widget<IconButton>(find.byKey(_favoriteControl)).onPressed != null,
    enabled,
  );
  for (final action in _otherActions) {
    expect(
      // Область действий может лежать вне видимой части страницы.
      tester
          .widget<ButtonStyleButton>(find.byKey(action, skipOffstage: false))
          .enabled,
      enabled,
      reason: '$action',
    );
  }
}

Future<void> _dismissMessage(WidgetTester tester) async {
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await _expectNoLateMessage(tester);
}

/// Предъявленный результат не показывается повторно, а показанный страницей
/// отказ не получает сообщения общей поверхности.
Future<void> _expectNoLateMessage(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsNothing);
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

/// Отказывает ближайшей записи отметки устранимой недоступностью хранилища:
/// транзакция команды откатывается самим адаптером.
final class _MarkWriteFaults extends LocalDatabaseConnectionObserver {
  var _failNext = false;

  void failNextMarkWrite() => _failNext = true;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (!_failNext ||
        statement.operation == LocalDatabaseSqlOperation.select ||
        !statement.statements.any(
          (sql) => sql.contains('favorite_intentions'),
        )) {
      return;
    }
    _failNext = false;
    throw sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'Управляемый отказ записи отметки',
    );
  }
}

/// Реальный адаптер, команду отметки которого тест удерживает до ухода со
/// страницы. Удержание происходит до транзакции, поэтому чтения не ждут.
final class _HeldMarkCommands extends Fake implements PersonalGraphRepository {
  _HeldMarkCommands(this._delegate);

  final PersonalGraphRepository _delegate;
  Completer<void>? _gate;

  /// Команда отметки принята координатором и ждёт [releaseMarkCommand].
  var isHolding = false;

  /// Число команд отметки и её снятия, дошедших до хранилища.
  var markCommands = 0;

  void holdNextMarkCommand() => _gate = Completer<void>();

  void releaseMarkCommand() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is MarkIntentionFavorite ||
        command is UnmarkIntentionFavorite) {
      markCommands++;
      final gate = _gate;
      if (gate != null) {
        isHolding = true;
        await gate.future;
        isHolding = false;
        _gate = null;
      }
    }
    return _delegate.execute(command);
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => _delegate.getCatalogPage(query);

  @override
  Future<Result<IntentionCatalogReconciliationOutcome>>
  getCatalogReconciliationPortion(IntentionCatalogReconciliationQuery query) =>
      _delegate.getCatalogReconciliationPortion(query);

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
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => _delegate.getDailyChoiceCatalogPage(query);

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
