import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'после выбора действия открывает подтверждение, отмена не пишет граф',
    (tester) async {
      final repository = _PathRepository();
      addTearDown(repository.dispose);
      await _pumpPage(tester, repository);
      repository.complete(0, [_edge(1, 2, 1)]);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('choice-path-continue-${_relation(1).toCanonicalString()}'),
        ),
      );
      await tester.pump();
      repository.complete(1, [], ready: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choice-path-select-action')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('choice-path-open-confirmation')),
      );
      await tester.tap(
        find.byKey(const ValueKey('choice-path-open-confirmation')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-choice-date')), findsOneWidget);
      expect(find.textContaining('Намерение 1'), findsWidgets);
      expect(find.textContaining('Намерение 2'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-cancel')),
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-cancel')));
      await tester.pump();
      expect(repository.commands, 0);
    },
  );

  testWidgets(
    'передаёт в подтверждение весь многошаговый путь в выбранном порядке',
    (tester) async {
      final repository = _PathRepository();
      addTearDown(repository.dispose);
      await _pumpPage(tester, repository);
      repository.complete(0, [_edge(1, 2, 1)]);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('choice-path-continue-${_relation(1).toCanonicalString()}'),
        ),
      );
      await tester.pump();
      repository.complete(1, [_edge(2, 3, 2)]);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('choice-path-continue-${_relation(2).toCanonicalString()}'),
        ),
      );
      await tester.pump();
      repository.complete(2, [], ready: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choice-path-select-action')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('choice-path-open-confirmation')),
      );
      await tester.tap(
        find.byKey(const ValueKey('choice-path-open-confirmation')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-date')),
        '2026-12-31',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
      await tester.pump();
      expect(repository.commands, 1);
      expect(
        repository.lastCommand!.path.steps
            .map((step) => step.relationId)
            .toList(),
        [_relation(1), _relation(2)],
      );
      expect(repository.lastCommand!.selectedIntentionId, _intention(3));
    },
  );

  testWidgets('показывает путь, выбор действия и возврат к ветви', (
    tester,
  ) async {
    final repository = _PathRepository();
    addTearDown(repository.dispose);
    await _pumpPage(tester, repository);
    repository.complete(0, [_edge(1, 2, 1)]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('choice-path-select-action')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        ValueKey('choice-path-continue-${_relation(1).toCanonicalString()}'),
      ),
    );
    await tester.pump();
    repository.complete(1, [_edge(2, 3, 2)], ready: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Намерение 1'), findsWidgets);
    expect(find.textContaining('Намерение 2'), findsWidgets);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('Шаг 1:.*нужно.*P1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choice-path-select-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('choice-path-continue-${_relation(2).toCanonicalString()}'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('choice-path-select-action')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('choice-path-selected-action')),
      findsOneWidget,
    );
    expect(repository.commands, 0);

    await tester.tap(find.byKey(const ValueKey('choice-path-back-0')));
    await tester.pump();
    repository.complete(2, [_edge(1, 4, 3)]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('choice-path-selected-action')),
      findsNothing,
    );
    expect(
      find.byKey(
        ValueKey('choice-path-continue-${_relation(3).toCanonicalString()}'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('различает отсутствие пути, конфликт и временную ошибку', (
    tester,
  ) async {
    final repository = _PathRepository();
    addTearDown(repository.dispose);
    await _pumpPage(tester, repository);
    repository.complete(0, []);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('choice-path-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choice-path-select-action')),
      findsNothing,
    );

    repository.emitRevision(2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('choice-path-conflict')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choice-path-refresh')));
    await tester.pump();
    repository.fail(1, const ChoicePathContinuationUnavailableFailure());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('choice-path-failure')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choice-path-retry')));
    await tester.pump();
    repository.complete(2, [_edge(1, 2, 1)], revision: 2);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey('choice-path-continue-${_relation(1).toCanonicalString()}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('порции и семантика доступны на английском с крупным текстом', (
    tester,
  ) async {
    final repository = _PathRepository();
    addTearDown(repository.dispose);
    await _pumpPage(
      tester,
      repository,
      locale: const Locale('en'),
      textScale: 2,
    );
    repository.complete(0, [_edge(1, 2, 1)], cursor: _Cursor());
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    expect(find.text('Choose an action'), findsNothing);
    expect(find.byKey(const ValueKey('choice-path-load-more')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('choice-path-load-more')),
    );
    await tester.tap(find.byKey(const ValueKey('choice-path-load-more')));
    await tester.pump();
    expect(repository.queries[1].cursor, isA<_Cursor>());
    repository.complete(1, [_edge(1, 3, 2, type: LongTermRelationType.can)]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey('choice-path-continue-${_relation(2).toCanonicalString()}'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('.*can.*', caseSensitive: false)),
      findsWidgets,
    );
    semantics.dispose();
  });

  testWidgets(
    'нижний обход показывает направление связей и подтверждает основание',
    (tester) async {
      final repository = _PathRepository();
      addTearDown(repository.dispose);
      await _pumpPage(
        tester,
        repository,
        direction: ChoicePathDraftDirection.bottomUp,
        startingId: 3,
      );
      expect(
        repository.queries[0].draft.direction,
        ChoicePathDraftDirection.bottomUp,
      );
      repository.complete(0, [_edge(2, 3, 1)]);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('choice-path-select-action')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(
          ValueKey('choice-path-continue-${_relation(1).toCanonicalString()}'),
        ),
      );
      await tester.pump();
      repository.complete(1, [_edge(1, 2, 2)], ready: true);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Выбранное действие: Намерение 3'),
        findsOneWidget,
      );
      expect(find.textContaining('Основание: Намерение 2'), findsOneWidget);
      expect(find.textContaining('от действия к основанию'), findsWidgets);
      expect(find.textContaining('от основания к действию'), findsWidgets);
      expect(
        find.byKey(const ValueKey('choice-path-select-source')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey('choice-path-continue-${_relation(2).toCanonicalString()}'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('choice-path-select-source')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('choice-path-selected-source')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('choice-path-open-confirmation')),
        findsOneWidget,
      );
      expect(repository.commands, 0);

      final nextStep = find.byKey(
        ValueKey('choice-path-continue-${_relation(2).toCanonicalString()}'),
      );
      await tester.scrollUntilVisible(nextStep, 180);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(nextStep);
      await tester.pump();
      repository.complete(2, []);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('choice-path-selected-source')),
        findsNothing,
      );
      expect(find.textContaining('Основание: Намерение 1'), findsOneWidget);
      expect(
        find.textContaining('Выбранное действие: Намерение 3'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('choice-path-back-1')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('choice-path-back-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choice-path-back-1')));
      await tester.pump();
      repository.complete(3, [_edge(4, 2, 3, type: LongTermRelationType.can)]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Основание: Намерение 2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('choice-path-select-source')),
        findsOneWidget,
      );
      final alternateStep = find.byKey(
        ValueKey('choice-path-continue-${_relation(3).toCanonicalString()}'),
      );
      await tester.scrollUntilVisible(alternateStep, 150);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(alternateStep);
      await tester.pump();
      repository.complete(4, []);
      await tester.pumpAndSettle();
      expect(find.textContaining('Основание: Намерение 4'), findsOneWidget);
      expect(
        find.textContaining('Выбранное действие: Намерение 3'),
        findsOneWidget,
      );
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Шаг 1:.*можно.*P1')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('нижний нулевой путь и ошибка не выглядят подтверждением', (
    tester,
  ) async {
    final repository = _PathRepository();
    addTearDown(repository.dispose);
    await _pumpPage(
      tester,
      repository,
      direction: ChoicePathDraftDirection.bottomUp,
      startingId: 3,
    );
    repository.complete(0, []);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('choice-path-select-source')),
      findsNothing,
    );
    expect(
      find.textContaining('Выбранное действие: Намерение 3'),
      findsOneWidget,
    );
    expect(
      find.textContaining('нет допустимых входящих связей'),
      findsOneWidget,
    );
    repository.emitRevision(2);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choice-path-refresh')));
    await tester.pump();
    repository.fail(1, const ChoicePathContinuationUnavailableFailure());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('choice-path-select-source')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('choice-path-retry')), findsOneWidget);
  });

  testWidgets('нижний обход доступен по-английски при крупном тексте', (
    tester,
  ) async {
    final repository = _PathRepository();
    addTearDown(repository.dispose);
    await _pumpPage(
      tester,
      repository,
      direction: ChoicePathDraftDirection.bottomUp,
      startingId: 3,
      locale: const Locale('en'),
      textScale: 2,
    );
    repository.complete(0, [_edge(2, 3, 1)], cursor: _Cursor());
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected action: Намерение 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('choice-path-load-more')), findsOneWidget);
    final loadMore = find.byKey(const ValueKey('choice-path-load-more'));
    await tester.scrollUntilVisible(loadMore, 150);
    await tester.pumpAndSettle();
    await tester.tap(loadMore);
    await tester.pump();
    repository.complete(1, [_edge(4, 3, 2, type: LongTermRelationType.can)]);
    await tester.pumpAndSettle();
    final loadedStep = find.byKey(
      ValueKey('choice-path-continue-${_relation(2).toCanonicalString()}'),
    );
    await tester.scrollUntilVisible(loadedStep, 150);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(loadedStep);
    await tester.pump();
    repository.complete(2, []);
    await tester.pumpAndSettle();
    expect(find.textContaining('Source: Намерение 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choice-path-select-source')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('choice-path-back-0')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('choice-path-back-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choice-path-back-0')));
    await tester.pump();
    repository.complete(3, []);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('choice-path-select-source')),
      findsNothing,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _PathRepository repository, {
  Locale locale = const Locale('ru'),
  double textScale = 1,
  ChoicePathDraftDirection direction = ChoicePathDraftDirection.topDown,
  int startingId = 1,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: direction == ChoicePathDraftDirection.topDown
          ? ChoicePathPage(sourceIntentionId: _intention(startingId))
          : ChoicePathPage.fromAction(
              actionIntentionId: _intention(startingId),
            ),
    ),
  ),
);

final class _PathRepository implements PersonalGraphRepository {
  final queries = <ChoicePathContinuationQuery>[];
  final _requests = <Completer<ChoicePathContinuationResult>>[];
  final _observations =
      StreamController<Result<GraphSnapshot<IntentionDetails?>>>.broadcast(
        sync: true,
      );
  var commands = 0;
  CreateDailyChoice? lastCommand;

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) {
    queries.add(query);
    final request = Completer<ChoicePathContinuationResult>();
    _requests.add(request);
    return request.future;
  }

  void complete(
    int index,
    List<LongTermRelationSummary> items, {
    int revision = 1,
    bool ready = false,
    ChoicePathContinuationCursor? cursor,
  }) {
    final draft = queries[index].draft;
    _requests[index].complete(
      ChoicePathContinuationSuccess(
        ChoicePathContinuationsPage(
          draft: draft,
          current: _current(draft.currentIntentionId, ready: ready),
          items: items,
          nextCursor: cursor,
          revision: _Revision(revision),
        ),
      ),
    );
  }

  void fail(int index, ChoicePathContinuationFailure failure) =>
      _requests[index].complete(ChoicePathContinuationError(failure));

  void emitRevision(int revision) => _observations.add(
    ResultSuccess(
      GraphSnapshot(
        value: IntentionDetails(
          intention: _current(_intention(1)),
          relationCounts: RelationCounts(
            activeNeedIncoming: 0,
            activeNeedOutgoing: 0,
            activeCanIncoming: 0,
            activeCanOutgoing: 0,
            archivedNeedIncoming: 0,
            archivedNeedOutgoing: 0,
            archivedCanIncoming: 0,
            archivedCanOutgoing: 0,
          ),
        ),
        revision: _Revision(revision),
      ),
    ),
  );

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => _observations.stream;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) {
    commands++;
    lastCommand = command as CreateDailyChoice;
    return Completer<GraphCommandResult<TSuccess, TFailure>>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void dispose() => _observations.close();
}

final class _Cursor implements ChoicePathContinuationCursor {}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is! _Revision
      ? GraphRevisionOrder.differentEpoch
      : switch (value.compareTo(other.value)) {
          < 0 => GraphRevisionOrder.older,
          > 0 => GraphRevisionOrder.newer,
          _ => GraphRevisionOrder.same,
        };
}

IntentionId _intention(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8001-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

Intention _current(IntentionId id, {bool ready = false}) => Intention(
  id: id,
  title: 'Намерение ${int.parse(id.toCanonicalString().substring(24))}',
  description: null,
  readiness: ready ? IntentionReadiness.ready : IntentionReadiness.notReady,
  archiveState: IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

LongTermRelationSummary _edge(
  int source,
  int related,
  int number, {
  LongTermRelationType type = LongTermRelationType.need,
}) => LongTermRelationSummary(
  relation: LongTermRelation(
    id: _relation(number),
    sourceIntentionId: _intention(source),
    relatedIntentionId: _intention(related),
    type: type,
    priority: RelationPriority.p1,
    scope: RelationScope.active,
    creationSequence: RelationCreationSequence(number),
  ),
  source: RelationParticipantSummary(
    id: _intention(source),
    title: 'Намерение $source',
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 1,
  ),
  related: RelationParticipantSummary(
    id: _intention(related),
    title: 'Намерение $related',
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 0,
  ),
  hasDescription: false,
);
