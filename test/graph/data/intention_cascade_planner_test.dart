import 'dart:math';

import 'package:doable/src/graph/data/intention_cascade_planner.dart';
import 'package:doable/src/graph/data/intention_holding_computation.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_durability_fixture.dart';
import '../../support/intention_cascade_reference.dart';
import '../../support/intention_holding_reference.dart';

void main() {
  /// Граф сценариев: «Быть здоровым» → «Много ходить» → «Хорошая обувь»,
  /// «Много ходить» → «Высыпаться», «Сходить в поход» → «Хорошая обувь».
  _Graph hikingGraph() => _Graph()
    ..main('Быть здоровым')
    ..supporting('Много ходить')
    ..supporting('Хорошая обувь')
    ..main('Высыпаться')
    ..main('Сходить в поход')
    ..relation('Быть здоровым', 'Много ходить')
    ..relation('Много ходить', 'Хорошая обувь')
    ..relation('Много ходить', 'Высыпаться')
    ..relation('Сходить в поход', 'Хорошая обувь');

  group('Архивирование', () {
    test('каскад уносит только то, что больше не удерживается', () {
      final graph = hikingGraph();

      final plan = graph.planner().planArchive(
        graph.intention('Быть здоровым'),
      );

      expect(plan.asksQuestion, isTrue);
      expect(graph.names(plan.withSupporting.departing), ['Много ходить']);
      expect(plan.withSupporting.archivedRelationCount, 3);
    });

    test('неудерживаемое вспомогательное вне каскада не затрагивается', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить')
        ..supporting('Разминка')
        ..supporting('Растяжка')
        ..relation('Быть здоровым', 'Много ходить')
        ..relation('Разминка', 'Растяжка')
        ..relation('Растяжка', 'Разминка');

      final plan = graph.planner().planArchive(
        graph.intention('Быть здоровым'),
      );

      expect(graph.names(plan.withSupporting.departing), ['Много ходить']);
      expect(plan.withSupporting.archivedRelationCount, 1);
    });

    test('архивирование не учитывает архивное главное намерение', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить')
        ..supporting('Хорошая обувь')
        ..main('Высыпаться')
        ..main('Сходить в поход', archived: true)
        ..relation('Быть здоровым', 'Много ходить')
        ..relation('Много ходить', 'Хорошая обувь')
        ..relation('Много ходить', 'Высыпаться')
        ..relation('Сходить в поход', 'Хорошая обувь', archived: true);

      final plan = graph.planner().planArchive(
        graph.intention('Быть здоровым'),
      );

      expect(graph.names(plan.withSupporting.departing), [
        'Много ходить',
        'Хорошая обувь',
      ]);
    });

    test('«только это» делает непосредственно нижнее намерение главным', () {
      final graph = hikingGraph();

      final plan = graph.planner().planArchive(
        graph.intention('Быть здоровым'),
      );

      expect(plan.onlyThis.departing, isEmpty);
      expect(graph.names(plan.onlyThis.promoted), ['Много ходить']);
      expect(plan.onlyThis.archivedRelationCount, 1);
    });

    test('вопрос не задаётся, когда другие намерения не затронуты', () {
      final graph = hikingGraph();

      final plan = graph.planner().planArchive(graph.intention('Много ходить'));

      expect(plan.asksQuestion, isFalse);
      expect(plan.withSupporting.departing, isEmpty);
      expect(plan.withSupporting.promoted, isEmpty);
      expect(plan.withSupporting.archivedRelationCount, 3);
    });

    test('архивирование связи с выбором «только это» делает связанное '
        'намерение главным', () {
      final graph = hikingGraph();

      final plan = graph.planner().planArchive(
        graph.relationSubject('Быть здоровым', 'Много ходить'),
      );

      expect(plan.asksQuestion, isTrue);
      expect(graph.names(plan.withSupporting.departing), ['Много ходить']);
      expect(graph.names(plan.onlyThis.promoted), ['Много ходить']);
      expect(plan.onlyThis.archivedRelationCount, 1);
    });
  });

  group('Удаление', () {
    test('подтверждение называет, что уйдёт и что потеряет только связь', () {
      final graph = hikingGraph();

      final plan = graph.planner().planDelete(graph.intention('Быть здоровым'));

      expect(plan.asksQuestion, isTrue);
      final withSupporting = plan.withSupporting;
      expect(graph.names(withSupporting.departing), ['Много ходить']);
      expect(withSupporting.deletedRelationCount, 3);
      expect(graph.names(withSupporting.mainsLosingRelation), ['Высыпаться']);
      expect(withSupporting.archivedByInvariant, isEmpty);
      expect(graph.names(plan.onlyThis.promoted), ['Много ходить']);
      expect(plan.onlyThis.archivedByInvariant, isEmpty);
    });

    test('подтверждение называет намерения, которые уйдут в архив', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить')
        ..supporting('Хорошая обувь')
        ..supporting('Шнуровка')
        ..main('Сходить в поход', archived: true)
        ..relation('Быть здоровым', 'Много ходить')
        ..relation('Много ходить', 'Хорошая обувь')
        ..relation('Хорошая обувь', 'Шнуровка')
        ..relation('Сходить в поход', 'Хорошая обувь', archived: true);

      final plan = graph.planner().planDelete(graph.intention('Быть здоровым'));

      final withSupporting = plan.withSupporting;
      expect(graph.names(withSupporting.departing), ['Много ходить']);
      expect(withSupporting.deletedRelationCount, 2);
      expect(graph.names(withSupporting.archivedByInvariant), [
        'Хорошая обувь',
        'Шнуровка',
      ]);
      expect(withSupporting.mainsLosingRelation, isEmpty);
    });

    test('удаление уносит архивное вспомогательное, до которого ведёт только '
        'архивная связь', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить')
        ..supporting('Хорошая обувь', archived: true)
        ..relation('Быть здоровым', 'Много ходить')
        ..relation('Много ходить', 'Хорошая обувь', archived: true);

      final plan = graph.planner().planDelete(graph.intention('Быть здоровым'));

      expect(graph.names(plan.withSupporting.departing), [
        'Много ходить',
        'Хорошая обувь',
      ]);
      expect(plan.withSupporting.deletedRelationCount, 2);
    });

    test('удаление главного из пути действия уносит только его связи', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить')
        ..main('Высыпаться')
        ..relation('Быть здоровым', 'Много ходить')
        ..relation('Много ходить', 'Высыпаться');

      final plan = graph.planner().planDelete(graph.intention('Высыпаться'));

      expect(plan.asksQuestion, isFalse);
      expect(plan.withSupporting.departing, isEmpty);
      expect(plan.withSupporting.archivedByInvariant, isEmpty);
      expect(plan.withSupporting.mainsLosingRelation, isEmpty);
      expect(plan.withSupporting.deletedRelationCount, 1);
    });

    test('вспомогательное, удерживаемое только архивным главным, уходит в '
        'архив, а «только это» его архивирование не отменяет', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить')
        ..supporting('Хорошая обувь')
        ..main('Сходить в поход', archived: true)
        ..relation('Быть здоровым', 'Много ходить')
        ..relation('Быть здоровым', 'Хорошая обувь')
        ..relation('Сходить в поход', 'Хорошая обувь', archived: true);

      final plan = graph.planner().planDelete(graph.intention('Быть здоровым'));

      expect(graph.names(plan.withSupporting.departing), ['Много ходить']);
      expect(graph.names(plan.withSupporting.archivedByInvariant), [
        'Хорошая обувь',
      ]);
      expect(graph.names(plan.onlyThis.promoted), ['Много ходить']);
      expect(graph.names(plan.onlyThis.archivedByInvariant), ['Хорошая обувь']);
    });

    test('«Оставить главным» удаляет только связь', () {
      final graph = hikingGraph();

      final plan = graph.planner().planDelete(
        graph.relationSubject('Быть здоровым', 'Много ходить'),
      );

      expect(plan.asksQuestion, isTrue);
      expect(graph.names(plan.withSupporting.departing), ['Много ходить']);
      expect(plan.withSupporting.deletedRelationCount, 3);
      expect(plan.onlyThis.departing, isEmpty);
      expect(graph.names(plan.onlyThis.promoted), ['Много ходить']);
      expect(plan.onlyThis.deletedRelationCount, 1);
    });

    test('подтверждение удаления связи называет намерение, которое уйдёт в '
        'архив', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить')
        ..supporting('Хорошая обувь')
        ..main('Сходить в поход', archived: true)
        ..relation('Быть здоровым', 'Много ходить')
        ..relation('Много ходить', 'Хорошая обувь')
        ..relation('Сходить в поход', 'Хорошая обувь', archived: true);

      final plan = graph.planner().planDelete(
        graph.relationSubject('Много ходить', 'Хорошая обувь'),
      );

      expect(plan.asksQuestion, isFalse);
      expect(plan.withSupporting.departing, isEmpty);
      expect(plan.withSupporting.deletedRelationCount, 1);
      expect(graph.names(plan.withSupporting.archivedByInvariant), [
        'Хорошая обувь',
      ]);
    });

    test('списки идут обходом в глубину по порядку связей, а главные — '
        'входящими связями раньше исходящих', () {
      final graph = _Graph()
        ..main('Здоровье')
        ..main('Форма')
        ..supporting('Сон')
        ..supporting('Ходьба')
        ..supporting('Обувь')
        ..supporting('Носки')
        ..supporting('Стельки')
        ..supporting('Маршрут')
        ..supporting('Карта')
        ..supporting('Вода')
        ..main('Отпуск')
        ..main('Поход')
        ..relation('Форма', 'Здоровье')
        ..relation('Здоровье', 'Вода', type: LongTermRelationType.can)
        ..relation('Здоровье', 'Сон', priority: RelationPriority.p3)
        ..relation('Здоровье', 'Ходьба', priority: RelationPriority.p1)
        ..relation('Здоровье', 'Поход', priority: RelationPriority.p4)
        ..relation('Ходьба', 'Маршрут', priority: RelationPriority.p2)
        ..relation('Ходьба', 'Обувь', priority: RelationPriority.p2)
        ..relation('Обувь', 'Носки')
        ..relation('Обувь', 'Стельки')
        ..relation('Маршрут', 'Карта')
        ..relation('Карта', 'Отпуск');

      final plan = graph.planner().planDelete(graph.intention('Здоровье'));

      expect(graph.names(plan.withSupporting.departing), [
        'Ходьба',
        'Маршрут',
        'Карта',
        'Обувь',
        'Носки',
        'Стельки',
        'Сон',
        'Вода',
      ]);
      expect(graph.names(plan.withSupporting.mainsLosingRelation), [
        'Форма',
        'Отпуск',
        'Поход',
      ]);
    });
  });

  group('Восстановление', () {
    test('каскад восстановления останавливается на главном намерении', () {
      final graph = _Graph()
        ..main('Быть здоровым', archived: true)
        ..supporting('Много ходить', archived: true)
        ..main('Высыпаться', archived: true)
        ..supporting('Хорошая обувь')
        ..main('Сходить в поход')
        ..relation('Быть здоровым', 'Много ходить', archived: true)
        ..relation('Много ходить', 'Хорошая обувь', archived: true)
        ..relation('Много ходить', 'Высыпаться', archived: true)
        ..relation('Сходить в поход', 'Хорошая обувь');

      final plan = graph.planner().planRestore(
        graph.intention('Быть здоровым'),
      );

      expect(plan.asksQuestion, isTrue);
      expect(graph.names(plan.withSupporting.restored), ['Много ходить']);
      expect(plan.withSupporting.restoredRelationCount, 2);
      expect(plan.withSupporting.returnedAsMain, isNull);
    });

    test('восстановление только этого намерения оставляет вспомогательное и '
        'связь с ним в архиве', () {
      final graph = _Graph()
        ..main('Быть здоровым', archived: true)
        ..supporting('Много ходить', archived: true)
        ..relation('Быть здоровым', 'Много ходить', archived: true);

      final plan = graph.planner().planRestore(
        graph.intention('Быть здоровым'),
      );

      expect(plan.asksQuestion, isTrue);
      expect(graph.names(plan.withSupporting.restored), ['Много ходить']);
      expect(plan.withSupporting.restoredRelationCount, 1);
      expect(plan.onlyThis.restored, isEmpty);
      expect(plan.onlyThis.restoredRelationCount, 0);
    });

    test(
      'вспомогательное без активного намерения выше возвращается главным',
      () {
        final graph = _Graph()
          ..main('Быть здоровым', archived: true)
          ..supporting('Много ходить', archived: true)
          ..main('Высыпаться')
          ..relation('Быть здоровым', 'Много ходить', archived: true)
          ..relation('Много ходить', 'Высыпаться', archived: true);

        final plan = graph.planner().planRestore(
          graph.intention('Много ходить'),
        );

        expect(plan.asksQuestion, isFalse);
        expect(graph.name(plan.withSupporting.returnedAsMain!), 'Много ходить');
        expect(plan.withSupporting.restoredRelationCount, 1);
      },
    );

    test('вспомогательное с активным намерением выше сохраняет вид', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить', archived: true)
        ..relation('Быть здоровым', 'Много ходить', archived: true);

      final plan = graph.planner().planRestore(graph.intention('Много ходить'));

      expect(plan.withSupporting.returnedAsMain, isNull);
      expect(plan.withSupporting.restoredRelationCount, 1);
    });

    test('восстановление связи возвращает архивного участника и спрашивает '
        'о вспомогательных ниже него', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..supporting('Много ходить', archived: true)
        ..supporting('Хорошая обувь', archived: true)
        ..relation('Быть здоровым', 'Много ходить', archived: true)
        ..relation('Много ходить', 'Хорошая обувь', archived: true);

      final plan = graph.planner().planRestore(
        graph.relationSubject('Быть здоровым', 'Много ходить'),
      );

      expect(plan.asksQuestion, isTrue);
      expect(graph.names(plan.withSupporting.restored), [
        'Много ходить',
        'Хорошая обувь',
      ]);
      expect(graph.names(plan.onlyThis.restored), ['Много ходить']);
      expect(plan.onlyThis.returnedAsMain, isNull);
      expect(plan.onlyThis.restoredRelationCount, 1);
    });

    test('восстановление связи возвращает исходного участника главным', () {
      final graph = _Graph()
        ..main('Быть здоровым', archived: true)
        ..supporting('Много ходить', archived: true)
        ..supporting('Хорошая обувь')
        ..main('Сходить в поход')
        ..relation('Быть здоровым', 'Много ходить', archived: true)
        ..relation('Много ходить', 'Хорошая обувь', archived: true)
        ..relation('Сходить в поход', 'Хорошая обувь');

      final plan = graph.planner().planRestore(
        graph.relationSubject('Много ходить', 'Хорошая обувь'),
      );

      expect(plan.asksQuestion, isFalse);
      expect(graph.names(plan.withSupporting.restored), ['Много ходить']);
      expect(graph.name(plan.withSupporting.returnedAsMain!), 'Много ходить');
      expect(plan.withSupporting.restoredRelationCount, 1);
    });

    test('связь между активными намерениями восстанавливается одна', () {
      final graph = _Graph()
        ..main('Быть здоровым')
        ..main('Высыпаться')
        ..relation('Быть здоровым', 'Высыпаться', archived: true);

      final plan = graph.planner().planRestore(
        graph.relationSubject('Быть здоровым', 'Высыпаться'),
      );

      expect(plan.asksQuestion, isFalse);
      expect(plan.withSupporting.restored, isEmpty);
      expect(plan.withSupporting.restoredRelationCount, 1);
    });
  });

  test('намерение, созданное после построения индекса, планируется активным '
      'главным без связей', () {
    final graph = hikingGraph();
    final planner = graph.planner();
    final created = PlannedIntention(durabilityIntention(1000));

    final archive = planner.planArchive(created);
    final delete = planner.planDelete(created);

    expect(archive.asksQuestion, isFalse);
    expect(archive.withSupporting.departing, isEmpty);
    expect(archive.withSupporting.archivedRelationCount, 0);
    expect(delete.asksQuestion, isFalse);
    expect(delete.withSupporting.departing, isEmpty);
    expect(delete.withSupporting.archivedByInvariant, isEmpty);
    expect(delete.withSupporting.deletedRelationCount, 0);
  });

  test('на случайных графах с циклами и архивом составы обоих вариантов '
      'совпадают с эталоном', () {
    final random = Random(57);
    for (var round = 0; round < 300; round++) {
      final graph = _randomGraph(random);
      final planner = graph.planner();
      final reference = graph.reference();
      final subjects = [
        for (final id in reference.intentions.keys)
          (
            planned: PlannedIntention(id) as CascadePlanningSubject,
            reference: (intention: id, relation: null),
            archived:
                reference.intentions[id]!.archiveState ==
                IntentionArchiveState.archived,
          ),
        for (final relation in reference.relations)
          (
            planned: PlannedRelation(
              source: relation.source,
              related: relation.target,
            ),
            reference: (intention: null, relation: relation),
            archived: relation.scope == RelationScope.archived,
          ),
      ];
      for (final (index, subject) in subjects.indexed) {
        final reason = 'раунд $round, предмет $index';
        if (subject.archived) {
          _expectRestore(
            planner.planRestore(subject.planned),
            referenceCascadeRestore(reference, subject.reference),
            reason,
          );
        } else {
          final archive = planner.planArchive(subject.planned);
          _expectRemoval(
            archive,
            (composition) => (
              departing: composition.departing.toSet(),
              promoted: composition.promoted.toSet(),
              archivedByInvariant: <IntentionId>{},
              mainsLosingRelation: null,
              removedRelationCount: composition.archivedRelationCount,
            ),
            referenceCascadeRemoval(
              reference,
              subject.reference,
              delete: false,
            ),
            reason,
          );
        }
        _expectRemoval(
          planner.planDelete(subject.planned),
          (composition) => (
            departing: composition.departing.toSet(),
            promoted: composition.promoted.toSet(),
            archivedByInvariant: composition.archivedByInvariant.toSet(),
            mainsLosingRelation: composition.mainsLosingRelation.toSet(),
            removedRelationCount: composition.deletedRelationCount,
          ),
          referenceCascadeRemoval(reference, subject.reference, delete: true),
          reason,
        );
      }
    }
  });
}

void _expectRemoval<C extends CascadeComposition>(
  CascadePlan<C> plan,
  CascadeReferenceRemoval Function(C composition) sets,
  ({
    CascadeReferenceRemoval withSupporting,
    CascadeReferenceRemoval onlyThis,
    bool asksQuestion,
  })
  expected,
  String reason,
) {
  expect(plan.asksQuestion, expected.asksQuestion, reason: reason);
  expect(
    _removalFields(sets(plan.withSupporting)),
    _removalFields(expected.withSupporting),
    reason: reason,
  );
  expect(
    _removalFields(sets(plan.onlyThis)),
    _removalFields(expected.onlyThis),
    reason: reason,
  );
}

/// Записи сравниваются по `==`, а множества внутри них — по ссылке, поэтому
/// поля сравниваются отображением.
Map<String, Object?> _removalFields(CascadeReferenceRemoval removal) => {
  'departing': removal.departing,
  'promoted': removal.promoted,
  'archivedByInvariant': removal.archivedByInvariant,
  'mainsLosingRelation': removal.mainsLosingRelation,
  'removedRelationCount': removal.removedRelationCount,
};

void _expectRestore(
  CascadePlan<RestoreCascadeComposition> plan,
  ({
    CascadeReferenceRestore withSupporting,
    CascadeReferenceRestore onlyThis,
    bool asksQuestion,
  })
  expected,
  String reason,
) {
  CascadeReferenceRestore sets(RestoreCascadeComposition composition) => (
    restored: composition.restored.toSet(),
    returnedAsMain: {?composition.returnedAsMain},
    restoredRelationCount: composition.restoredRelationCount,
  );
  expect(plan.asksQuestion, expected.asksQuestion, reason: reason);
  expect(
    _restoreFields(sets(plan.withSupporting)),
    _restoreFields(expected.withSupporting),
    reason: reason,
  );
  expect(
    _restoreFields(sets(plan.onlyThis)),
    _restoreFields(expected.onlyThis),
    reason: reason,
  );
}

Map<String, Object> _restoreFields(CascadeReferenceRestore restore) => {
  'restored': restore.restored,
  'returnedAsMain': restore.returnedAsMain,
  'restoredRelationCount': restore.restoredRelationCount,
};

/// Допустимый граф: активная связь соединяет только активные намерения, а у
/// активного вспомогательного есть активная входящая связь.
_Graph _randomGraph(Random random) {
  final count = 2 + random.nextInt(10);
  final graph = _Graph();
  final states = <({bool supporting, bool archived})>[
    for (var number = 0; number < count; number++)
      (supporting: random.nextInt(10) < 7, archived: random.nextInt(10) < 3),
  ];
  final pairs = <(int, int)>{};
  for (var edge = 0; edge < random.nextInt(count * 2 + 1); edge++) {
    final source = random.nextInt(count);
    final target = random.nextInt(count);
    if (source != target) pairs.add((source, target));
  }
  final relations = [
    for (final (source, target) in pairs)
      (
        source: source,
        target: target,
        archived:
            states[source].archived ||
            states[target].archived ||
            random.nextInt(5) == 0,
      ),
  ];
  for (final (number, state) in states.indexed) {
    final hasActiveIncoming = relations.any(
      (relation) => relation.target == number && !relation.archived,
    );
    final supporting =
        state.supporting && (state.archived || hasActiveIncoming);
    if (supporting) {
      graph.supporting('$number', archived: state.archived);
    } else {
      graph.main('$number', archived: state.archived);
    }
  }
  for (final relation in relations) {
    graph.relation(
      '${relation.source}',
      '${relation.target}',
      archived: relation.archived,
      type: LongTermRelationType.values[random.nextInt(2)],
      priority: RelationPriority.values[random.nextInt(4)],
    );
  }
  return graph;
}

/// Граф по названиям намерений; связи получают последовательность создания
/// в порядке добавления.
final class _Graph {
  final _numbers = <String, int>{};
  final _intentions = <IntentionId, HoldingReferenceIntention>{};
  final _relations =
      <
        ({
          HoldingReferenceRelation relation,
          LongTermRelationType type,
          RelationPriority priority,
        })
      >[];

  void main(String name, {bool archived = false}) =>
      _add(name, IntentionKind.main, archived);

  void supporting(String name, {bool archived = false}) =>
      _add(name, IntentionKind.supporting, archived);

  void _add(String name, IntentionKind kind, bool archived) {
    final number = _numbers.length + 1;
    _numbers[name] = number;
    _intentions[durabilityIntention(number)] = (
      kind: kind,
      archiveState: archived
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
    );
  }

  void relation(
    String source,
    String target, {
    bool archived = false,
    LongTermRelationType type = LongTermRelationType.need,
    RelationPriority priority = RelationPriority.p2,
  }) => _relations.add((
    relation: (
      source: id(source),
      target: id(target),
      scope: archived ? RelationScope.archived : RelationScope.active,
    ),
    type: type,
    priority: priority,
  ));

  IntentionId id(String name) => durabilityIntention(_numbers[name]!);

  String name(IntentionId id) =>
      _numbers.entries.firstWhere((entry) => id == this.id(entry.key)).key;

  List<String> names(List<IntentionId> ids) => [for (final id in ids) name(id)];

  PlannedIntention intention(String name) => PlannedIntention(id(name));

  PlannedRelation relationSubject(String source, String target) =>
      PlannedRelation(source: id(source), related: id(target));

  CascadeReferenceGraph reference() => (
    intentions: _intentions,
    relations: [for (final entry in _relations) entry.relation],
  );

  IntentionCascadePlanner planner() {
    final builder = IntentionHoldingGraphBuilder();
    for (final MapEntry(:key, :value) in _intentions.entries) {
      builder.addIntention(key, value.kind, value.archiveState);
    }
    for (final (index, (:relation, :type, :priority)) in _relations.indexed) {
      builder.addRelation(
        relation.source,
        relation.target,
        relation.scope,
        type: type,
        priority: priority,
        creationSequence: index + 1,
      );
    }
    final (:graph, :indexes, :ids) = builder.build();
    return IntentionCascadePlanner(
      graph: graph,
      indexes: indexes,
      ids: ids,
      held: computeIntentionHolding(graph),
    );
  }
}
