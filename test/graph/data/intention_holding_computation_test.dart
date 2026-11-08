import 'dart:math';
import 'dart:typed_data';

import 'package:doable/src/graph/data/intention_holding_computation.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_durability_fixture.dart';
import '../../support/intention_holding_reference.dart';

const _main = (
  kind: IntentionKind.main,
  archiveState: IntentionArchiveState.active,
);
const _supporting = (
  kind: IntentionKind.supporting,
  archiveState: IntentionArchiveState.active,
);
const _archivedMain = (
  kind: IntentionKind.main,
  archiveState: IntentionArchiveState.archived,
);
const _archivedSupporting = (
  kind: IntentionKind.supporting,
  archiveState: IntentionArchiveState.archived,
);

void main() {
  test('Главные удерживают цепочку вспомогательных через другие '
      'вспомогательные и через главные', () {
    final held = _held(
      {1: _main, 2: _supporting, 3: _supporting, 4: _main, 5: _supporting},
      [_active(1, 2), _active(2, 3), _active(4, 5)],
    );

    expect(held, {1, 2, 3, 4, 5});
  });

  test('Вспомогательные, ведущие только друг к другу, не удерживаются', () {
    final held = _held(
      {1: _main, 2: _supporting, 3: _supporting, 4: _supporting},
      [_active(2, 3), _active(3, 2), _active(3, 4)],
    );

    expect(held, {1});
  });

  test('Архивное главное и архивная связь ничего не удерживают', () {
    final held = _held(
      {1: _archivedMain, 2: _supporting, 3: _supporting, 4: _main},
      [_archived(1, 2), _active(2, 3), _active(3, 2), _archived(4, 3)],
    );

    expect(held, {4});
  });

  test('Архивное вспомогательное не удерживается и не передаёт удержание', () {
    final held = _held(
      {1: _main, 2: _archivedSupporting, 3: _supporting},
      [_archived(1, 2), _archived(2, 3)],
    );

    expect(held, {1});
  });

  test('Исходящие и входящие связи упорядочены: «нужно» раньше «можно», '
      'затем приоритет, затем последовательность создания', () {
    final builder = IntentionHoldingGraphBuilder();
    for (var number = 1; number <= 6; number++) {
      builder.addIntention(
        durabilityIntention(number),
        IntentionKind.main,
        IntentionArchiveState.active,
      );
    }
    for (final (source, target, type, priority, sequence) in [
      (1, 2, LongTermRelationType.can, RelationPriority.p1, 1),
      (1, 5, LongTermRelationType.need, RelationPriority.p2, 5),
      (1, 3, LongTermRelationType.need, RelationPriority.p2, 2),
      (1, 4, LongTermRelationType.need, RelationPriority.p1, 3),
      (2, 6, LongTermRelationType.can, RelationPriority.p1, 7),
      (3, 6, LongTermRelationType.need, RelationPriority.p3, 8),
      (4, 6, LongTermRelationType.need, RelationPriority.p3, 6),
    ]) {
      builder.addRelation(
        durabilityIntention(source),
        durabilityIntention(target),
        RelationScope.active,
        type: type,
        priority: priority,
        creationSequence: sequence,
      );
    }
    final (:graph, :indexes, :ids) = builder.build();

    List<int> numbers(Uint32List offsets, Uint32List ends, int intention) {
      final index = indexes[durabilityIntention(intention)]!;
      return [
        for (var edge = offsets[index]; edge < offsets[index + 1]; edge++)
          for (var number = 1; number <= 6; number++)
            if (ids[ends[edge]] == durabilityIntention(number)) number,
      ];
    }

    expect(numbers(graph.childOffsets, graph.children, 1), [4, 3, 5, 2]);
    expect(numbers(graph.parentOffsets, graph.parents, 6), [4, 3, 2]);
  });

  test('На случайных графах с циклами совпадает с эталоном', () {
    final random = Random(56);
    final states = [_main, _supporting, _archivedMain, _archivedSupporting];
    for (var round = 0; round < 200; round++) {
      final count = 1 + random.nextInt(24);
      final intentions = {
        for (var number = 1; number <= count; number++)
          number: random.nextInt(10) < 6
              ? _supporting
              : states[random.nextInt(states.length)],
      };
      final relations = [
        for (var edge = 0; edge < random.nextInt(count * 3); edge++)
          (
            1 + random.nextInt(count),
            1 + random.nextInt(count),
            random.nextInt(5) == 0
                ? RelationScope.archived
                : RelationScope.active,
          ),
      ];

      expect(
        _held(intentions, relations),
        _referenceHeld(intentions, relations),
        reason: 'раунд $round',
      );
    }
  });
}

typedef _Relation = (int, int, RelationScope);

_Relation _active(int source, int target) =>
    (source, target, RelationScope.active);

_Relation _archived(int source, int target) =>
    (source, target, RelationScope.archived);

Set<int> _held(
  Map<int, HoldingReferenceIntention> intentions,
  List<_Relation> relations,
) {
  final builder = IntentionHoldingGraphBuilder();
  for (final MapEntry(:key, :value) in intentions.entries) {
    builder.addIntention(
      durabilityIntention(key),
      value.kind,
      value.archiveState,
    );
  }
  for (final (index, (source, target, scope)) in relations.indexed) {
    builder.addRelation(
      durabilityIntention(source),
      durabilityIntention(target),
      scope,
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      creationSequence: index + 1,
    );
  }
  final (:graph, :indexes, ids: _) = builder.build();
  final held = computeIntentionHolding(graph);
  return {
    for (final number in intentions.keys)
      if (held[indexes[durabilityIntention(number)]!] == 1) number,
  };
}

Set<int> _referenceHeld(
  Map<int, HoldingReferenceIntention> intentions,
  List<_Relation> relations,
) {
  final held = referenceHeldIntentions(
    intentions: {
      for (final MapEntry(:key, :value) in intentions.entries)
        durabilityIntention(key): value,
    },
    relations: [
      for (final (source, target, scope) in relations)
        (
          source: durabilityIntention(source),
          target: durabilityIntention(target),
          scope: scope,
        ),
    ],
  );
  return {
    for (final number in intentions.keys)
      if (held.contains(durabilityIntention(number))) number,
  };
}
