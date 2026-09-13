import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_diagnostics_sink.dart';

void main() {
  testWidgets(
    'оболочка показывает результат ушедшего экрана поверх другого намерения один раз',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final repository = _DelayedPersonalGraphRepository();
      final intentionA = _intention(
        uuid: '018f0000-0000-7000-8000-000000000001',
        title: 'A',
        description: null,
      );
      final intentionB = _intention(
        uuid: '018f0000-0000-7000-8000-000000000002',
        title: 'B',
        description: null,
      );
      await _pumpCatalog(tester, repository, [intentionA, intentionB]);

      await _openDetails(tester, repository, intentionA, requestIndex: 0);
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-archive')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-archive')));
      await tester.pump();
      expect(repository.commands.single, isA<ArchiveIntention>());

      await _goBack(tester);
      await tester.pumpAndSettle();
      await _openDetails(tester, repository, intentionB, requestIndex: 1);

      final archivedA = _copyIntention(
        intentionA,
        archiveState: IntentionArchiveState.archived,
        updatedDay: 2,
      );
      repository.completeCommand(
        0,
        _saved(archivedA, before: intentionA, revision: 1),
      );
      await tester.pumpAndSettle();

      const message = 'Archive — “A”: Intention archived.';
      expect(find.text(message), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: message,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      semantics.dispose();

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _goBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      expect(find.text(message), findsNothing);
    },
  );

  for (final scenario in <({Locale locale, String message})>[
    (
      locale: Locale('en'),
      message:
          'Archive — “A”: The intention state couldn’t be changed. Try again.',
    ),
    (
      locale: Locale('ru'),
      message: 'Архивирование — «A»: Не удалось изменить состояние намерения. Повторите попытку.',
    ),
  ]) {
    testWidgets(
      'оболочка ждёт возвращения приложения перед показом failure (${scenario.locale.languageCode})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.binding.platformDispatcher.localesTestValue = [scenario.locale];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        final repository = _DelayedPersonalGraphRepository();
        final intentionA = _intention(
          uuid: '018f0000-0000-7000-8000-000000000001',
          title: 'A',
          description: null,
        );
        final intentionB = _intention(
          uuid: '018f0000-0000-7000-8000-000000000002',
          title: 'B',
          description: null,
        );
        await _pumpCatalog(tester, repository, [intentionA, intentionB]);

        await _openDetails(tester, repository, intentionA, requestIndex: 0);
        await tester.ensureVisible(
          find.byKey(const ValueKey('intention-details-archive')),
        );
        await tester.tap(
          find.byKey(const ValueKey('intention-details-archive')),
        );
        await tester.pump();
        await _goBack(tester);
        await tester.pumpAndSettle();
        await _openDetails(tester, repository, intentionB, requestIndex: 1);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        expect(find.text(scenario.message), findsNothing);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(find.text(scenario.message), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: scenario.message,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'проходит полный app-level lifecycle через задерживаемый repository',
    (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final repository = _DelayedPersonalGraphRepository();
      final runtime = AppRuntime(
        connectionFactory: openInMemoryLocalDatabase,
        diagnosticsSink: InMemoryDiagnosticsSink(),
        repositoryFactory: (_) => repository,
      );
      addTearDown(() async {
        await runtime.shutdown();
        await repository.close();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await _pumpUntil(tester, () => repository.pageQueries.isNotEmpty);
      repository.completePage(
        0,
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const _Revision(0),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('catalog-create-intention')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        '  Быть здоровым  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-description')),
        '  Пользовательское описание\n',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await tester.pump();
      expect(repository.commands.single, isA<CreateIntention>());
      expect(find.text('Creating…'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      final created = _intention(
        title: 'Быть здоровым',
        description: '  Пользовательское описание\n',
      );
      repository.completeCommand(0, _saved(created, revision: 1));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('Create — “Быть здоровым”: Intention created.'),
        findsOneWidget,
      );
      expect(find.text(created.title), findsOneWidget);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('Create — “Быть здоровым”: Intention created.'),
        findsNothing,
      );

      await tester.tap(find.text(created.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 1);
      repository.emitDetail(0, created);
      await tester.pumpAndSettle();
      expect(find.text(created.description!), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-edit')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-edit')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        'Укреплять здоровье',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-description')),
        'Новое описание',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pump();
      final updated = _copyIntention(
        created,
        title: 'Укреплять здоровье',
        description: 'Новое описание',
        updatedDay: 2,
      );
      repository.completeCommand(
        1,
        _saved(updated, before: created, revision: 2),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 2);

      repository.emitDetail(0, created);
      await tester.pump();
      expect(find.text(updated.title), findsOneWidget);
      expect(find.text(created.title), findsNothing);
      repository.emitDetail(1, updated);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-enable-readiness')),
      );
      await tester.tap(
        find.byKey(const ValueKey('intention-details-enable-readiness')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as ready'));
      await tester.pump();
      final ready = _copyIntention(
        updated,
        readiness: IntentionReadiness.ready,
        updatedDay: 3,
      );
      repository.completeCommand(
        2,
        _saved(ready, before: updated, revision: 3),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 3);
      repository.emitDetail(2, ready);
      await tester.pumpAndSettle();
      expect(find.text('Ready for action'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-archive')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-archive')));
      await tester.pump();
      final archived = _copyIntention(
        ready,
        archiveState: IntentionArchiveState.archived,
        updatedDay: 4,
      );
      repository.completeCommand(
        3,
        _saved(archived, before: ready, revision: 4),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 4);
      repository.emitDetail(3, archived);
      await tester.pumpAndSettle();
      expect(find.text('Archived'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No active intentions yet.'), findsOneWidget);
      await _selectScope(tester, 'Archived');
      await _pumpUntil(tester, () => repository.pageQueries.length == 2);
      repository.completePage(
        1,
        IntentionCatalogFirstPage(
          items: [_summary(archived)],
          totalCount: 1,
          nextCursor: null,
          revision: const _Revision(4),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(archived.title), findsOneWidget);

      await tester.tap(find.text(archived.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 5);
      repository.emitDetail(4, archived);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-restore')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-restore')));
      await tester.pump();
      final restored = _copyIntention(
        archived,
        archiveState: IntentionArchiveState.active,
        updatedDay: 5,
      );
      repository.completeCommand(
        4,
        _saved(restored, before: archived, revision: 5),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 6);
      repository.emitDetail(5, restored);
      await tester.pumpAndSettle();
      expect(find.text('Active'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No archived intentions yet.'), findsOneWidget);
      await _selectScope(tester, 'Active');
      await _pumpUntil(tester, () => repository.pageQueries.length == 3);
      repository.completePage(
        2,
        IntentionCatalogFirstPage(
          items: [_summary(restored)],
          totalCount: 1,
          nextCursor: null,
          revision: const _Revision(5),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(restored.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 7);
      repository.emitDetail(6, restored);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-delete')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await tester.pump();
      expect(repository.commands.last, isA<DeleteIntention>());

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('catalog-create-intention')),
        findsOneWidget,
      );
      repository.completeCommand(5, _deleted(restored, revision: 6));
      await tester.pumpAndSettle();

      expect(
        find.text('Delete — “Укреплять здоровье”: Intention deleted.'),
        findsOneWidget,
      );
      expect(find.text(restored.title), findsNothing);
      expect(find.text('No active intentions yet.'), findsOneWidget);
    },
  );
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

Future<void> _pumpCatalog(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
  List<Intention> intentions,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final runtime = AppRuntime(
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: InMemoryDiagnosticsSink(),
    repositoryFactory: (_) => repository,
  );
  addTearDown(() async {
    await runtime.shutdown();
    await repository.close();
  });

  await tester.pumpWidget(MainApp(runtime: runtime));
  await _pumpUntil(tester, () => repository.pageQueries.isNotEmpty);
  repository.completePage(
    0,
    IntentionCatalogFirstPage(
      items: intentions.map(_summary).toList(growable: false),
      totalCount: intentions.length,
      nextCursor: null,
      revision: const _Revision(0),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDetails(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
  Intention intention, {
  required int requestIndex,
}) async {
  await tester.tap(find.text(intention.title));
  await _pumpUntil(
    tester,
    () => repository.detailRequests.length > requestIndex,
  );
  repository.emitDetail(requestIndex, intention);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Условие app-level теста не выполнено.');
}

final class _DelayedPersonalGraphRepository implements PersonalGraphRepository {
  final pageQueries = <IntentionCatalogQuery>[];
  final detailRequests =
      <StreamController<Result<GraphSnapshot<Intention?>>>>[];
  final commands = <IntentionCommand>[];
  final _pages = <Completer<Result<IntentionCatalogPage>>>[];
  final _commands =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    pageQueries.add(query);
    final request = Completer<Result<IntentionCatalogPage>>();
    _pages.add(request);
    return request.future;
  }

  @override
  Stream<Result<GraphSnapshot<Intention?>>> watchIntention(IntentionId id) {
    final request = StreamController<Result<GraphSnapshot<Intention?>>>();
    detailRequests.add(request);
    return request.stream;
  }

  @override
  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> execute(
    IntentionCommand command,
  ) {
    commands.add(command);
    final request =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _commands.add(request);
    return request.future;
  }

  void completePage(int index, IntentionCatalogPage page) {
    _pages[index].complete(ResultSuccess(page));
  }

  void emitDetail(int index, Intention intention) {
    detailRequests[index].add(
      ResultSuccess(
        GraphSnapshot(value: intention, revision: _Revision(index)),
      ),
    );
  }

  void completeCommand(
    int index,
    Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
  ) {
    _commands[index].complete(result);
  }

  Future<void> close() async {
    for (final request in detailRequests) {
      if (!request.isClosed) await request.close();
    }
  }
}

Intention _intention({
  String uuid = '018f0000-0000-7000-8000-000000000001',
  required String title,
  required String? description,
}) {
  final id = switch (IntentionId.decode(uuid)) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный fixture ID.',
    ),
  };
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 1));
  return Intention(
    id: id,
    title: title,
    description: description,
    readiness: IntentionReadiness.notReady,
    archiveState: IntentionArchiveState.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Intention _copyIntention(
  Intention source, {
  String? title,
  String? description,
  IntentionReadiness? readiness,
  IntentionArchiveState? archiveState,
  required int updatedDay,
}) => Intention(
  id: source.id,
  title: title ?? source.title,
  description: description ?? source.description,
  readiness: readiness ?? source.readiness,
  archiveState: archiveState ?? source.archiveState,
  createdAt: source.createdAt,
  updatedAt: IntentionTimestamp(DateTime.utc(2026, 1, updatedDay)),
);

IntentionSummary _summary(Intention intention) => IntentionSummary(
  id: intention.id,
  title: intention.title,
  hasDescription: intention.description != null,
  readiness: intention.readiness,
  archiveState: intention.archiveState,
  createdAt: intention.createdAt,
  updatedAt: intention.updatedAt,
);

Result<ConfirmedGraphResult<IntentionCommandSuccess>> _saved(
  Intention intention, {
  Intention? before,
  required int revision,
}) {
  final after = _Snapshot(intention);
  final mutation = before == null
      ? IntentionCatalogCreated(revision: _Revision(revision), entry: after)
      : IntentionCatalogUpdated(
          revision: _Revision(revision),
          before: _Snapshot(before),
          after: after,
        );
  final value = IntentionSaved(intention, catalogMutation: mutation);
  return ResultSuccess(
    ConfirmedGraphResult(revision: _Revision(revision), value: value),
  );
}

Result<ConfirmedGraphResult<IntentionCommandSuccess>> _deleted(
  Intention intention, {
  required int revision,
}) {
  final value = IntentionDeleted(
    intention.id,
    catalogMutation: IntentionCatalogDeleted(
      revision: _Revision(revision),
      entry: _Snapshot(intention),
    ),
  );
  return ResultSuccess(
    ConfirmedGraphResult(revision: _Revision(revision), value: value),
  );
}

final class _Snapshot implements IntentionCatalogEntrySnapshot {
  _Snapshot(Intention intention) : summary = _summary(intention);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

final class _Revision implements GraphRevision {
  const _Revision(this.sequence);

  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _Revision) {
      return GraphRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return GraphRevisionOrder.older;
    if (comparison > 0) return GraphRevisionOrder.newer;
    return GraphRevisionOrder.same;
  }
}
