import 'dart:math';
import 'dart:typed_data';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/contribution_reachability_reference.dart';

void main() {
  test(
    'Цикл сохраняет предшественника X и различает пути к одному действию',
    () {
      final graph = _graph([(2, 1), (1, 4), (1, 2), (3, 1)]);
      final groups = [_group(predecessor: 2), _group(predecessor: 3)];
      IntentionContributionResult<int> compute(int length) =>
          computeIntentionContribution(
            graph: graph,
            intentionId: _id(1),
            groups: groups.take(length).toList(),
            activeOutgoingRelations: [
              (relationId: _rid(12), targetId: _id(2)),
              (relationId: _rid(14), targetId: _id(4)),
            ],
          );

      final first = compute(1);
      expect(_relationValues(first), [(_rid(14), 1, 1), (_rid(12), 1, 1)]);
      final both = compute(2);
      expect(_relationValues(both), [(_rid(14), 2, 2), (_rid(12), 1, 1)]);
      expect(both.summary.counts.planned, 2);
      expect(both.summary.counts.contribution, 2);
      expect(both.explicitPathChoices, 2);
      expect(both.selectedActions.single.intentionId, _id(4));
      expect(both.selectedActions.single.counts.planned, 2);
      expect(both.calendarCounts[5]!.contribution, 2);
    },
  );

  test(
    'Архивированная следующая связь сохраняет только своё явное основание',
    () {
      final relations = [
        _relation(2, 1),
        _relation(1, 4, archived: true),
        _relation(1, 3, archived: true),
        _relation(3, 4),
      ];
      final choices = <ContributionReferenceChoice>[
        (path: relations.sublist(0, 2), completed: true),
        (path: relations.sublist(0, 2), completed: false),
        (path: [relations.last], completed: true),
      ];

      final result = _computeChoices(relations, choices, 1);
      expect(_relationValues(result), [(_rid(1004), 2, 1)]);
      expect(result.summary.counts.planned, 2);
      expect(result.explicitPathChoices, 2);
      _expectReference(result, relations, choices, 1);
    },
  );

  test(
    'Выбранное действие X входит в сводку, но не в разбивку даже при цикле',
    () {
      final relations = [_relation(2, 1), _relation(1, 2)];
      final choices = <ContributionReferenceChoice>[
        (path: [relations.first], completed: true),
      ];
      final result = _computeChoices(relations, choices, 1);

      expect(result.summary.counts.planned, 1);
      expect(result.explicitPathChoices, 1);
      expect(result.selectedActions.single.intentionId, _id(1));
      expect(result.relations, isEmpty);
      _expectReference(result, relations, choices, 1);
    },
  );

  test(
    'Вес дубликатов сохраняется в сводке, днях и действиях без умножения',
    () {
      final fifth = CalendarDate.fromParts(2026, 10, 5);
      final twelfth = CalendarDate.fromParts(2026, 10, 12);
      IntentionContributionGroup<CalendarDate> group({
        required int action,
        required CalendarDate day,
        required int planned,
        required int completed,
        required int missed,
        required int upcoming,
        required IntentionContributionPathPosition position,
      }) => IntentionContributionGroup(
        seeds: [_id(action)],
        selectedActionId: _id(action),
        calendarPart: day,
        pathPosition: position,
        summary: StatisticsPeriodSummary(
          counts: ContributionCounts(planned: planned, contribution: completed),
          uncompleted: UncompletedSplit(missed: missed, upcoming: upcoming),
        ),
      );
      final result = computeIntentionContribution(
        graph: _graph([(1, 2), (1, 3), (3, 2)]),
        intentionId: _id(1),
        activeOutgoingRelations: [
          (relationId: _rid(12), targetId: _id(2)),
          (relationId: _rid(13), targetId: _id(3)),
        ],
        groups: [
          group(
            action: 2,
            day: fifth,
            planned: 5,
            completed: 2,
            missed: 3,
            upcoming: 0,
            position: ContributionBeforeSelectedAction(
              followingRelationId: _rid(12),
            ),
          ),
          group(
            action: 2,
            day: twelfth,
            planned: 4,
            completed: 1,
            missed: 0,
            upcoming: 3,
            position: const ContributionOutsidePath(),
          ),
          group(
            action: 3,
            day: twelfth,
            planned: 2,
            completed: 0,
            missed: 0,
            upcoming: 2,
            position: const ContributionOutsidePath(),
          ),
          group(
            action: 4,
            day: fifth,
            planned: 7,
            completed: 7,
            missed: 0,
            upcoming: 0,
            position: const ContributionOutsidePath(),
          ),
        ],
      );

      expect(_counts(result.summary.counts), (11, 3));
      expect(result.summary.uncompleted.missed, 3);
      expect(result.summary.uncompleted.upcoming, 5);
      expect(result.explicitPathChoices, 5);
      expect(
        result.calendarCounts.map(
          (day, value) => MapEntry(day, _counts(value)),
        ),
        {fifth: (5, 2), twelfth: (6, 1)},
      );
      expect(
        [
          for (final entry in result.selectedActions)
            (entry.intentionId, _counts(entry.counts)),
        ],
        [(_id(2), (9, 3)), (_id(3), (2, 0))],
      );
      expect(_relationValues(result), [(_rid(13), 11, 3), (_rid(12), 9, 3)]);
    },
  );

  test('Без активного графа сохраняет изолированный путь, а пустой период даёт нули', () {
    final relations = [_relation(1, 2, archived: true)];
    final result = _computeChoices(relations, [
      (path: relations, completed: false),
    ], 1);
    expect(_relationValues(result), [(_rid(1002), 1, 0)]);
    expect(result.explicitPathChoices, 1);
    final empty = _computeChoices(relations, [], 1);
    expect(_counts(empty.summary.counts), (0, 0));
    expect(empty.explicitPathChoices, 0);
    expect(empty.calendarCounts, isEmpty);
    expect(empty.selectedActions, isEmpty);
    expect(empty.relations, isEmpty);
  });

  test('Явные и неявные основания объединяются через границу 64 групп', () {
    final direct = [
      for (var action = 2; action <= 130; action++) _relation(1, action),
    ];
    final relations = [
      ...direct,
      _relation(1, 1000),
      for (var action = 2; action <= 130; action++) _relation(1000, action),
    ];
    final choices = <ContributionReferenceChoice>[
      for (var i = 0; i < 129; i++) (path: [direct[i]], completed: i.isEven),
    ];
    final result = _computeChoices(relations, choices, 1);
    expect(result.relations.length, 130);
    expect(result.relations.first.relationId, _rid(2000));
    expect(_counts(result.relations.first.counts), (129, 65));
    _expectReference(result, relations, choices, 1);
  });

  test(
    'Разбивки совпадают с полными путями на воспроизводимых случайных графах',
    () {
      final random = Random(3202);
      for (var sample = 0; sample < 60; sample++) {
        final nodeCount = 4 + random.nextInt(15);
        final relations = <ContributionReferenceRelation>[
          for (var source = 1; source <= nodeCount; source++)
            for (var target = 1; target <= nodeCount; target++)
              if (source != target && random.nextInt(5) == 0)
                _relation(source, target, archived: random.nextInt(4) == 0),
        ];
        final choices = <ContributionReferenceChoice>[];
        for (var index = 0; index < 140; index++) {
          var current = _id(1 + random.nextInt(nodeCount));
          final visited = {current};
          final path = <ContributionReferenceRelation>[];
          for (var step = 0; step < 1 + random.nextInt(6); step++) {
            final outgoing = relations
                .where(
                  (relation) =>
                      relation.source == current &&
                      !visited.contains(relation.target),
                )
                .toList();
            if (outgoing.isEmpty) break;
            final relation = outgoing[random.nextInt(outgoing.length)];
            path.add(relation);
            current = relation.target;
            visited.add(current);
          }
          if (path.isEmpty) continue;
          final choice = (path: path, completed: random.nextBool());
          choices.add(choice);
          if (random.nextInt(5) == 0) choices.add(choice);
        }
        for (var intention = 1; intention <= nodeCount; intention++) {
          _expectReference(
            _computeChoices(relations, choices, intention),
            relations,
            choices,
            intention,
            reason: 'Граф $sample, намерение $intention, seed 3202',
          );
        }
      }
    },
  );
}

(int, int) _counts(ContributionCounts counts) =>
    (counts.planned, counts.contribution);

ContributionReferenceRelation _relation(
  int source,
  int target, {
  bool archived = false,
}) => (source: _id(source), target: _id(target), archived: archived);

int _number(IntentionId id) =>
    int.parse(id.toCanonicalString().substring(24), radix: 16);

LongTermRelationId _relationId(ContributionReferenceRelation relation) =>
    _rid(_number(relation.source) * 1000 + _number(relation.target));

IntentionContributionResult<int> _computeChoices(
  List<ContributionReferenceRelation> relations,
  List<ContributionReferenceChoice> choices,
  int intention,
) {
  final x = _id(intention);
  return computeIntentionContribution(
    graph: _graph([
      for (final relation in relations)
        if (!relation.archived)
          (_number(relation.source), _number(relation.target)),
    ]),
    intentionId: x,
    activeOutgoingRelations: [
      for (final relation in relations)
        if (relation.source == x && !relation.archived)
          (relationId: _relationId(relation), targetId: relation.target),
    ],
    groups: [for (final choice in choices) _choiceGroup(choice, x)],
  );
}

IntentionContributionGroup<int> _choiceGroup(
  ContributionReferenceChoice choice,
  IntentionId x,
) {
  final followingIndex = choice.path.indexWhere((step) => step.source == x);
  return IntentionContributionGroup(
    seeds: {
      choice.path.last.target,
      for (final step in choice.path)
        if (step.archived) step.source,
    }.toList(),
    selectedActionId: choice.path.last.target,
    calendarPart: 5,
    pathPosition: choice.path.last.target == x
        ? const ContributionSelectedOnPath()
        : followingIndex < 0
        ? const ContributionOutsidePath()
        : ContributionBeforeSelectedAction(
            predecessorId: followingIndex == 0
                ? null
                : choice.path[followingIndex - 1].source,
            followingRelationId: _relationId(choice.path[followingIndex]),
          ),
    summary: StatisticsPeriodSummary(
      counts: ContributionCounts(
        planned: 1,
        contribution: choice.completed ? 1 : 0,
      ),
      uncompleted: UncompletedSplit(
        missed: choice.completed ? 0 : 1,
        upcoming: 0,
      ),
    ),
  );
}

void _expectReference(
  IntentionContributionResult<int> result,
  List<ContributionReferenceRelation> relations,
  List<ContributionReferenceChoice> choices,
  int intention, {
  String? reason,
}) {
  final x = _id(intention);
  final reference = referenceContributionCounts(
    relations: relations,
    choices: choices,
  )[x];
  expect(_counts(result.summary.counts), (
    reference?.planned ?? 0,
    reference?.contribution ?? 0,
  ), reason: reason);
  final relationReference = referenceIntentionRelationCounts(
    intentionId: x,
    relations: relations,
    choices: choices,
  );
  expect(
    {
      for (final entry in result.relations)
        entry.relationId: _counts(entry.counts),
    },
    {
      for (final entry in relationReference.entries)
        _relationId(entry.key): (entry.value.planned, entry.value.contribution),
    },
    reason: reason,
  );
  expect(
    result.explicitPathChoices,
    choices
        .where(
          (choice) =>
              choice.path.any((step) => step.source == x || step.target == x),
        )
        .length,
    reason: reason,
  );
}

IntentionContributionGroup<int> _group({required int predecessor}) =>
    IntentionContributionGroup(
      seeds: [_id(4)],
      selectedActionId: _id(4),
      calendarPart: 5,
      pathPosition: ContributionBeforeSelectedAction(
        predecessorId: _id(predecessor),
        followingRelationId: _rid(14),
      ),
      summary: StatisticsPeriodSummary(
        counts: ContributionCounts(planned: 1, contribution: 1),
        uncompleted: UncompletedSplit(missed: 0, upcoming: 0),
      ),
    );

List<(LongTermRelationId, int, int)> _relationValues<T extends Object>(
  IntentionContributionResult<T> result,
) => [
  for (final entry in result.relations)
    (entry.relationId, entry.counts.planned, entry.counts.contribution),
];

ContributionRelationGraph _graph(List<(int, int)> edges) {
  final ids = {
    for (final (a, b) in edges) ...[a, b],
  }.toList();
  final indexes = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final children = List.generate(ids.length, (_) => <int>[]);
  final parents = List.generate(ids.length, (_) => <int>[]);
  for (final (a, b) in edges) {
    children[indexes[a]!].add(indexes[b]!);
    parents[indexes[b]!].add(indexes[a]!);
  }
  return ContributionRelationGraph(
    intentionIds: ids.map(_id).toList(),
    childOffsets: _offsets(children),
    children: Uint32List.fromList(children.expand((row) => row).toList()),
    parentOffsets: _offsets(parents),
    parents: Uint32List.fromList(parents.expand((row) => row).toList()),
  );
}

Uint32List _offsets(List<List<int>> rows) {
  final result = Uint32List(rows.length + 1);
  for (var i = 0; i < rows.length; i++) {
    result[i + 1] = result[i] + rows[i].length;
  }
  return result;
}

String _uuid(int number) =>
    '00000000-0000-4000-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _id(int number) => switch (IntentionId.decode(_uuid(number))) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Неверный тестовый UUID'),
};

LongTermRelationId _rid(int number) =>
    switch (LongTermRelationId.decode(_uuid(number))) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Неверный тестовый UUID',
      ),
    };
