import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/tag_positions.dart';

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _until(tester, () => finder.evaluate().isNotEmpty);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('поиск и выбор согласованы после ухода с формы переименования', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late sqlite.Database raw;
    late _ControlledRepository repository;
    final diagnostics = InMemoryDiagnosticsSink();
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () =>
          openInMemoryLocalDatabase(setup: (database) => raw = database),
      diagnosticsSink: diagnostics,
      repositoryFactory: (database) => repository = _ControlledRepository(
        DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 25),
          diagnostics,
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(
      tester,
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
    );
    await _until(
      tester,
      () =>
          find.byKey(const ValueKey('catalog-open-tags')).evaluate().isNotEmpty,
    );
    seedRawGraph(raw, () {
      raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
        '018f0b5d-6b2e-7c80-8000-000000000002',
        'Для дома',
        tagPositionKey(200001),
      ]);
    });
    await _tap(tester, 'catalog-open-tags');
    final search = find.byKey(const ValueKey('tag-catalog-search'));
    await _until(tester, () => search.evaluate().isNotEmpty);
    await tester.enterText(search, 'дом');
    await tester.pump();
    await _tap(tester, 'tag-catalog-create');
    await _until(
      tester,
      () => find.byKey(const ValueKey('tag-editor-name')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Дом',
    );
    await tester.pump();
    await _tap(tester, 'tag-editor-submit');
    await _until(
      tester,
      () => find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty,
    );
    final tagIdText = raw
        .select("SELECT id FROM tags WHERE name = 'Дом'")
        .single['id'];
    final row = find.byKey(ValueKey('tag-catalog-row-$tagIdText'));
    await _until(
      tester,
      () => tester.widget<Semantics>(row).properties.selected == true,
    );
    expect(tester.widget<TextField>(search).controller!.text, 'дом');
    await tester.tap(find.byTooltip('Изменить тег').first);
    await _until(
      tester,
      () => find.byKey(const ValueKey('tag-editor-name')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Спорт',
    );
    await tester.pump();
    repository.holdNextRename();
    await _tap(tester, 'tag-editor-submit');
    await _until(tester, () => repository.renameAttempts == 1);
    await _tap(tester, 'tag-editor-cancel');
    await _until(
      tester,
      () => find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty,
    );
    expect(tester.widget<TextField>(search).controller!.text, 'дом');
    repository.releaseRename();
    await _until(tester, () => row.evaluate().isEmpty);
    expect(find.text('Для дома'), findsOneWidget);
    expect(find.text('Спорт'), findsNothing);
    expect(tester.widget<TextField>(search).controller!.text, 'дом');
    await tester.enterText(search, 'спорт');
    await _until(tester, () => find.text('Спорт').evaluate().isNotEmpty);
    expect(tester.widget<Semantics>(row).properties.selected, isTrue);
    expect(find.text('Дом'), findsNothing);
    expect(repository.renameAttempts, 1);
  });

  testWidgets('после commit ошибка обновления каталога не повторяет создание', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late sqlite.Database raw;
    late _ControlledRepository repository;
    final diagnostics = InMemoryDiagnosticsSink();
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () =>
          openInMemoryLocalDatabase(setup: (database) => raw = database),
      diagnosticsSink: diagnostics,
      repositoryFactory: (database) => repository = _ControlledRepository(
        DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 25),
          diagnostics,
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(
      tester,
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
    );
    await _tap(tester, 'catalog-open-tags');
    final search = find.byKey(const ValueKey('tag-catalog-search'));
    await _until(tester, () => search.evaluate().isNotEmpty);
    await tester.enterText(search, 'STRASS');
    await tester.pump();
    await _tap(tester, 'tag-catalog-create');
    await _until(
      tester,
      () => find.byKey(const ValueKey('tag-editor-name')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Straße',
    );
    await tester.pump();
    repository.failNextCatalogRead = true;
    await _tap(tester, 'tag-editor-submit');
    // Успех закрывает форму тегом из результата команды без чтения после
    // записи.
    await _until(
      tester,
      () => find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty,
    );
    expect(raw.select('SELECT name FROM tags').single['name'], 'Straße');
    expect(repository.createAttempts, 1);
    await _until(
      tester,
      () => find.textContaining('couldn’t be loaded').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Try again'));
    await _until(tester, () => find.text('Straße').evaluate().isNotEmpty);
    expect(tester.widget<TextField>(search).controller!.text, 'STRASS');
    expect(repository.createAttempts, 1);
    expect(raw.select('SELECT id FROM tags'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

final class _ControlledRepository extends Fake
    implements PersonalGraphRepository {
  _ControlledRepository(this.delegate);

  final PersonalGraphRepository delegate;
  Completer<void>? _heldRename;
  bool failNextCatalogRead = false;
  int createAttempts = 0;
  int renameAttempts = 0;

  void holdNextRename() => _heldRename = Completer<void>();
  void releaseRename() => _heldRename!.complete();

  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) =>
      delegate.getStatisticsPage(query);

  @override
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) => delegate.getIntentionStatisticsSection(query);

  @override
  Future<IntentionStatisticsBreakdownResult<T>>
  getIntentionStatisticsBreakdown<T>(StatisticsBreakdownCursor<T> cursor) =>
      delegate.getIntentionStatisticsBreakdown(cursor);

  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) => delegate.getDailyChoiceDayStatuses(query);

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => delegate.getCatalogPage(query);

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) =>
      failNextCatalogRead ? _failCatalogRead() : delegate.getTagCatalog(mode);

  Future<TagCatalogResult> _failCatalogRead() async {
    failNextCatalogRead = false;
    return const TagCatalogError(TagCatalogUnavailableFailure());
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) => delegate.watchTag(id);

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is CreateTag) createAttempts++;
    if (command is UpdateTag) {
      renameAttempts++;
      final gate = _heldRename;
      if (gate != null) {
        await gate.future;
        _heldRename = null;
      }
    }
    return delegate.execute(command);
  }
}
