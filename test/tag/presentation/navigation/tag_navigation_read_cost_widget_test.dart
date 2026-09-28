@Tags(['slow'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/tag_storage_fixture.dart';

void main() {
  for (final (pairs, repetition) in [(5003, 1), (5003, 2), (15003, 1)]) {
    testWidgets(
      'прокрутка обоих охватов при ${pairs * 2} назначениях, повтор $repetition',
      (tester) async {
        final app = await _App.pump(tester, pairs);
        for (final scope in TaggedEntitiesScope.values) {
          await app.selectScope(tester, scope);
          await _traverse(tester, app, _expected(pairs, scope), {
            'recipientPairs': pairs,
            'repetition': repetition,
            'scope': scope.name,
          });
        }
        // Переключатель доступен и после самого длинного обхода.
        await app.selectScope(tester, TaggedEntitiesScope.active);
        expect((await app.loaded(tester)).items, hasLength(50));
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  for (final scope in TaggedEntitiesScope.values) {
    testWidgets(
      'изменение большого ${scope == TaggedEntitiesScope.active ? 'активного' : 'архивного'} охвата заменяет все порции',
      (tester) async {
        const pairs = 5003;
        final app = await _App.pump(tester, pairs);
        await app.selectScope(tester, scope);
        final expected = _expected(pairs, scope);
        await _scrollTo(tester, app.more, 2000);
        await tester.tap(app.more);
        await tester.pump();
        final before = await app.loaded(tester);
        expect(before.items, hasLength(100));
        final held = app.reads.holdNext();
        await _scrollTo(tester, app.more, 2000);
        await tester.tap(app.more);
        await tester.pump();
        await _waitFor(tester, () => held.ready.isCompleted);
        final readCount = app.reads.samples.length;
        final coordinator = app
            .container(tester)
            .read(graphCommandCoordinatorProvider.notifier);
        for (final command in [
          RemoveTagAssignment(tagId: _tagId, target: expected.first),
          RemoveTagAssignment(tagId: _tagId, target: expected.last),
          AssignTag(tagId: _tagId, target: expected.first),
        ]) {
          final accepted = switch (command) {
            RemoveTagAssignment() => coordinator.acceptTagRemoveAssignment(
              command,
            ),
            AssignTag() => coordinator.acceptTagAssign(command),
            _ => throw StateError('Неподдерживаемая команда фикстуры'),
          };
          expect(accepted, isA<TagCommandAccepted>());
          final completion = await tester.runAsync(
            () => (accepted as TagCommandAccepted).future,
          );
          expect(completion!.result, isA<GraphResultSuccess>());
          await tester.pump();
        }
        final refreshing = app.state(tester) as TagNavigationLoaded;
        expect(refreshing.freshness, TagNavigationFreshness.refreshing);
        expect(refreshing.nextCursor, isNull);
        for (final element
            in find
                .descendant(of: _navigation, matching: find.byType(ListTile))
                .evaluate()) {
          expect((element.widget as ListTile).onTap, isNull);
        }
        held.release.complete();
        final current = await app.loaded(tester);
        final changed = [
          ...expected.skip(1).take(expected.length - 2),
          expected.first,
        ];
        expect(current.tagId, _tagId);
        expect(current.scope, scope);
        expect(current.items.map((item) => item.target), changed.take(50));
        expect(
          current.revision.compareTo(before.revision),
          GraphRevisionOrder.newer,
        );
        expect(app.reads.samples, hasLength(readCount + 1));
        expect(app.reads.samples.last.query.cursor, isNull);
        expect(app.reads.samples.last.query.scope, scope);
        await _traverse(tester, app, changed, {
          'recipientPairs': pairs,
          'scope': scope.name,
          'afterMutation': true,
          'discardedPageRows':
              (await held.ready.future as TaggedEntitiesPageSuccess)
                  .value
                  .items
                  .length,
          'resetRows': current.items.length,
        });
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

Future<void> _traverse(
  WidgetTester tester,
  _App app,
  List<TagTarget> expected,
  Map<String, Object?> context,
) async {
  var loaded = await app.loaded(tester);
  expect(loaded.items, hasLength(50));
  final revision = loaded.revision;
  final sampleStart = app.reads.samples.length - 1;
  final scrollDurations = <int>[];
  final loadingDurations = <int>[];
  var maximumMountedRows = 0;
  while (!loaded.hasReachedEnd) {
    final before = loaded;
    final scrolling = Stopwatch()..start();
    await _scrollTo(tester, app.more, 2000);
    scrollDurations.add(scrolling.elapsedMicroseconds);
    final loading = Stopwatch()..start();
    await tester.tap(app.more);
    await tester.pump();
    loaded = await app.loaded(tester);
    loadingDurations.add(loading.elapsedMicroseconds);
    final mountedRows = find
        .descendant(of: _navigation, matching: find.byType(ListTile))
        .evaluate()
        .length;
    if (mountedRows > maximumMountedRows) maximumMountedRows = mountedRows;
    expect(mountedRows, lessThanOrEqualTo(40));
    expect(loaded.revision.compareTo(revision), GraphRevisionOrder.same);
    expect(loaded.items.length, greaterThan(before.items.length));
    expect(loaded.items.length - before.items.length, lessThanOrEqualTo(50));
    expect(
      loaded.items.skip(before.items.length).map((item) => item.target),
      expected.skip(before.items.length).take(50),
    );
    expect(tester.takeException(), isNull);
  }
  expect(loaded.items.map((item) => item.target), expected);
  expect(
    loaded.items.map((item) => item.target).toSet(),
    hasLength(expected.length),
  );
  final samples = app.reads.samples.skip(sampleStart).toList();
  expect(samples, hasLength((expected.length / 50).ceil()));
  expect(samples.first.query.cursor, isNull);
  expect(
    samples.skip(1).every((sample) => sample.query.cursor != null),
    isTrue,
  );
  expect(
    samples.every((sample) => sample.rows <= 50 && sample.query.pageSize == 50),
    isTrue,
  );
  _emit({
    'kind': 'tag_navigation_widget_traversal',
    ...context,
    'pageSize': 50,
    'pages': samples.length,
    'resultRows': expected.length,
    'uniqueRows': loaded.items.map((item) => item.target).toSet().length,
    'maximumMountedRows': maximumMountedRows,
    'readElapsedMicroseconds': [
      for (final sample in samples) sample.microseconds,
    ],
    'scrollToMoreElapsedMicroseconds': scrollDurations,
    'tapToReadyElapsedMicroseconds': loadingDurations,
  });
  await _scrollTo(
    tester,
    find.text(app.l10n(tester).tagNavigationAllShown),
    1000,
  );
  expect(app.more, findsNothing);
  for (final target in [
    expected.whereType<IntentionTagTarget>().last,
    expected.whereType<LongTermRelationTagTarget>().last,
  ]) {
    await _scrollTo(tester, find.byKey(ValueKey(target)), -300);
    await tester.tap(find.byKey(ValueKey(target)));
    await tester.pumpAndSettle();
    switch (target) {
      case IntentionTagTarget(:final intentionId):
        expect(app.router.current.name, IntentionDetailsRoute.name);
        expect(
          app.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
          intentionId,
        );
      case LongTermRelationTagTarget(:final relationId):
        expect(app.router.current.name, RelationDetailsRoute.name);
        expect(
          app.router.current.argsAs<RelationDetailsRouteArgs>().relationId,
          relationId,
        );
    }
    app.router.pop();
    await tester.pumpAndSettle();
    expect((await app.loaded(tester)).items, loaded.items);
    expect(app.state(tester).scope, loaded.scope);
  }
}

void _emit(Map<String, Object?> record) =>
    debugPrintSynchronously(jsonEncode(record));

List<TagTarget> _expected(int pairs, TaggedEntitiesScope scope) => [
  for (var index = 0; index < pairs; index++) ...[
    if ((index % 40 == 0) == (scope == TaggedEntitiesScope.archived))
      IntentionTagTarget(
        (IntentionId.decode(
          tagFixtureId(100000 + index),
        ) as IntentionIdDecodingSuccess).id,
      ),
    if ((index % 20 == 0) == (scope == TaggedEntitiesScope.archived))
      LongTermRelationTagTarget(
        (LongTermRelationId.decode(
          tagFixtureId(200000 + index),
        ) as LongTermRelationIdDecodingSuccess).id,
      ),
  ],
];

final _tagId = (TagId.decode(tagFixtureId(9000)) as TagIdDecodingSuccess).id;
final _navigation = find.byType(TagNavigationPage);
Finder get _scrollable =>
    find.descendant(of: _navigation, matching: find.byType(Scrollable));

Future<void> _scrollTo(WidgetTester tester, Finder finder, double delta) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: _scrollable,
    maxScrolls: 30,
  );
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 200 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(done(), isTrue);
}

final class _App {
  _App(this.router, this.reads);

  final AppRouter router;
  final _MeasuredReads reads;

  Finder get more =>
      find.widgetWithText(OutlinedButton, 'Показать ещё сущности');

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(_navigation));

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(_navigation), listen: false);

  TagNavigationState state(WidgetTester tester) =>
      container(tester).read(tagNavigationViewModelProvider(_tagId));

  Future<TagNavigationLoaded> loaded(WidgetTester tester) async {
    await _waitFor(
      tester,
      () => switch (state(tester)) {
        TagNavigationLoaded(
          canUseCurrentItems: true,
          pageStatus: TagNavigationPageIdle(),
        ) =>
          true,
        _ => false,
      },
    );
    await tester.pumpAndSettle();
    return state(tester) as TagNavigationLoaded;
  }

  Future<void> selectScope(
    WidgetTester tester,
    TaggedEntitiesScope scope,
  ) async {
    final chip = find.byKey(ValueKey(scope));
    await _scrollTo(tester, chip, -100000);
    await tester.tap(chip);
    await tester.pump();
    await loaded(tester);
    expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
  }

  static Future<_App> pump(WidgetTester tester, int pairs) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('doable_navigation_widget_'),
    ))!;
    late sqlite.Database raw;
    final database = AppDatabase(
      openFileBackedLocalDatabase(
        File('${directory.path}/graph.sqlite'),
        setup: (connection) => raw = connection,
      ),
    );
    final router = AppRouter();
    _MeasuredReads? reads;
    addTearDown(() async {
      reads?.releaseAll();
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await tester.runAsync(database.close);
      await tester.runAsync(() => directory.delete(recursive: true));
    });
    await tester.runAsync(() async {
      await database.open();
      seedLargeTaggedEntitiesFixture(raw, recipientPairs: pairs);
    });
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 28),
      InMemoryDiagnosticsSink(),
    );
    final measuredReads = _MeasuredReads(repository);
    reads = measuredReads;
    _emit({
      'kind': 'tag_navigation_widget_fixture',
      'recipientPairs': pairs,
      'intentions': pairs + 1,
      'relations': pairs,
      'selectedTagAssignments': pairs * 2,
      'unrelatedTagAssignments': pairs * 2,
      'platform': Platform.operatingSystem,
      'runtime': Platform.version,
      'sqliteVersion': raw
          .select('SELECT sqlite_version()')
          .single
          .values
          .single,
      'journalMode': raw.select('PRAGMA journal_mode').single.values.single,
      'windowWidth': 600,
      'windowHeight': 900,
      'devicePixelRatio': 1,
      'textScale': 1,
      'buildMode': 'flutter test debug',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
          tagNavigationReaderProvider.overrideWithValue(measuredReads),
        ],
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pump();
    unawaited(router.push(TagNavigationRoute(tagId: _tagId)));
    await _waitFor(tester, () => _navigation.evaluate().isNotEmpty);
    final app = _App(router, measuredReads);
    await app.loaded(tester);
    return app;
  }
}

final class _ReadSample {
  const _ReadSample(this.query, this.rows, this.microseconds);
  final TaggedEntitiesQuery query;
  final int rows;
  final int microseconds;
}

final class _HeldPage {
  final ready = Completer<TaggedEntitiesPageResult>();
  final release = Completer<void>();
}

/// Измеряет настоящее чтение; задержка доставки исключена из его времени.
final class _MeasuredReads
    with TagReadContractTestFallback
    implements TagReadContract {
  _MeasuredReads(this.delegate);
  final TagReadContract delegate;
  final samples = <_ReadSample>[];
  final heldPages = <_HeldPage>[];
  _HeldPage? _next;

  _HeldPage holdNext() {
    expect(_next, isNull);
    final held = _HeldPage();
    heldPages.add(held);
    return _next = held;
  }

  void releaseAll() {
    for (final held in heldPages) {
      if (!held.release.isCompleted) held.release.complete();
    }
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) => delegate.watchTag(id);

  @override
  Future<TaggedEntitiesPageResult> getTaggedEntitiesPage(
    TaggedEntitiesQuery query,
  ) async {
    final held = _next;
    _next = null;
    final timer = Stopwatch()..start();
    final result = await delegate.getTaggedEntitiesPage(query);
    timer.stop();
    expect(result, isA<TaggedEntitiesPageSuccess>());
    final page = (result as TaggedEntitiesPageSuccess).value;
    samples.add(
      _ReadSample(query, page.items.length, timer.elapsedMicroseconds),
    );
    if (held != null) {
      held.ready.complete(result);
      await held.release.future;
    }
    return result;
  }
}
