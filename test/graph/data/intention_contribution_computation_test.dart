import 'dart:math';
import 'dart:typed_data';

import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/contribution_reachability_reference.dart';

void main() {
  test('вес групп сохраняется в сводке, днях и конечных намерениях '
      'без умножения', () {
    IntentionContributionGroup<int> group({
      required List<int> seeds,
      required int? terminal,
      required int day,
      required int planned,
      required int completed,
      required IntentionContributionPathPosition position,
    }) => IntentionContributionGroup(
      seeds: seeds.map(_id).toList(),
      terminalIntentionId: terminal == null ? null : _id(terminal),
      calendarPart: day,
      pathPosition: position,
      counts: ContributionCounts(planned: planned, contribution: completed),
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
          seeds: [1, 2],
          terminal: 2,
          day: 5,
          planned: 5,
          completed: 2,
          position: ContributionBeforeTerminal(
            isRoot: true,
            followingRelationId: _rid(12),
          ),
        ),
        group(
          seeds: [2],
          terminal: 2,
          day: 12,
          planned: 4,
          completed: 1,
          position: const ContributionOutsidePath(),
        ),
        group(
          seeds: [3],
          terminal: 3,
          day: 12,
          planned: 2,
          completed: 0,
          position: const ContributionOutsidePath(),
        ),
        group(
          seeds: [3, 1],
          terminal: null,
          day: 12,
          planned: 3,
          completed: 3,
          position: const ContributionTerminalOnPath(isRoot: false),
        ),
        group(
          seeds: [4],
          terminal: 4,
          day: 5,
          planned: 7,
          completed: 7,
          position: const ContributionOutsidePath(),
        ),
      ],
    );

    expect(_counts(result.counts), (14, 6));
    expect(result.explicitPathActions, 8);
    expect(
      result.calendarCounts.map((day, value) => MapEntry(day, _counts(value))),
      {5: (5, 2), 12: (9, 4)},
    );
    expect(
      [
        for (final entry in result.terminalIntentions)
          (entry.intentionId, _counts(entry.counts)),
      ],
      [(_id(2), (9, 3)), (_id(3), (2, 0))],
    );
    expect(_relationValues(result), [(_rid(13), 11, 3), (_rid(12), 9, 3)]);
  });

  test('без активного графа сохраняет следующую архивированную связь, '
      'а пустой период даёт нули', () {
    final relations = [_relation(1, 2, archived: true)];
    final actions = <ContributionReferenceAction>[
      (path: [_id(1), _id(2)], completed: false),
    ];
    final result = _compute(relations, actions, 1);
    expect(_relationValues(result), [(_rid(1002), 1, 0)]);
    expect(result.explicitPathActions, 1);
    _expectReference(result, relations, actions, 1);
    final empty = _compute(relations, [], 1);
    expect(_counts(empty.counts), (0, 0));
    expect(empty.explicitPathActions, 0);
    expect(empty.calendarCounts, isEmpty);
    expect(empty.terminalIntentions, isEmpty);
    expect(empty.relations, isEmpty);
  });

  test('явные и неявные основания объединяются через границу 64 групп', () {
    final direct = [
      for (var target = 2; target <= 130; target++) _relation(1, target),
    ];
    final relations = [
      ...direct,
      _relation(1, 1000),
      for (var target = 2; target <= 130; target++) _relation(1000, target),
    ];
    final actions = <ContributionReferenceAction>[
      for (var i = 0; i < 129; i++)
        (path: [_id(1), direct[i].target], completed: i.isEven),
    ];
    final result = _compute(relations, actions, 1);
    expect(result.relations.length, 130);
    expect(result.relations.first.relationId, _rid(2000));
    expect(_counts(result.relations.first.counts), (129, 65));
    _expectReference(result, relations, actions, 1);
  });

  test('«Через связи» и разбивки совпадают с полными путями на '
      'воспроизводимых случайных графах с циклами', () {
    final random = Random(3202);
    for (var sample = 0; sample < 60; sample++) {
      final nodeCount = 4 + random.nextInt(12);
      final deleted = {
        for (var node = 1; node <= nodeCount; node++)
          if (random.nextInt(7) == 0) _id(node),
      };
      final relations = <ContributionReferenceRelation>[
        for (var source = 1; source <= nodeCount; source++)
          for (var target = 1; target <= nodeCount; target++)
            if (source != target &&
                !deleted.contains(_id(source)) &&
                !deleted.contains(_id(target)) &&
                random.nextInt(5) == 0)
              _relation(source, target, archived: random.nextInt(4) == 0),
      ];
      final actions = <ContributionReferenceAction>[];
      for (var index = 0; index < 100; index++) {
        final path = ([
          for (var node = 1; node <= nodeCount; node++) _id(node),
        ]..shuffle(random)).take(1 + random.nextInt(5)).toList();
        final action = (path: path, completed: random.nextBool());
        actions.add(action);
        if (random.nextInt(5) == 0) actions.add(action);
      }
      for (var intention = 1; intention <= nodeCount; intention++) {
        if (deleted.contains(_id(intention))) continue;
        _expectReference(
          _compute(relations, actions, intention, deleted: deleted),
          relations,
          actions,
          intention,
          deleted: deleted,
          reason: 'Граф $sample, намерение $intention, seed 3202',
        );
      }
    }
  });
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

/// Каждое действие — своя группа со всеми существующими намерениями пути
/// в опорном наборе: подсчёт не должен зависеть от сокращения набора.
IntentionContributionResult<int> _compute(
  List<ContributionReferenceRelation> relations,
  List<ContributionReferenceAction> actions,
  int intention, {
  Set<IntentionId> deleted = const {},
}) {
  final x = _id(intention);
  IntentionContributionGroup<int>? group(ContributionReferenceAction action) {
    final seeds = [
      for (final node in action.path)
        if (!deleted.contains(node)) node,
    ];
    if (seeds.isEmpty) return null;
    final position = action.path.indexOf(x);
    final terminal = action.path.last;
    final isLast = position == action.path.length - 1;
    final following = position < 0 || isLast
        ? null
        : relations
              .where(
                (r) => r.source == x && r.target == action.path[position + 1],
              )
              .firstOrNull;
    return IntentionContributionGroup(
      seeds: seeds,
      terminalIntentionId: terminal == x || deleted.contains(terminal)
          ? null
          : terminal,
      calendarPart: 5,
      pathPosition: position < 0
          ? const ContributionOutsidePath()
          : isLast
          ? ContributionTerminalOnPath(isRoot: position == 0)
          : ContributionBeforeTerminal(
              isRoot: position == 0,
              followingRelationId: following == null
                  ? null
                  : _relationId(following),
            ),
      counts: ContributionCounts(
        planned: 1,
        contribution: action.completed ? 1 : 0,
      ),
    );
  }

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
    groups: [for (final action in actions) ?group(action)],
  );
}

void _expectReference(
  IntentionContributionResult<int> result,
  List<ContributionReferenceRelation> relations,
  List<ContributionReferenceAction> actions,
  int intention, {
  Set<IntentionId> deleted = const {},
  String? reason,
}) {
  final reference = referenceIntentionActionStatistics(
    intentionId: _id(intention),
    relations: relations,
    actions: actions,
    deleted: deleted,
  );
  expect(_counts(result.counts), (
    reference.throughRelations.planned,
    reference.throughRelations.contribution,
  ), reason: reason);
  expect(
    result.explicitPathActions,
    reference.explicitPathActions,
    reason: reason,
  );
  expect(
    {
      for (final entry in result.terminalIntentions)
        entry.intentionId: _counts(entry.counts),
    },
    {
      for (final entry in reference.terminalIntentions.entries)
        entry.key: (entry.value.planned, entry.value.contribution),
    },
    reason: reason,
  );
  expect(
    {
      for (final entry in result.relations)
        entry.relationId: _counts(entry.counts),
    },
    {
      for (final entry in reference.relations.entries)
        _relationId(entry.key): (entry.value.planned, entry.value.contribution),
    },
    reason: reason,
  );
  for (final entries in [
    [for (final entry in result.terminalIntentions) entry.counts],
    [for (final entry in result.relations) entry.counts],
  ]) {
    for (var i = 1; i < entries.length; i++) {
      final (previous, current) = (entries[i - 1], entries[i]);
      expect(
        previous.planned > current.planned ||
            (previous.planned == current.planned &&
                previous.contribution >= current.contribution),
        isTrue,
        reason: reason,
      );
    }
  }
}

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
