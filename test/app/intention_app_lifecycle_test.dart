import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_diagnostics_sink.dart';

void main() {
  testWidgets(
    'проходит полный app-level lifecycle через задерживаемый repository',
    (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final repository = _DelayedIntentionRepository();
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

      expect(find.text('Intention created.'), findsOneWidget);
      expect(find.text(created.title), findsOneWidget);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Intention created.'), findsNothing);

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

      expect(find.text('Intention deleted.'), findsOneWidget);
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

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Условие app-level теста не выполнено.');
}

final class _DelayedIntentionRepository implements IntentionRepository {
  final pageQueries = <IntentionCatalogQuery>[];
  final detailRequests = <StreamController<Result<Intention?>>>[];
  final commands = <IntentionCommand>[];
  final _pages = <Completer<Result<IntentionCatalogPage>>>[];
  final _commands = <Completer<Result<IntentionCommandSuccess>>>[];

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
  Stream<Result<Intention?>> watchById(IntentionId id) {
    final request = StreamController<Result<Intention?>>();
    detailRequests.add(request);
    return request.stream;
  }

  @override
  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command) {
    commands.add(command);
    final request = Completer<Result<IntentionCommandSuccess>>();
    _commands.add(request);
    return request.future;
  }

  void completePage(int index, IntentionCatalogPage page) {
    _pages[index].complete(ResultSuccess(page));
  }

  void emitDetail(int index, Intention intention) {
    detailRequests[index].add(ResultSuccess(intention));
  }

  void completeCommand(int index, Result<IntentionCommandSuccess> result) {
    _commands[index].complete(result);
  }

  Future<void> close() async {
    for (final request in detailRequests) {
      if (!request.isClosed) await request.close();
    }
  }
}

Intention _intention({required String title, required String? description}) {
  final id = switch (IntentionId.decode(
    '018f0000-0000-7000-8000-000000000001',
  )) {
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

Result<IntentionCommandSuccess> _saved(
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
  return ResultSuccess(IntentionSaved(intention, catalogMutation: mutation));
}

Result<IntentionCommandSuccess> _deleted(
  Intention intention, {
  required int revision,
}) => ResultSuccess(
  IntentionDeleted(
    intention.id,
    catalogMutation: IntentionCatalogDeleted(
      revision: _Revision(revision),
      entry: _Snapshot(intention),
    ),
  ),
);

final class _Snapshot implements IntentionCatalogEntrySnapshot {
  _Snapshot(Intention intention) : summary = _summary(intention);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

final class _Revision implements IntentionCatalogRevision {
  const _Revision(this.sequence);

  final int sequence;

  @override
  IntentionCatalogRevisionOrder compareTo(IntentionCatalogRevision other) {
    if (other is! _Revision) {
      return IntentionCatalogRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return IntentionCatalogRevisionOrder.older;
    if (comparison > 0) return IntentionCatalogRevisionOrder.newer;
    return IntentionCatalogRevisionOrder.same;
  }
}
