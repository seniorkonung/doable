import 'dart:convert';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_state_assembly.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tag_positions.dart';

void main() {
  group('сборка состояния графа на позиции', () {
    test('пустые база и диапазон дают пустой граф', () async {
      final state = await GraphStateAssembly.assemble(
        const GraphStateBase.empty(),
        const Stream.empty(),
      );

      expect(_counts(state.counts), _noCounts);
      expect(await state.records.toList(), isEmpty);
    });

    test('созданные сущности встают в свои секции после сущностей базы в '
        'порядке создания', () async {
      final home = _tag(1, 'Дом');
      final health = _intention(1, 'Здоровье', createdAt: _morning);
      final running = _intention(2, 'Бегать', createdAt: _morning.add(_minute));
      final needRunning = _relation(1, from: 1, to: 2);
      final choice = _dailyChoice(1, from: 1, to: 2, through: 1);
      final sport = _tag(2, 'Спорт');
      final swimming = _intention(3, 'Плавать', createdAt: _evening);
      final canSwim = _relation(2, from: 1, to: 3);

      final state = await GraphStateAssembly.assemble(
        GraphStateBase(
          position: 1,
          readRecords: () => Stream.fromIterable([
            home,
            health,
            running,
            _assignment(tag: 1, intention: 2),
            needRunning,
            choice,
          ]),
        ),
        Stream.fromIterable([
          GraphFactPackage(
            position: 2,
            facts: [
              GraphEntityCreated(sport),
              GraphEntityCreated(swimming),
              GraphEntityCreated(_assignment(tag: 2, intention: 3)),
              GraphEntityCreated(_assignment(tag: 1, intention: 3)),
              GraphEntityCreated(canSwim),
            ],
          ),
        ]),
      );

      expect(_counts(state.counts), (
        tags: 2,
        intentions: 3,
        tagAssignments: 3,
        longTermRelations: 2,
        dailyChoices: 1,
      ));
      expect(_lines(await state.records.toList()), [
        ..._lines([home, sport, health, running, swimming]),
        ..._lines([
          _assignment(tag: 1, intention: 2),
          _assignment(tag: 2, intention: 3),
          _assignment(tag: 1, intention: 3),
        ]),
        ..._lines([needRunning, canSwim, choice]),
      ]);
    });

    test('пустой диапазон оставляет базовое состояние как есть', () async {
      final base = [
        _tag(1, 'Дом'),
        _intention(1, 'Здоровье', createdAt: _morning),
        _assignment(tag: 1, intention: 1),
      ];

      final state = await GraphStateAssembly.assemble(
        GraphStateBase(
          position: 7,
          readRecords: () => Stream.fromIterable(base),
        ),
        const Stream.empty(),
      );

      expect(_counts(state.counts), (
        tags: 1,
        intentions: 1,
        tagAssignments: 1,
        longTermRelations: 0,
        dailyChoices: 0,
      ));
      expect(_lines(await state.records.toList()), _lines(base));
    });

    test('повторно изменённая сущность остаётся на своём месте с последним '
        'состоянием', () async {
      final state = await GraphStateAssembly.assemble(
        GraphStateBase(
          position: 4,
          readRecords: () => Stream.fromIterable([
            _intention(1, 'Здоровье', createdAt: _morning),
            _intention(2, 'Бегать', createdAt: _morning.add(_minute)),
            _intention(3, 'Спать', createdAt: _evening),
            _relation(1, from: 1, to: 2),
            _relation(2, from: 2, to: 1),
          ]),
        ),
        Stream.fromIterable([
          GraphFactPackage(
            position: 5,
            facts: [
              GraphEntityChanged(
                _intention(1, 'Здоровье и сон', createdAt: _morning),
              ),
              GraphEntityChanged(
                _relation(1, from: 1, to: 2, priority: RelationPriority.p1),
              ),
              GraphEntityCreated(_relation(3, from: 2, to: 3)),
            ],
          ),
          GraphFactPackage(
            position: 6,
            facts: [
              GraphEntityChanged(
                _intention(
                  1,
                  'Здоровье, сон и отдых',
                  createdAt: _morning,
                  archived: true,
                ),
              ),
              GraphEntityChanged(
                _relation(
                  1,
                  from: 1,
                  to: 2,
                  priority: RelationPriority.p1,
                  scope: RelationScope.archived,
                ),
              ),
              GraphEntityChanged(
                _relation(3, from: 2, to: 3, priority: RelationPriority.p3),
              ),
            ],
          ),
        ]),
      );

      expect(_counts(state.counts), (
        tags: 0,
        intentions: 3,
        tagAssignments: 0,
        longTermRelations: 3,
        dailyChoices: 0,
      ));
      expect(
        _lines(await state.records.toList()),
        _lines([
          _intention(
            1,
            'Здоровье, сон и отдых',
            createdAt: _morning,
            archived: true,
          ),
          _intention(2, 'Бегать', createdAt: _morning.add(_minute)),
          _intention(3, 'Спать', createdAt: _evening),
          _relation(
            1,
            from: 1,
            to: 2,
            priority: RelationPriority.p1,
            scope: RelationScope.archived,
          ),
          _relation(2, from: 2, to: 1),
          _relation(3, from: 2, to: 3, priority: RelationPriority.p3),
        ]),
      );
    });

    test('сущность, созданная и удалённая в разных пакетах, в состояние не '
        'попадает', () async {
      final state = await GraphStateAssembly.assemble(
        const GraphStateBase.empty(),
        Stream.fromIterable([
          GraphFactPackage(
            position: 1,
            facts: [GraphEntityCreated(_tag(1, 'Дом'))],
          ),
          GraphFactPackage(
            position: 2,
            facts: [GraphEntityCreated(_tag(2, 'Спорт'))],
          ),
          GraphFactPackage(
            position: 3,
            facts: [GraphEntityCreated(_tag(3, 'Чтение'))],
          ),
          GraphFactPackage(
            position: 4,
            facts: [GraphEntityDeleted(TagKey(_tagId(2)))],
          ),
        ]),
      );

      expect(_counts(state.counts), (
        tags: 2,
        intentions: 0,
        tagAssignments: 0,
        longTermRelations: 0,
        dailyChoices: 0,
      ));
      expect(
        _lines(await state.records.toList()),
        _lines([_tag(1, 'Дом'), _tag(3, 'Чтение')]),
      );
    });

    test('удалённая сущность базы выбрасывается вместе с её '
        'назначениями', () async {
      final state = await GraphStateAssembly.assemble(
        GraphStateBase(
          position: 3,
          readRecords: () => Stream.fromIterable([
            _tag(1, 'Дом'),
            _tag(2, 'Спорт'),
            _intention(1, 'Здоровье', createdAt: _morning),
            _assignment(tag: 1, intention: 1),
            _assignment(tag: 2, intention: 1),
          ]),
        ),
        Stream.fromIterable([
          GraphFactPackage(
            position: 4,
            facts: [
              GraphEntityDeleted(TagKey(_tagId(1))),
              GraphEntityDeleted(
                TagAssignmentKey(
                  TagAssignment(tagId: _tagId(1), intentionId: _intentionId(1)),
                ),
              ),
            ],
          ),
        ]),
      );

      expect(_counts(state.counts), (
        tags: 1,
        intentions: 1,
        tagAssignments: 1,
        longTermRelations: 0,
        dailyChoices: 0,
      ));
      expect(
        _lines(await state.records.toList()),
        _lines([
          _tag(2, 'Спорт'),
          _intention(1, 'Здоровье', createdAt: _morning),
          _assignment(tag: 2, intention: 1),
        ]),
      );
    });

    test('снятое и повторно назначенное назначение из базы уходит в конец '
        'секции', () async {
      final state = await GraphStateAssembly.assemble(
        GraphStateBase(
          position: 10,
          readRecords: () => Stream.fromIterable([
            _tag(1, 'Дом'),
            _intention(1, 'А', createdAt: _morning),
            _intention(2, 'Б', createdAt: _morning.add(_minute)),
            _assignment(tag: 1, intention: 1),
            _assignment(tag: 1, intention: 2),
          ]),
        ),
        Stream.fromIterable([
          GraphFactPackage(
            position: 11,
            facts: [_unassigned(tag: 1, intention: 1)],
          ),
          GraphFactPackage(
            position: 12,
            facts: [GraphEntityCreated(_assignment(tag: 1, intention: 1))],
          ),
        ]),
      );

      expect(_counts(state.counts), (
        tags: 1,
        intentions: 2,
        tagAssignments: 2,
        longTermRelations: 0,
        dailyChoices: 0,
      ));
      expect(
        _lines(await state.records.toList()),
        _lines([
          _tag(1, 'Дом'),
          _intention(1, 'А', createdAt: _morning),
          _intention(2, 'Б', createdAt: _morning.add(_minute)),
          _assignment(tag: 1, intention: 2),
          _assignment(tag: 1, intention: 1),
        ]),
      );
    });

    test('снятое и повторно назначенное назначение, созданное в диапазоне, '
        'встаёт на место повторного создания', () async {
      final state = await GraphStateAssembly.assemble(
        GraphStateBase(
          position: 20,
          readRecords: () => Stream.fromIterable([
            _tag(1, 'Дом'),
            _intention(1, 'А', createdAt: _morning),
            _intention(2, 'Б', createdAt: _morning.add(_minute)),
            _intention(3, 'В', createdAt: _evening),
          ]),
        ),
        Stream.fromIterable([
          GraphFactPackage(
            position: 21,
            facts: [GraphEntityCreated(_assignment(tag: 1, intention: 1))],
          ),
          GraphFactPackage(
            position: 22,
            facts: [
              GraphEntityCreated(_assignment(tag: 1, intention: 2)),
              GraphEntityCreated(_assignment(tag: 1, intention: 3)),
            ],
          ),
          GraphFactPackage(
            position: 23,
            facts: [_unassigned(tag: 1, intention: 1)],
          ),
          GraphFactPackage(
            position: 24,
            facts: [GraphEntityCreated(_assignment(tag: 1, intention: 1))],
          ),
        ]),
      );

      expect(_counts(state.counts), (
        tags: 1,
        intentions: 3,
        tagAssignments: 3,
        longTermRelations: 0,
        dailyChoices: 0,
      ));
      expect(
        _lines(await state.records.toList()),
        _lines([
          _tag(1, 'Дом'),
          _intention(1, 'А', createdAt: _morning),
          _intention(2, 'Б', createdAt: _morning.add(_minute)),
          _intention(3, 'В', createdAt: _evening),
          _assignment(tag: 1, intention: 2),
          _assignment(tag: 1, intention: 3),
          _assignment(tag: 1, intention: 1),
        ]),
      );
    });

    test('намерение с более ранним временем создания встаёт перед '
        'намерениями базы по времени создания и идентификатору', () async {
      // Часы устройства переведены назад: намерения создаются в диапазоне с
      // временем раньше намерений базы, одно из них — с тем же временем, что
      // и намерение базы.
      final state = await GraphStateAssembly.assemble(
        GraphStateBase(
          position: 5,
          readRecords: () => Stream.fromIterable([
            _intention(2, 'Утро', createdAt: _morning),
            _intention(4, 'Вечер', createdAt: _evening),
          ]),
        ),
        Stream.fromIterable([
          GraphFactPackage(
            position: 6,
            facts: [
              GraphEntityCreated(
                _intention(3, 'Тоже утро', createdAt: _morning),
              ),
            ],
          ),
          GraphFactPackage(
            position: 7,
            facts: [
              GraphEntityCreated(_intention(1, 'Ночь', createdAt: _night)),
            ],
          ),
          GraphFactPackage(
            position: 8,
            facts: [
              GraphEntityCreated(_intention(5, 'Тоже ночь', createdAt: _night)),
            ],
          ),
        ]),
      );

      expect(_counts(state.counts).intentions, 5);
      expect(
        _lines(await state.records.toList()),
        _lines([
          _intention(1, 'Ночь', createdAt: _night),
          _intention(5, 'Тоже ночь', createdAt: _night),
          _intention(2, 'Утро', createdAt: _morning),
          _intention(3, 'Тоже утро', createdAt: _morning),
          _intention(4, 'Вечер', createdAt: _evening),
        ]),
      );
    });

    test('записи базового состояния выдаются по мере чтения, не дожидаясь '
        'его конца', () async {
      const tagCount = 100000;
      final tag = _tag(1, 'Дом');
      var readTags = 0;
      Stream<GraphEntityRecord> tags() async* {
        for (readTags = 0; readTags < tagCount; readTags++) {
          yield tag;
        }
      }

      final state = await GraphStateAssembly.assemble(
        GraphStateBase(position: 1, readRecords: tags),
        const Stream.empty(),
      );
      await state.records.first;

      expect(readTags, lessThan(tagCount));
    });
  });
}

const _noCounts = (
  tags: 0,
  intentions: 0,
  tagAssignments: 0,
  longTermRelations: 0,
  dailyChoices: 0,
);

typedef _Counts = ({
  int tags,
  int intentions,
  int tagAssignments,
  int longTermRelations,
  int dailyChoices,
});

_Counts _counts(GraphRecordCounts counts) => (
  tags: counts.tags,
  intentions: counts.intentions,
  tagAssignments: counts.tagAssignments,
  longTermRelations: counts.longTermRelations,
  dailyChoices: counts.dailyChoices,
);

/// Кодирование каноническое и передаёт каждое поле, поэтому совпадение строк
/// означает совпадение записей.
List<String> _lines(Iterable<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];

final _night = DateTime.utc(2026, 10, 1, 1);
final _morning = DateTime.utc(2026, 10, 1, 7);
final _evening = DateTime.utc(2026, 10, 1, 19);
const _minute = Duration(minutes: 1);

TagRecord _tag(int number, String name) => TagRecord(
  Tag(
    id: _tagId(number),
    name: TagName.fromStored(name),
    color: null,
    position: tagPositionAt(number),
  ),
);

IntentionRecord _intention(
  int number,
  String title, {
  required DateTime createdAt,
  bool archived = false,
}) => IntentionRecord(
  Intention(
    id: _intentionId(number),
    title: title,
    description: null,
    readiness: IntentionReadiness.ready,
    archiveState: archived
        ? IntentionArchiveState.archived
        : IntentionArchiveState.active,
    createdAt: IntentionTimestamp(createdAt),
    updatedAt: IntentionTimestamp(createdAt),
  ),
);

TagAssignmentRecord _assignment({required int tag, required int intention}) =>
    TagAssignmentRecord(
      TagAssignment(tagId: _tagId(tag), intentionId: _intentionId(intention)),
    );

GraphEntityDeleted _unassigned({required int tag, required int intention}) =>
    GraphEntityDeleted(
      TagAssignmentKey(
        TagAssignment(tagId: _tagId(tag), intentionId: _intentionId(intention)),
      ),
    );

LongTermRelationRecord _relation(
  int number, {
  required int from,
  required int to,
  RelationPriority priority = RelationPriority.p2,
  RelationScope scope = RelationScope.active,
}) => LongTermRelationRecord(
  id: _relationId(number),
  sourceIntentionId: _intentionId(from),
  relatedIntentionId: _intentionId(to),
  type: LongTermRelationType.need,
  priority: priority,
  description: null,
  scope: scope,
);

DailyChoiceRecord _dailyChoice(
  int number, {
  required int from,
  required int to,
  required int through,
}) {
  final id = _dailyChoiceId(number);
  return DailyChoiceRecord(
    choice: DailyChoice(
      id: id,
      sourceIntentionId: _intentionId(from),
      selectedIntentionId: _intentionId(to),
      date: CalendarDate.fromParts(2026, 10, 2),
      description: null,
      isCompleted: false,
    ),
    path: StoredChoicePath([
      ChoicePathStep(
        id: _stepId(number),
        dailyChoiceId: id,
        relationId: _relationId(through),
        previousStepId: null,
      ),
    ]),
  );
}

TagId _tagId(int number) =>
    (TagId.decode(_uuid('7b0e2f4c', number)) as TagIdDecodingSuccess).id;

IntentionId _intentionId(int number) => (IntentionId.decode(
  _uuid('1f6c7a2e', number),
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  _uuid('2a3b4c5d', number),
) as LongTermRelationIdDecodingSuccess).id;

DailyChoiceId _dailyChoiceId(int number) => (DailyChoiceId.decode(
  _uuid('3c4d5e6f', number),
) as DailyChoiceIdDecodingSuccess).id;

ChoicePathStepId _stepId(int number) => (ChoicePathStepId.decode(
  _uuid('4d5e6f7a', number),
) as ChoicePathStepIdDecodingSuccess).id;

/// Идентификаторы с одним префиксом упорядочены по [number].
String _uuid(String prefix, int number) =>
    '$prefix-1d3a-4c5e-8f60-0a1b2c3d4e${number.toString().padLeft(2, '0')}';
