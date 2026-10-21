import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/inline_text.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

part 'tag_navigation_terminal_app_scenarios.dart';
part 'tag_navigation_primary_navigation_app_scenarios.dart';

void main() {
  _registerTerminalAppScenarios();
  _registerPrimaryNavigationAppScenarios();

  testWidgets(
    'новый маршрут не принимает страницу и обработчики закрытой сессии',
    (tester) async {
      final app = await _App.pump(tester);
      final held = app.repository.holdNextPage();
      await app.openNavigation(tester);
      await _waitFor(tester, () => held.ready.isCompleted);
      final oldModel = app.model(tester);
      app.router.pop();
      await tester.pumpAndSettle();
      await _waitFor(
        tester,
        () => find
            .byType(TagNavigationPage, skipOffstage: false)
            .evaluate()
            .isEmpty,
      );
      final accepted = app.runtime.commandCoordinator.acceptTagUpdate(
        UpdateTag(
          tagId: _tagId,
          name: TagName.fromInput('Новое название'),
          color: null,
        ),
      ) as TagCommandAccepted;
      await _completed(tester, accepted.future);
      await app.openNavigation(tester);
      final before = await app.loaded(tester);
      expect(before.tag.name.value, 'Новое название');
      oldModel.setScope(TaggedIntentionsScope.archived);
      oldModel.setTagId(_otherTagId);
      unawaited(oldModel.loadMore());
      unawaited(oldModel.retryFirstPage());
      app.repository.releasePage(held);
      await _waitFor(tester, () => app.repository.activePages == 0);
      final after = await app.loaded(tester);
      expect(after.scope, TaggedIntentionsScope.active);
      expect(after.tagId, before.tagId);
      expect(after.tag.name.value, 'Новое название');
      expect(
        after.items.map((item) => item.id),
        before.items.map((item) => item.id),
      );
      expect(app.router.current.name, TagNavigationRoute.name);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'успех записи отделён от отказа актуализации и повторяет только чтение',
    (tester) async {
      final app = await _App.pump(tester);
      await app.openNavigation(tester);
      await app.loaded(tester);
      await _changeScope(tester, TaggedIntentionsScope.archived);
      final before = await app.loaded(tester);
      final l10n = app.l10n(tester);
      app.repository.failPages = true;
      final accepted = app.runtime.commandCoordinator.acceptTagUpdate(
        UpdateTag(tagId: _tagId, name: TagName.fromInput('Быт'), color: null),
      ) as TagCommandAccepted;
      final completion = await _completed(tester, accepted.future);
      expect(completion.result, isA<GraphResultSuccess>());
      await _waitFor(
        tester,
        () =>
            app.state(tester) is TagNavigationLoaded &&
            (app.state(tester) as TagNavigationLoaded).freshness ==
                TagNavigationFreshness.stale,
      );
      final stale = app.state(tester) as TagNavigationLoaded;
      expect(stale.scope, before.scope);
      expect(stale.tag.name.value, 'Быт');
      expect(
        stale.items.map((item) => item.id),
        before.items.map((item) => item.id),
      );
      expect(app.model(tester).canActOn(_intention(2)), isFalse);
      expect(find.text(l10n.tagNavigationRefreshUnavailable), findsOneWidget);
      await _waitFor(
        tester,
        () => find.textContaining(l10n.tagUpdated).evaluate().isNotEmpty,
      );
      expect(
        app.raw.select('SELECT name FROM tags WHERE id = ?', [
          tagFixtureId(firstTagNumber),
        ]).single['name'],
        'Быт',
      );
      app.repository.failPages = false;
      await _tap(tester, find.widgetWithText(OutlinedButton, l10n.commonRetry));
      final current = await app.loaded(tester);
      expect(current.scope, TaggedIntentionsScope.archived);
      expect(current.tag.name.value, 'Быт');
      expect(app.repository.commands.whereType<UpdateTag>(), hasLength(1));
      expect(find.text(l10n.tagNavigationRefreshUnavailable), findsNothing);
      expect(app.model(tester).canActOn(_intention(2)), isTrue);
      await _dismissMessage(tester);
      expect(find.textContaining(l10n.tagUpdated), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (mutation, order) in _mutationCases) {
    testWidgets(
      '${_mutationName(mutation)}: ${order.map(_arrivalName).join(' → ')} не возвращает прежнюю выдачу',
      (tester) async {
        final app = await _App.pump(tester);
        app.repository.holdObservations = true;
        final heldPage = app.repository.holdNextPage();
        await app.openNavigation(tester);
        await _waitFor(
          tester,
          () =>
              heldPage.ready.isCompleted &&
              app.repository.observations.isNotEmpty,
        );
        final before =
            (await heldPage.ready.future as TaggedIntentionsPageSuccess).value;
        final heldCommand = app.repository.holdNextCommand(
          delay: _CommandDelay.afterWrite,
        );
        final completion = _mutate(app, mutation);
        await _waitFor(tester, () => heldCommand.written.isCompleted);
        if (mutation == _Mutation.renameTag ||
            mutation == _Mutation.deleteTag) {
          await _waitFor(tester, () => app.repository.observations.length >= 2);
        }
        for (final arrival in order) {
          switch (arrival) {
            case _Arrival.page:
              app.repository.releasePage(heldPage);
              await _waitFor(tester, () => app.repository.activePages == 0);
            case _Arrival.package:
              heldCommand.release.complete();
              final result = await _completed(tester, completion);
              expect(result.isFailure, isFalse);
            case _Arrival.observation:
              // Новое наблюдение приходит раньше удержанного старого.
              app.repository.flushObservations(newestFirst: true);
              await tester.pump();
          }
        }
        app.repository.flushObservations(newestFirst: true);
        if (mutation == _Mutation.deleteTag) {
          await _waitFor(
            tester,
            () => app.state(tester) is TagNavigationTagMissing,
          );
          expect(find.text(app.l10n(tester).tagNotFound), findsOneWidget);
          expect(find.byKey(ValueKey(_intention(1))), findsNothing);
          final created = app.runtime.commandCoordinator.acceptTagCreation(
            TagCreationFormKey(),
            CreateTag(name: before.tag.name, color: null),
          ) as TagCommandAccepted;
          final replacement = await _completed(tester, created.future);
          switch (replacement.result) {
            case GraphResultSuccess(value: TagCreated(:final tag)):
              expect(tag.id, isNot(_tagId));
            default:
              fail('Новое одноимённое создание должно подтвердиться');
          }
          expect(app.state(tester), isA<TagNavigationTagMissing>());
          expect(
            app.raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
              tagFixtureId(firstTagNumber),
            ]),
            isEmpty,
          );
        } else {
          final current = await app.loaded(tester);
          expect(current.tagId, _tagId);
          expect(current.scope, TaggedIntentionsScope.active);
          switch (mutation) {
            case _Mutation.removeAssignment:
              expect(
                current.items.map((item) => item.id),
                isNot(contains(_intention(4))),
              );
              expect(app.model(tester).canActOn(_intention(4)), isFalse);
            case _Mutation.renameTag:
              expect(current.tag.name.value, 'Быт');
              expect(
                findTextIgnoringInlineWidgets(
                  app.l10n(tester).tagNavigationTag(before.tag.name.value),
                ),
                findsNothing,
              );
            case _Mutation.deleteTag:
              fail('Удаление проверяется состоянием отсутствия');
          }
        }
        expect(
          app.repository.commands.whereType<CreateTag>(),
          hasLength(mutation == _Mutation.deleteTag ? 1 : 0),
        );
        expect(
          app.repository.commands,
          hasLength(mutation == _Mutation.deleteTag ? 2 : 1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

enum _Mutation { removeAssignment, renameTag, deleteTag }

enum _Arrival { page, package, observation }

const _pageFirst = [_Arrival.page, _Arrival.package, _Arrival.observation];
const _pageLast = [_Arrival.package, _Arrival.observation, _Arrival.page];
const _observationFirst = [
  _Arrival.observation,
  _Arrival.page,
  _Arrival.package,
];

/// Каждый источник приходит и первым, и последним; поздняя страница после
/// пакета проверяется для каждой мутации. Остальные порядки проходят те же
/// ветки модели представления.
const _mutationCases = <(_Mutation, List<_Arrival>)>[
  (_Mutation.removeAssignment, _pageFirst),
  (_Mutation.removeAssignment, _pageLast),
  (_Mutation.renameTag, _pageLast),
  (_Mutation.renameTag, _observationFirst),
  (_Mutation.deleteTag, _observationFirst),
  (_Mutation.deleteTag, _pageFirst),
];

String _mutationName(_Mutation mutation) => switch (mutation) {
  _Mutation.removeAssignment => 'Снятие назначения',
  _Mutation.renameTag => 'Переименование тега',
  _Mutation.deleteTag => 'Удаление тега',
};
String _arrivalName(_Arrival arrival) => switch (arrival) {
  _Arrival.page => 'страница',
  _Arrival.package => 'пакет',
  _Arrival.observation => 'наблюдение',
};

Future<GraphCommandCompletion> _mutate(_App app, _Mutation mutation) {
  final coordinator = app.runtime.commandCoordinator;
  return switch (mutation) {
    _Mutation.removeAssignment => (coordinator.acceptTagRemoveAssignment(
      RemoveTagAssignment(tagId: _tagId, intentionId: _intention(4)),
    ) as TagCommandAccepted).future,
    _Mutation.renameTag => (coordinator.acceptTagUpdate(
      UpdateTag(tagId: _tagId, name: TagName.fromInput('Быт'), color: null),
    ) as TagCommandAccepted).future,
    _Mutation.deleteTag => (coordinator.acceptTagDelete(
      DeleteTag(_tagId),
    ) as TagCommandAccepted).future,
  };
}

final _tagId =
    (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
final _otherTagId =
    (TagId.decode(tagFixtureId(303)) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<T> _completed<T extends Object>(
  WidgetTester tester,
  Future<T> future,
) async {
  T? outcome;
  unawaited(future.then((value) => outcome = value));
  await _waitFor(tester, () => outcome != null);
  return outcome!;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, () => finder.evaluate().isNotEmpty);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _changeScope(WidgetTester tester, TaggedIntentionsScope scope) =>
    _tap(tester, find.byKey(ValueKey(scope)));

Future<void> _dismissMessage(WidgetTester tester) async {
  final message = find.byKey(const ValueKey('graph-operation-message'));
  ScaffoldMessenger.of(tester.element(message.first)).removeCurrentSnackBar();
  await _waitFor(tester, () => message.evaluate().isEmpty);
  await tester.pumpAndSettle();
}

final class _App {
  _App(
    this.runtime,
    this.router,
    this.repository,
    this.raw,
    this.database,
    this.readProbe,
  );

  final AppRuntime runtime;
  final AppRouter router;
  final _ControlledRepository repository;
  final sqlite.Database raw;
  final AppDatabase database;
  final _ReadProbe readProbe;

  static Future<_App> pump(WidgetTester tester, {String locale = 'ru'}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [Locale(locale)];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late sqlite.Database raw;
    late _ControlledRepository repository;
    late AppDatabase appDatabase;
    final readProbe = _ReadProbe();
    final diagnostics = InMemoryDiagnosticsSink();
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (database) => raw = database),
        readProbe,
      ),
      diagnosticsSink: diagnostics,
      repositoryFactory: (database) {
        appDatabase = database;
        return repository = _ControlledRepository(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 28),
            diagnostics,
          ),
        );
      },
    );
    addTearDown(() async {
      repository.releaseAll();
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    final ready = await tester.runAsync(runtime.bootstrap) as AppRuntimeReady;
    seedTagNavigationFixture(raw, extraPairsPerScope: 51);
    final router = ready.container.read(appRouterProvider);
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(
      tester,
      waitFor: (tester, finder) =>
          _waitFor(tester, () => finder.evaluate().isNotEmpty),
    );
    await _waitFor(
      tester,
      () =>
          find.byKey(const ValueKey('catalog-open-tags')).evaluate().isNotEmpty,
    );
    return _App(runtime, router, repository, raw, appDatabase, readProbe);
  }

  Future<void> openNavigation(WidgetTester tester) async {
    unawaited(router.push(TagNavigationRoute(tagId: _tagId)));
    await _waitFor(
      tester,
      () => find.byType(TagNavigationPage).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(TagNavigationPage)),
    listen: false,
  );
  TagNavigationState state(WidgetTester tester) =>
      container(tester).read(tagNavigationViewModelProvider(_tagId));
  TagNavigationViewModel model(WidgetTester tester) =>
      container(tester).read(tagNavigationViewModelProvider(_tagId).notifier);
  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(TagNavigationPage)));

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
}

/// Задерживает доставку уже прочитанного настоящего снимка.
final class _HeldPage {
  final ready = Completer<TaggedIntentionsPageResult>();
  final release = Completer<void>();
}

enum _CommandDelay { beforeWrite, afterWrite }

final class _HeldCommand {
  _HeldCommand(this.delay);
  final _CommandDelay delay;
  final started = Completer<void>();
  final written = Completer<void>();
  final release = Completer<void>();
}

final class _ControlledRepository extends Fake
    implements PersonalGraphRepository {
  _ControlledRepository(this.delegate);
  final PersonalGraphRepository delegate;
  final queries = <TaggedIntentionsQuery>[];
  final heldPages = <_HeldPage>[];
  final heldCommands = <_HeldCommand>[];
  final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[];
  final watchedIds = <TagId>[];
  final watchResults = <TagReadResult>[];
  int completedWatches = 0;
  final observations =
      <({TagReadResult result, StreamController<TagReadResult> delivery})>[];
  bool holdObservations = false;
  int activePages = 0;
  bool failPages = false;
  _HeldPage? _nextPage;
  _HeldCommand? _nextCommand;

  void flushObservations({required bool newestFirst}) {
    final pending = observations.toList();
    observations.clear();
    for (final observation in newestFirst ? pending.reversed : pending) {
      if (observation.delivery.hasListener && !observation.delivery.isClosed) {
        observation.delivery.add(observation.result);
      }
    }
  }

  _HeldCommand holdNextCommand({
    _CommandDelay delay = _CommandDelay.beforeWrite,
  }) {
    expect(_nextCommand, isNull);
    final held = _HeldCommand(delay);
    heldCommands.add(held);
    _nextCommand = held;
    return held;
  }

  _HeldPage holdNextPage() {
    expect(_nextPage, isNull);
    final held = _HeldPage();
    heldPages.add(held);
    _nextPage = held;
    return held;
  }

  void releasePage(_HeldPage held) {
    if (!held.release.isCompleted) held.release.complete();
  }

  void releaseAll() {
    for (final held in heldPages) {
      releasePage(held);
    }
    for (final held in heldCommands) {
      if (!held.release.isCompleted) held.release.complete();
    }
  }

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
  Future<TaggedIntentionsPageResult> getTaggedIntentionsPage(
    TaggedIntentionsQuery query,
  ) async {
    queries.add(query);
    if (failPages) {
      return const TaggedIntentionsPageError(
        TaggedIntentionsUnavailableFailure(),
      );
    }
    activePages++;
    final held = _nextPage;
    _nextPage = null;
    final result = await delegate.getTaggedIntentionsPage(query);
    if (held != null) {
      held.ready.complete(result);
      await held.release.future;
    }
    activePages--;
    return result;
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => delegate.getCatalogPage(query);

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => delegate.watchIntention(id);

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId id,
  ) => delegate.getRelationCounts(id);

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => delegate.getRelationGroupPage(query);

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId id) =>
      delegate.getTagAssignments(id);

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => delegate.getDailyChoiceCatalogPage(query);

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    watchedIds.add(id);
    late StreamSubscription<TagReadResult> subscription;
    late StreamController<TagReadResult> delivery;
    delivery = StreamController<TagReadResult>(
      sync: true,
      onListen: () {
        subscription = delegate
            .watchTag(id)
            .listen(
              (result) {
                watchResults.add(result);
                if (holdObservations) {
                  observations.add((result: result, delivery: delivery));
                } else {
                  delivery.add(result);
                }
              },
              onError: delivery.addError,
              onDone: () {
                completedWatches++;
                unawaited(delivery.close());
              },
            );
      },
      onCancel: () => subscription.cancel(),
    );
    return delivery.stream;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command);
    final held = _nextCommand;
    _nextCommand = null;
    if (held != null) {
      held.started.complete();
      if (held.delay == _CommandDelay.beforeWrite) await held.release.future;
    }
    final result = await delegate.execute(command);
    if (held != null) {
      held.written.complete();
      if (held.delay == _CommandDelay.afterWrite) await held.release.future;
    }
    return result;
  }
}
