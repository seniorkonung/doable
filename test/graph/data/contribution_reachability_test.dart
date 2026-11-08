import 'dart:math';
import 'dart:typed_data';

import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/contribution_reachability_reference.dart';

void main() {
  test('Пустой период не создаёт элементы даже при наличии связей', () {
    expect(computeContributionReachability(_graph([(1, 2)]), []), isEmpty);
  });

  test('Без активных связей сохраняет изолированные опорные намерения', () {
    final result = computeContributionReachability(_graph([]), [
      _group([1, 2], planned: 3, contribution: 2),
      _group([2], planned: 2, contribution: 0),
      _group([3], planned: 1, contribution: 0),
    ]);

    expect(_values(result), [(_id(2), 5, 2), (_id(1), 3, 2), (_id(3), 1, 0)]);
  });

  test('Циклы и несколько цепочек засчитывают вес группы один раз', () {
    final result = computeContributionReachability(
      _graph([(1, 2), (1, 3), (2, 4), (3, 4), (4, 2), (4, 5), (6, 7)]),
      [
        _group([2, 5], planned: 7, contribution: 4),
      ],
    );

    expect(_values(result), [for (var id = 5; id >= 1; id--) (_id(id), 7, 4)]);
  });

  test('Неактивные звенья различают основания одного пути и сохраняют '
      'дубликаты', () {
    final relations = [
      _relation(1, 2),
      _relation(2, 3, archived: true),
      _relation(3, 4),
      _relation(5, 4, archived: true),
      _relation(6, 1),
      _relation(7, 5),
      _relation(8, 4, archived: true),
      _relation(9, 3),
    ];
    final actions = <ContributionReferenceAction>[
      (path: _ids([1, 2, 3, 4]), completed: true),
      (path: _ids([1, 2, 3, 4]), completed: true),
      (path: _ids([5, 4]), completed: false),
    ];
    final result = _computeActions(relations, actions);

    expect(_values(result), [
      for (final id in [9, 4, 3]) (_id(id), 3, 2),
      for (final id in [6, 2, 1]) (_id(id), 2, 2),
      (_id(7), 1, 0),
      (_id(5), 1, 0),
    ]);
    _expectReference(result, relations, actions);
  });

  test(
    'Архивирование конечного намерения с его связями сохраняет явный путь',
    () {
      final relations = [
        _relation(1, 2, archived: true),
        _relation(3, 2, archived: true),
        _relation(5, 1),
      ];
      final actions = <ContributionReferenceAction>[
        (path: _ids([1, 2]), completed: true),
      ];
      final result = _computeActions(relations, actions);

      expect(_values(result), [
        for (final id in [5, 2, 1]) (_id(id), 1, 1),
      ]);
      _expectReference(result, relations, actions);
    },
  );

  test('Удалённое намерение пути не засчитывается и не ведёт к вкладу', () {
    final relations = [_relation(4, 3), _relation(5, 1)];
    final actions = <ContributionReferenceAction>[
      (path: _ids([1, 7, 3]), completed: true),
      (path: _ids([7]), completed: true),
    ];
    final result = _computeActions(relations, actions, deleted: {_id(7)});

    expect(_values(result), [
      for (final id in [5, 4, 3, 1]) (_id(id), 1, 1),
    ]);
    _expectReference(result, relations, actions, deleted: {_id(7)});
  });

  for (final groupCount in [63, 64, 65, 129]) {
    test('Суммирует все байты и пачки при числе групп $groupCount', () {
      final result = computeContributionReachability(
        _graph([for (var i = 1; i <= groupCount; i++) (1000, i)]),
        [
          for (var i = 1; i <= groupCount; i++)
            _group([i], planned: i, contribution: i.isEven ? i : 0),
        ],
      );
      final expected = [
        for (var i = 1; i <= groupCount; i++) (_id(i), i, i.isEven ? i : 0),
      ]..sort(_compareValues);
      expect(_values(result), [
        (
          _id(1000),
          groupCount * (groupCount + 1) ~/ 2,
          (groupCount ~/ 2) * (groupCount ~/ 2 + 1),
        ),
        ...expected,
      ]);
    });
  }

  test('Новая активная связь меняет вклад уже сохранённого действия', () {
    final original = [_relation(1, 2)];
    final actions = <ContributionReferenceAction>[
      (path: _ids([1, 2]), completed: true),
    ];
    final before = _computeActions(original, actions);
    final after = _computeActions([...original, _relation(3, 2)], actions);

    expect(_values(before), [(_id(2), 1, 1), (_id(1), 1, 1)]);
    expect(_values(after), [(_id(3), 1, 1), (_id(2), 1, 1), (_id(1), 1, 1)]);
  });

  test('Совпадает с полными путями на воспроизводимых случайных графах', () {
    final random = Random(2303);
    for (var sample = 0; sample < 120; sample++) {
      final nodeCount = 4 + random.nextInt(24);
      final deleted = {
        for (var node = 1; node <= nodeCount; node++)
          if (random.nextInt(8) == 0) _id(node),
      };
      final relations = <ContributionReferenceRelation>[
        for (var source = 1; source <= nodeCount; source++)
          for (var target = 1; target <= nodeCount; target++)
            if (source != target &&
                !deleted.contains(_id(source)) &&
                !deleted.contains(_id(target)) &&
                random.nextInt(6) == 0)
              _relation(source, target, archived: random.nextInt(4) == 0),
      ];
      final actions = <ContributionReferenceAction>[];
      for (var action = 0; action < 140; action++) {
        // Звенья сохранённого пути не обязаны совпадать с текущими связями.
        final path = <IntentionId>[];
        for (var step = 0; step < 1 + random.nextInt(6); step++) {
          final linked = path.isEmpty
              ? const <ContributionReferenceRelation>[]
              : relations
                    .where(
                      (edge) =>
                          edge.source == path.last &&
                          !path.contains(edge.target),
                    )
                    .toList();
          final next = linked.isNotEmpty && random.nextBool()
              ? linked[random.nextInt(linked.length)].target
              : _id(1 + random.nextInt(nodeCount));
          if (!path.contains(next)) path.add(next);
        }
        final saved = (path: path, completed: random.nextBool());
        actions.add(saved);
        if (random.nextInt(5) == 0) actions.add(saved);
      }
      _expectReference(
        _computeActions(relations, actions, deleted: deleted),
        relations,
        actions,
        deleted: deleted,
        reason: 'Случайный граф $sample, seed 2303',
      );
    }
  });
}

ContributionReferenceRelation _relation(
  int source,
  int target, {
  bool archived = false,
}) => (source: _id(source), target: _id(target), archived: archived);

/// Опорные намерения действия выбираются так же, как при подготовке групп
/// Главной: существующие намерения пути, кроме тех, за которыми в пути идёт
/// следующее по активной связи их пары.
List<ContributionReachabilityEntry> _computeActions(
  List<ContributionReferenceRelation> relations,
  List<ContributionReferenceAction> actions, {
  Set<IntentionId> deleted = const {},
}) {
  final active = {
    for (final relation in relations)
      if (!relation.archived) (relation.source, relation.target),
  };
  final graph = _idGraph(active.toList());
  final grouped = <String, ContributionSeedGroup>{};
  for (final action in actions) {
    final path = action.path;
    final seeds = [
      for (var i = 0; i < path.length; i++)
        if (!deleted.contains(path[i]) &&
            !(i + 1 < path.length && active.contains((path[i], path[i + 1]))))
          path[i],
    ]..sort();
    if (seeds.isEmpty) continue;
    final key = seeds.map((id) => id.toCanonicalString()).join(',');
    final previous = grouped[key]?.counts;
    grouped[key] = ContributionSeedGroup(
      seeds: seeds,
      counts: ContributionCounts(
        planned: (previous?.planned ?? 0) + 1,
        contribution:
            (previous?.contribution ?? 0) + (action.completed ? 1 : 0),
      ),
    );
  }
  return computeContributionReachability(graph, grouped.values.toList());
}

void _expectReference(
  List<ContributionReachabilityEntry> result,
  List<ContributionReferenceRelation> relations,
  List<ContributionReferenceAction> actions, {
  Set<IntentionId> deleted = const {},
  String? reason,
}) {
  final reference = referenceActionContributionCounts(
    relations: relations,
    actions: actions,
    deleted: deleted,
  );
  final expected = [
    for (final entry in reference.entries)
      (entry.key, entry.value.planned, entry.value.contribution),
  ]..sort(_compareValues);
  expect(_values(result), expected, reason: reason);
}

int _compareValues((IntentionId, int, int) a, (IntentionId, int, int) b) {
  final byPlanned = b.$2.compareTo(a.$2);
  if (byPlanned != 0) return byPlanned;
  final byContribution = b.$3.compareTo(a.$3);
  return byContribution != 0 ? byContribution : b.$1.compareTo(a.$1);
}

ContributionSeedGroup _group(
  List<int> seeds, {
  required int planned,
  required int contribution,
}) => ContributionSeedGroup(
  seeds: seeds.map(_id).toList(),
  counts: ContributionCounts(planned: planned, contribution: contribution),
);

ContributionRelationGraph _graph(List<(int, int)> edges) => _idGraph([
  for (final (source, target) in edges) (_id(source), _id(target)),
]);

ContributionRelationGraph _idGraph(List<(IntentionId, IntentionId)> edges) {
  final ids = {
    for (final (source, target) in edges) ...[source, target],
  }.toList();
  final indexes = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final children = List.generate(ids.length, (_) => <int>[]);
  final parents = List.generate(ids.length, (_) => <int>[]);
  for (final (source, target) in edges) {
    children[indexes[source]!].add(indexes[target]!);
    parents[indexes[target]!].add(indexes[source]!);
  }
  return ContributionRelationGraph(
    intentionIds: ids,
    childOffsets: _offsets(children),
    children: Uint32List.fromList(children.expand((row) => row).toList()),
    parentOffsets: _offsets(parents),
    parents: Uint32List.fromList(parents.expand((row) => row).toList()),
  );
}

Uint32List _offsets(List<List<int>> rows) {
  final offsets = Uint32List(rows.length + 1);
  for (var i = 0; i < rows.length; i++) {
    offsets[i + 1] = offsets[i] + rows[i].length;
  }
  return offsets;
}

List<(IntentionId, int, int)> _values(
  List<ContributionReachabilityEntry> entries,
) => [
  for (final entry in entries)
    (entry.intentionId, entry.counts.planned, entry.counts.contribution),
];

List<IntentionId> _ids(List<int> numbers) => numbers.map(_id).toList();

IntentionId _id(int number) => switch (IntentionId.decode(
  '00000000-0000-4000-8000-${number.toRadixString(16).padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Неверный тестовый UUID'),
};
