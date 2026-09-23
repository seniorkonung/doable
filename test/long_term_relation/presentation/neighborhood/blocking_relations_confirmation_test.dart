import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_confirmation.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neighborhood_test_support.dart';

void main() {
  testWidgets('показывает весь выбор из разных групп и порций при крупном тексте', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(480, 720);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final harness = await _pumpAction(tester, const Locale('ru'));
    final rows = [
      testGroupRow(ownerId: harness.intentionId, index: 1),
      for (var index = 2; index <= 18; index++)
        testGroupRow(
          ownerId: harness.intentionId,
          index: index,
          type: LongTermRelationType.can,
          direction: RelationDirection.incoming,
          scope: RelationScope.archived,
          neighborTitle: 'Одноимённое',
        ),
    ];
    for (final row in rows) {
      harness.select(row);
    }
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await tester.pumpAndSettle();
    expect(harness.repository.selectedReads, 1);
    expect(harness.repository.selectedWatches, 1);
    expect(harness.repository.relationWatches, 0);
    expect(
      harness.repository.selectedIds,
      rows.map((row) => row.relation.id).toSet(),
    );
    expect(
      find.text('Чтобы Намерение-владелец, нужно Связанное 1'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(
        ValueKey(
          'blocking-relations-confirm-row-${rows[1].relation.id.toCanonicalString()}',
        ),
      ),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Связь в архиве'), findsWidgets);
    expect(find.text('Входящие'), findsWidgets);
    expect(
      find.textContaining(rows[1].source.id.toCanonicalString()),
      findsWidgets,
    );
    expect(harness.repository.commands, isEmpty);

    final last = find.byKey(
      ValueKey(
        'blocking-relations-confirm-row-${rows.last.relation.id.toCanonicalString()}',
      ),
    );
    await tester.scrollUntilVisible(
      last,
      450,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              ValueKey(
                'blocking-relations-confirm-semantics-${rows.last.relation.id.toCanonicalString()}',
              ),
            ),
          )
          .label,
      contains('Входящие'),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('blocking-relations-confirm-delete')),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const ValueKey('blocking-relations-cancel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('blocking-relations-confirm-delete')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'отмена не отправляет команду, а подтверждение отправляет только снимок один раз',
    (tester) async {
      final harness = await _pumpAction(tester, const Locale('en'));
      final first = testGroupRow(ownerId: harness.intentionId, index: 1);
      final second = testGroupRow(
        ownerId: harness.intentionId,
        index: 2,
        type: LongTermRelationType.can,
        direction: RelationDirection.incoming,
        scope: RelationScope.archived,
        neighborTitle: 'Same name',
      );
      harness.select(first);
      harness.select(second);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
      await _finishSelectionRead(tester, harness);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('blocking-relations-cancel')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-cancel')));
      await tester.pumpAndSettle();
      expect(harness.repository.commands, isEmpty);

      await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
      await tester.pumpAndSettle();
      final later = testGroupRow(ownerId: harness.intentionId, index: 3);
      expect(
        harness.container
            .read(
              blockingRelationsSelectionViewModelProvider(harness.intentionId),
            )
            .selected
            .containsKey(later.relation.id),
        isFalse,
      );
      final confirm = find.byKey(
        const ValueKey('blocking-relations-confirm-delete'),
      );
      await tester.scrollUntilVisible(
        confirm,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();
      expect(harness.repository.commands, hasLength(1));
      expect(
        (harness.repository.commands.single as DeleteBlockingRelations)
            .relationIds,
        {first.relation.id, second.relation.id},
      );
    },
  );

  testWidgets(
    'английский резервный язык и пустой выбор не запускают удаление',
    (tester) async {
      final harness = await _pumpAction(tester, const Locale('fr'));
      expect(
        find.byKey(const ValueKey('blocking-relations-review')),
        findsNothing,
      );
      expect(harness.repository.commands, isEmpty);
      harness.select(testGroupRow(ownerId: harness.intentionId, index: 1));
      await tester.pump();
      expect(find.text('Review selected relations'), findsOneWidget);
    },
  );

  testWidgets('ошибка принятой операции остаётся у инлайн-сообщения', (
    tester,
  ) async {
    final harness = await _pumpAction(tester, const Locale('ru'));
    harness.select(testGroupRow(ownerId: harness.intentionId, index: 1));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await _finishSelectionRead(tester, harness);
    await tester.pumpAndSettle();
    final confirm = find.byKey(
      const ValueKey('blocking-relations-confirm-delete'),
    );
    await tester.scrollUntilVisible(
      confirm,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pump();
    expect(find.text('Удаляем выбранные связи…'), findsOneWidget);
    harness.repository.requests.single.complete(
      const GraphCommandFailed<
        BlockingRelationsDeleted,
        DeleteBlockingRelationsFailure
      >(DeleteBlockingRelationsUnavailableFailure()),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('blocking-relations-delete-failure')),
      findsOneWidget,
    );
    expect(
      find.text('Не удалось удалить выбранные связи. Повторите попытку.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('blocking-relations-edit-selection')),
      findsOneWidget,
    );
  });

  testWidgets(
    'изменённый во время просмотра черновик требует нового подтверждения',
    (tester) async {
      final harness = await _pumpAction(tester, const Locale('en'));
      harness.select(testGroupRow(ownerId: harness.intentionId, index: 1));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
      await tester.pumpAndSettle();
      harness.select(testGroupRow(ownerId: harness.intentionId, index: 2));
      await tester.pump();
      final confirm = find.byKey(
        const ValueKey('blocking-relations-confirm-delete'),
      );
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(harness.repository.commands, isEmpty);
      expect(
        find.byKey(const ValueKey('blocking-relations-review')),
        findsOneWidget,
      );
    },
  );

  testWidgets('конфликт показывает недоступную связь до явного исправления', (
    tester,
  ) async {
    final harness = await _pumpAction(tester, const Locale('ru'));
    final first = testGroupRow(ownerId: harness.intentionId, index: 1);
    final missing = testGroupRow(
      ownerId: harness.intentionId,
      index: 2,
      type: LongTermRelationType.can,
      direction: RelationDirection.incoming,
      scope: RelationScope.archived,
    );
    harness.select(first);
    harness.select(missing);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await _finishSelectionRead(tester, harness);
    await tester.pumpAndSettle();
    final confirm = find.byKey(
      const ValueKey('blocking-relations-confirm-delete'),
    );
    await tester.scrollUntilVisible(
      confirm,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pump();
    expect(harness.repository.commands, hasLength(1));

    harness.repository.rows.remove(missing.relation.id);
    harness.repository.requests.single.complete(
      GraphCommandFailed<
        BlockingRelationsDeleted,
        DeleteBlockingRelationsFailure
      >(
        DeleteBlockingRelationsSelectionConflictFailure.longTerm(
          relationId: missing.relation.id,
          reason: BlockingRelationConflictReason.relationMissing,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('blocking-relations-refresh-selection')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('blocking-relations-refresh-selection')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey(
          'blocking-relations-invalid-${missing.relation.id.toCanonicalString()}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('blocking-relations-review')),
      findsNothing,
    );
    expect(harness.repository.commands, hasLength(1));

    await tester.tap(
      find.byKey(
        ValueKey(
          'blocking-relations-remove-invalid-${missing.relation.id.toCanonicalString()}',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      confirm,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pump();
    expect(harness.repository.commands, hasLength(2));
    expect(
      (harness.repository.commands.last as DeleteBlockingRelations).relationIds,
      {first.relation.id},
    );
  });

  testWidgets('просмотр получает изменённые поля выбранной связи', (
    tester,
  ) async {
    final harness = await _pumpAction(tester, const Locale('en'));
    final original = testGroupRow(ownerId: harness.intentionId, index: 1);
    harness.select(original);
    harness.repository.rows[original.relation.id] = testGroupRow(
      ownerId: harness.intentionId,
      index: 1,
      type: LongTermRelationType.can,
      scope: RelationScope.archived,
      neighborTitle: 'New title',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await tester.pumpAndSettle();
    expect(
      find.text('To Намерение-владелец, you can New title'),
      findsOneWidget,
    );
    expect(find.text('Archived relation'), findsWidgets);
    expect(harness.repository.commands, isEmpty);
  });

  testWidgets('открытое подтверждение показывает новые поля без смены набора', (
    tester,
  ) async {
    final harness = await _pumpAction(tester, const Locale('ru'));
    final original = testGroupRow(ownerId: harness.intentionId, index: 1);
    harness.select(original);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await tester.pumpAndSettle();

    final changed = testGroupRow(
      ownerId: harness.intentionId,
      index: 1,
      type: LongTermRelationType.can,
      scope: RelationScope.archived,
      priority: RelationPriority.p1,
      neighborTitle: 'Новое название',
    );
    harness.repository.emitRelation(
      changed,
      revision: const TestGraphRevision(5),
      description: 'Новое описание',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Чтобы Намерение-владелец, можно Новое название'),
      findsOneWidget,
    );
    expect(find.textContaining('P1'), findsWidgets);
    expect(find.text('Новое описание'), findsOneWidget);
    expect(find.text('Связь в архиве'), findsWidgets);

    harness.repository.emitRelation(
      original,
      revision: const TestGraphRevision(4),
    );
    await tester.pumpAndSettle();
    expect(find.text('Новое описание'), findsOneWidget);
    expect(harness.repository.commands, isEmpty);
  });

  testWidgets(
    'ошибка актуализации сохраняет выбор и не открывает подтверждение',
    (tester) async {
      final harness = await _pumpAction(tester, const Locale('ru'));
      final row = testGroupRow(ownerId: harness.intentionId, index: 1);
      harness.select(row);
      harness.repository.readFailure =
          const LongTermRelationReadUnavailableFailure();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('blocking-relations-confirm-delete')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('blocking-relations-refresh-retry')),
        findsOneWidget,
      );
      expect(harness.repository.commands, isEmpty);
      expect(
        harness.container
            .read(
              blockingRelationsSelectionViewModelProvider(harness.intentionId),
            )
            .selected
            .keys,
        {row.relation.id},
      );
      harness.repository.readFailure = null;
      await tester.tap(
        find.byKey(const ValueKey('blocking-relations-refresh-retry')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('blocking-relations-review')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'исчезновение выбранной связи запрещает подтверждение до исправления',
    (tester) async {
      final harness = await _pumpAction(tester, const Locale('ru'));
      final first = testGroupRow(ownerId: harness.intentionId, index: 1);
      final second = testGroupRow(ownerId: harness.intentionId, index: 2);
      harness.select(first);
      harness.select(second);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
      await tester.pumpAndSettle();

      harness.repository.emitMissing(
        second.relation.id,
        revision: const TestGraphRevision(5),
      );
      await tester.pumpAndSettle();
      final confirm = find.byKey(
        const ValueKey('blocking-relations-confirm-delete'),
      );
      await tester.scrollUntilVisible(
        confirm,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(harness.repository.commands, isEmpty);
      await tester.tap(find.byKey(const ValueKey('blocking-relations-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey(
            'blocking-relations-invalid-${second.relation.id.toCanonicalString()}',
          ),
        ),
        findsOneWidget,
      );
      expect(harness.repository.selectedIds, {
        first.relation.id,
        second.relation.id,
      });
    },
  );

  testWidgets('отказ наблюдения сохраняет набор и блокирует отправку', (
    tester,
  ) async {
    final harness = await _pumpAction(tester, const Locale('en'));
    final row = testGroupRow(ownerId: harness.intentionId, index: 1);
    harness.select(row);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await tester.pumpAndSettle();

    harness.repository.emitSelectionFailure();
    await tester.pumpAndSettle();
    final confirm = find.byKey(
      const ValueKey('blocking-relations-confirm-delete'),
    );
    await tester.scrollUntilVisible(
      confirm,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(harness.repository.commands, isEmpty);
    expect(
      harness.container
          .read(
            blockingRelationsSelectionViewModelProvider(harness.intentionId),
          )
          .selected
          .keys,
      {row.relation.id},
    );
  });
}

Future<_Harness> _pumpAction(WidgetTester tester, Locale locale) async {
  final harness = _Harness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(harness.repository),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: BlockingRelationsConfirmationAction(
              intentionId: harness.intentionId,
              intentionTitle: 'Намерение-владелец',
            ),
          ),
        ),
      ),
    ),
  );
  return harness
    ..container = ProviderScope.containerOf(
      tester.element(find.byType(BlockingRelationsConfirmationAction)),
    )
    ..repository.isPrepared = () => harness.container.read(
      blockingRelationsSelectionViewModelProvider(harness.intentionId),
    ) is BlockingRelationsSelectionPrepared;
}

Future<void> _finishSelectionRead(WidgetTester tester, _Harness harness) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
    final state = harness.container.read(
      blockingRelationsSelectionViewModelProvider(harness.intentionId),
    );
    if (state is! BlockingRelationsSelectionRefreshing &&
        (state is! BlockingRelationsSelectionPrepared ||
            find
                .byKey(const ValueKey('blocking-relations-confirm-list'))
                .evaluate()
                .isNotEmpty)) {
      return;
    }
  }
  fail('Проверка выбранного набора не завершилась.');
}

final class _Harness {
  final intentionId = testIntentionId(1);
  final repository = _CommandRepository();
  late ProviderContainer container;

  bool select(LongTermRelationSummary row) => container
      .read(blockingRelationsSelectionViewModelProvider(intentionId).notifier)
      .select(repository.rows[row.relation.id] = row);
}

final class _CommandRepository implements PersonalGraphRepository {
  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  final commands = <GraphCommand>[];
  final requests = <Completer<Object>>[];
  final rows = <LongTermRelationId, LongTermRelationSummary>{};
  final descriptions = <LongTermRelationId, String?>{};
  final _selectionUpdates =
      StreamController<SelectedRelationsReadResult>.broadcast(sync: true);
  SelectedRelationsQuery? _watchedQuery;
  GraphRevision _revision = const TestGraphRevision(2);
  int selectedReads = 0;
  int selectedWatches = 0;
  int relationWatches = 0;
  Set<LongTermRelationId> selectedIds = {};
  final _relationUpdates =
      <LongTermRelationId, StreamController<LongTermRelationReadResult>>{};
  LongTermRelationReadFailure? readFailure;
  bool Function()? isPrepared;

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) async => ResultSuccess(
    GraphSnapshot(
      value: testRelationCounts(),
      revision: const TestGraphRevision(1),
    ),
  );

  void emitRelation(
    LongTermRelationSummary row, {
    required GraphRevision revision,
    String? description,
  }) {
    rows[row.relation.id] = row;
    descriptions[row.relation.id] = description;
    _revision = revision;
    final query = _watchedQuery;
    if (query != null) {
      _selectionUpdates.add(_currentSelection(query));
    }
    _relationUpdates[row.relation.id]?.add(
      LongTermRelationReadSuccess(
        GraphSnapshot(
          value: LongTermRelationDetails(
            relation: row.relation,
            source: row.source,
            related: row.related,
            description: description == null
                ? null
                : LongTermRelationDescription.fromInput(description),
          ),
          revision: revision,
        ),
      ),
    );
  }

  void emitMissing(LongTermRelationId id, {required GraphRevision revision}) {
    rows.remove(id);
    _revision = revision;
    final query = _watchedQuery;
    if (query != null) _selectionUpdates.add(_currentSelection(query));
  }

  void emitSelectionFailure() => _selectionUpdates.add(
    const SelectedRelationsReadError(SelectedRelationsReadUnavailableFailure()),
  );

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) async {
    selectedReads++;
    selectedIds = query.relationIds;
    return _currentSelection(query);
  }

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => Stream.multi((controller) {
    selectedWatches++;
    selectedIds = query.relationIds;
    _watchedQuery = query;
    controller.addSync(_currentSelection(query));
    final subscription = _selectionUpdates.stream.listen(controller.addSync);
    controller.onCancel = () {
      _watchedQuery = null;
      return subscription.cancel();
    };
  });

  SelectedRelationsReadResult _currentSelection(SelectedRelationsQuery query) {
    final failure = readFailure;
    if (failure != null) {
      return SelectedRelationsReadError(switch (failure) {
        LongTermRelationReadUnavailableFailure() =>
          const SelectedRelationsReadUnavailableFailure(),
        LongTermRelationReadCorruptionFailure() =>
          const SelectedRelationsReadCorruptionFailure(),
        LongTermRelationReadUnexpectedFailure() =>
          const SelectedRelationsReadUnexpectedFailure(),
      });
    }
    return SelectedRelationsReadSuccess(
      GraphSnapshot(
        revision: _revision,
        value: SelectedRelationsSnapshot(
          query: query,
          entries: {
            for (final id in query.relationIds)
              id: switch (rows[id]) {
                null => SelectedRelationMissing(id),
                final row
                    when row.relation.sourceIntentionId != query.intentionId &&
                        row.relation.relatedIntentionId != query.intentionId =>
                  SelectedRelationNoLongerBlocking(id),
                final row => SelectedRelationPresent(
                  LongTermRelationDetails(
                    relation: row.relation,
                    source: row.source,
                    related: row.related,
                    description: descriptions[id] == null
                        ? null
                        : LongTermRelationDescription.fromInput(
                            descriptions[id]!,
                          ),
                  ),
                ),
              },
          },
        ),
      ),
    );
  }

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => Stream.value(
    ResultSuccess(
      GraphSnapshot(
        value: IntentionDetails(
          intention: testNeighborhoodIntention(id: id),
          relationCounts: testRelationCounts(),
        ),
        revision: const TestGraphRevision(1),
      ),
    ),
  );

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) {
    relationWatches++;
    if (!(isPrepared?.call() ?? false)) {
      return Stream.value(_currentRelation(id));
    }
    return Stream.multi((controller) {
      controller.addSync(_currentRelation(id));
      final subscription = _relationUpdates
          .putIfAbsent(id, () => StreamController.broadcast(sync: true))
          .stream
          .listen(controller.addSync);
      controller.onCancel = subscription.cancel;
    });
  }

  LongTermRelationReadResult _currentRelation(LongTermRelationId id) =>
      readFailure != null
      ? LongTermRelationReadError(readFailure!)
      : LongTermRelationReadSuccess(
          GraphSnapshot(
            value: switch (rows[id]) {
              null => null,
              final row => LongTermRelationDetails(
                relation: row.relation,
                source: row.source,
                related: row.related,
                description: null,
              ),
            },
            revision: const TestGraphRevision(2),
          ),
        );

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) async {
    commands.add(command);
    final request = Completer<Object>();
    requests.add(request);
    return await request.future as GraphCommandResult<T, F>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Неожиданный вызов репозитория: ${invocation.memberName}',
  );
}
