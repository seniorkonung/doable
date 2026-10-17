import 'dart:async';
import 'dart:io';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/app_root_pages.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/tag_storage_fixture.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

/// Архивирован каждый четвёртый получатель: из 206 назначений выбранного тега
/// активный охват занимает четыре порции по 50, а архивный — две.
const _archivePeriod = 4;

void main() {
  const pairs = 103;
  testWidgets(
    'прокрутка обоих охватов при ${pairs * 2} назначениях выбранного тега и ${pairs * 2} назначениях другого тега',
    (tester) async {
      final app = await _App.pump(tester, pairs);
      for (final scope in TaggedIntentionsScope.values) {
        await app.selectScope(tester, scope);
        await _traverse(tester, app, _expected(pairs, scope));
      }
      // Переключатель доступен и после самого длинного обхода.
      await app.selectScope(tester, TaggedIntentionsScope.active);
      expect((await app.loaded(tester)).items, hasLength(50));
    },
  );

  const scope = TaggedIntentionsScope.active;
  testWidgets('изменение большого активного охвата заменяет все порции', (
    tester,
  ) async {
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
      RemoveTagAssignment(tagId: _tagId, intentionId: expected.first),
      RemoveTagAssignment(tagId: _tagId, intentionId: expected.last),
      AssignTag(tagId: _tagId, intentionId: expected.first),
    ]) {
      final accepted = switch (command) {
        RemoveTagAssignment() => coordinator.acceptTagRemoveAssignment(command),
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
    expect(app.more, findsNothing);
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
    expect(current.items.map((item) => item.id), changed.take(50));
    // Актуализация перечитывает только первую порцию, а не все показанные.
    expect(app.reads.samples, hasLength(readCount + 1));
    await _traverse(tester, app, changed);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _traverse(
  WidgetTester tester,
  _App app,
  List<IntentionId> expected,
) async {
  var loaded = await app.loaded(tester);
  expect(loaded.items, hasLength(50));
  final sampleStart = app.reads.samples.length - 1;
  while (!loaded.hasReachedEnd) {
    final before = loaded;
    await _scrollTo(tester, app.more, 2000);
    await tester.tap(app.more);
    await tester.pump();
    loaded = await app.loaded(tester);
    final mountedRows = find
        .descendant(of: _navigation, matching: find.byType(ListTile))
        .evaluate()
        .length;
    expect(mountedRows, lessThanOrEqualTo(40));
    expect(loaded.items.length, greaterThan(before.items.length));
    expect(loaded.items.length - before.items.length, lessThanOrEqualTo(50));
    expect(
      loaded.items.skip(before.items.length).map((item) => item.id),
      expected.skip(before.items.length).take(50),
    );
    expect(tester.takeException(), isNull);
  }
  expect(loaded.items.map((item) => item.id), expected);
  expect(
    loaded.items.map((item) => item.id).toSet(),
    hasLength(expected.length),
  );
  final samples = app.reads.samples.skip(sampleStart).toList();
  expect(samples, hasLength((expected.length / 50).ceil()));
  expect(
    samples.every((sample) => sample.rows <= 50 && sample.query.pageSize == 50),
    isTrue,
  );
  await _scrollTo(
    tester,
    find.text(app.l10n(tester).tagNavigationAllShown),
    1000,
  );
  expect(app.more, findsNothing);
  final intentionId = expected.last;
  await _scrollTo(tester, find.byKey(ValueKey(intentionId)), -300);
  await tester.tap(find.byKey(ValueKey(intentionId)));
  await tester.pumpAndSettle();
  expect(app.router.current.name, IntentionDetailsRoute.name);
  expect(
    app.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
    intentionId,
  );
  app.router.pop();
  await tester.pumpAndSettle();
  expect((await app.loaded(tester)).items, loaded.items);
  expect(app.state(tester).scope, loaded.scope);
}

List<IntentionId> _expected(int pairs, TaggedIntentionsScope scope) => [
  for (final (id, _) in largeTaggedIntentions(
    pairs,
    archivePeriod: _archivePeriod,
    archived: scope == TaggedIntentionsScope.archived,
  ))
    (IntentionId.decode(id) as IntentionIdDecodingSuccess).id,
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
      find.widgetWithText(OutlinedButton, 'Показать ещё намерения');

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
    TaggedIntentionsScope scope,
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
      seedLargeTaggedEntitiesFixture(
        raw,
        recipientPairs: pairs,
        archivePeriod: _archivePeriod,
      );
    });
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 28),
      InMemoryDiagnosticsSink(),
    );
    final measuredReads = _MeasuredReads(repository);
    reads = measuredReads;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryQuickCreationModeOverride,
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
    await openIntentionGraph(tester);
    unawaited(router.push(TagNavigationRoute(tagId: _tagId)));
    await _waitFor(tester, () => _navigation.evaluate().isNotEmpty);
    final app = _App(router, measuredReads);
    await app.loaded(tester);
    return app;
  }
}

final class _ReadSample {
  const _ReadSample(this.query, this.rows);
  final TaggedIntentionsQuery query;
  final int rows;
}

final class _HeldPage {
  final ready = Completer<TaggedIntentionsPageResult>();
  final release = Completer<void>();
}

/// Записывает настоящие чтения страниц и позволяет удержать доставку одной.
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
  Future<TaggedIntentionsPageResult> getTaggedIntentionsPage(
    TaggedIntentionsQuery query,
  ) async {
    final held = _next;
    _next = null;
    final result = await delegate.getTaggedIntentionsPage(query);
    expect(result, isA<TaggedIntentionsPageSuccess>());
    final page = (result as TaggedIntentionsPageSuccess).value;
    samples.add(_ReadSample(query, page.items.length));
    if (held != null) {
      held.ready.complete(result);
      await held.release.future;
    }
    return result;
  }
}
