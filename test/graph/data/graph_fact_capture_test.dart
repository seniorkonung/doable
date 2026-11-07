import 'dart:convert';

import 'package:doable/src/action/domain/action.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/graph/data/graph_fact_capture.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_positions.dart';

const _source = '018f0b5d-6b2e-7c80-8000-000000000001';
const _selected = '018f0b5d-6b2e-7c80-8000-000000000002';
const _other = '018f0b5d-6b2e-7c80-8000-000000000003';
const _created = '018f0b5d-6b2e-7c80-8000-000000000004';
const _later = '018f0b5d-6b2e-7c80-8000-000000000005';
const _relation = '018f0b5d-6b2e-7c80-8000-000000000011';
const _secondRelation = '018f0b5d-6b2e-7c80-8000-000000000012';
const _directRelation = '018f0b5d-6b2e-7c80-8000-000000000013';
const _tagA = '018f0b5d-6b2e-7c80-8000-000000000021';
const _tagB = '018f0b5d-6b2e-7c80-8000-000000000022';
const _fullAction = '018f0b5d-6b2e-7c80-8000-000000000051';
const _shortAction = '018f0b5d-6b2e-7c80-8000-000000000052';

final _createdAt = DateTime.utc(2026, 10, 17, 9);
final _relationCreatedAt = DateTime.utc(2026, 10, 17, 9, 30);
final _relationUpdatedAt = DateTime.utc(2026, 10, 17, 10, 15, 0, 250);
final _updatedAt = DateTime.utc(2026, 10, 17, 10, 30, 0, 0, 1);

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
    await database.open();
  });

  tearDown(() => harness.dispose());

  Future<void> write(String sql, [List<Object?> arguments = const []]) =>
      database.customStatement(sql, arguments);

  /// Выполняет [writes] одной транзакцией с признаком записи, как единый
  /// путь записи графа, и превращает её отметки в факты.
  Future<List<GraphFact>> capture(Future<void> Function() writes) =>
      database.transaction(() async {
        await write('UPDATE graph_log_control SET writing = 1');
        await writes();
        final facts = await GraphFactCapture(database).takeFacts();
        await write('UPDATE graph_log_control SET writing = 0');
        return facts;
      });

  /// Записывает исходное состояние графа без отметок.
  Future<void> arrange(Future<void> Function() writes) =>
      seedGraph(database, writes);

  Future<void> addIntention(
    String id,
    String title, {
    String? description,
    DateTime? createdAt,
  }) => write(
    'INSERT INTO intentions '
    '(id, title, description, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      id,
      title,
      description,
      (createdAt ?? _createdAt).microsecondsSinceEpoch,
      (createdAt ?? _createdAt).microsecondsSinceEpoch,
    ],
  );

  Future<void> addRelation(String id, String source, String related) => write(
    'INSERT INTO long_term_relations '
    '(id, source_intention_id, related_intention_id, type, priority, '
    'created_at, updated_at) '
    "VALUES (?, ?, ?, 'need', 1, ?, ?)",
    [
      id,
      source,
      related,
      _relationCreatedAt.microsecondsSinceEpoch,
      _relationUpdatedAt.microsecondsSinceEpoch,
    ],
  );

  Future<void> addTag(String id, String name, String position) => write(
    'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
    [id, name, position],
  );

  Future<void> assign(String tagId, String intentionId) => write(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagId, intentionId],
  );

  Future<void> addAction(String id, List<String> path) async {
    await write(
      'INSERT INTO actions (id, title, date, priority, is_completed, '
      "created_at, updated_at) VALUES (?, 'Пробежка', '2026-10-17', 4, 0, ?, ?)",
      [
        id,
        _createdAt.microsecondsSinceEpoch,
        _createdAt.microsecondsSinceEpoch,
      ],
    );
    for (final (position, intention) in path.indexed) {
      await write(insertActionPathItem, [
        id,
        position,
        intention,
        position == 0 ? null : path[position - 1],
        actionPathRole(position, path.length),
      ]);
    }
  }

  /// Три намерения, связи «источник → выбранное → другое» и два тега.
  Future<void> addGraph() => arrange(() async {
    await addIntention(_source, 'Исходное намерение');
    await addIntention(_selected, 'Выбранное действие');
    await addIntention(_other, 'Другое действие');
    await addRelation(_relation, _source, _selected);
    await addRelation(_secondRelation, _selected, _other);
    await addTag(_tagA, 'Дом', 'a1');
    await addTag(_tagB, 'Работа', 'a0');
  });

  Future<int> remainingMarks() async {
    final row = await database.customSelect('''
      SELECT
        (SELECT count(*) FROM graph_log_tag_marks) +
        (SELECT count(*) FROM graph_log_intention_marks) +
        (SELECT count(*) FROM graph_log_tag_assignment_marks) +
        (SELECT count(*) FROM graph_log_long_term_relation_marks) +
        (SELECT count(*) FROM graph_log_action_marks) +
        (SELECT count(*) FROM graph_log_deleted_intention_marks) +
        (SELECT count(*) FROM graph_log_deleted_relation_pair_marks) AS marks
    ''').getSingle();
    return row.read<int>('marks');
  }

  test('после пакета отметок не остаётся, и следующая транзакция без '
      'изменений пакета не даёт', () async {
    await addGraph();
    await capture(() => addIntention(_created, 'Новое намерение'));

    expect(await remainingMarks(), 0);
    expect(await capture(() async {}), isEmpty);
  });

  test('создание намерения с тегами даёт факты «создана» с его полной '
      'записью и назначениями в порядке их создания', () async {
    await addGraph();

    final facts = await capture(() async {
      await addIntention(
        _created,
        'Новое намерение',
        description: '  Первая строка\nвторая строка  ',
      );
      await assign(_tagB, _created);
      await assign(_tagA, _created);
    });

    expect(
      _lines(facts),
      _lines([
        GraphEntityCreated(
          _intention(
            _created,
            'Новое намерение',
            description: '  Первая строка\nвторая строка  ',
          ),
        ),
        GraphEntityCreated(_assignment(_tagB, _created)),
        GraphEntityCreated(_assignment(_tagA, _created)),
      ]),
    );
  });

  test('намерения пакета идут по времени создания и идентификатору, '
      'а не по порядку записи', () async {
    final earlier = _createdAt.subtract(const Duration(hours: 1));

    final facts = await capture(() async {
      await addIntention(_later, 'Создано первым');
      await addIntention(_created, 'После перевода часов', createdAt: earlier);
      await addIntention(_source, 'В тот же момент', createdAt: earlier);
    });

    expect(
      _lines(facts),
      _lines([
        GraphEntityCreated(
          _intention(_source, 'В тот же момент', createdAt: earlier),
        ),
        GraphEntityCreated(
          _intention(_created, 'После перевода часов', createdAt: earlier),
        ),
        GraphEntityCreated(_intention(_later, 'Создано первым')),
      ]),
    );
  });

  test('изменение намерения даёт один факт «изменена» с состоянием после '
      'транзакции', () async {
    await addGraph();

    final facts = await capture(() async {
      await write("UPDATE intentions SET title = 'Черновик' WHERE id = ?", [
        _selected,
      ]);
      await write(
        "UPDATE intentions SET title = 'Новое название', "
        "description = 'Описание', kind = 'supporting', updated_at = ? "
        'WHERE id = ?',
        [_updatedAt.microsecondsSinceEpoch, _selected],
      );
    });

    expect(
      _lines(facts),
      _lines([
        GraphEntityChanged(
          _intention(
            _selected,
            'Новое название',
            description: 'Описание',
            kind: IntentionKind.supporting,
            updatedAt: _updatedAt,
          ),
        ),
      ]),
    );
  });

  test('архивирование намерения вместе со связями даёт факты «изменена» в '
      'порядке секций и создания связей', () async {
    await addGraph();

    final facts = await capture(() async {
      for (final relation in [_secondRelation, _relation]) {
        await write(
          'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
          [relation],
        );
      }
      await write('UPDATE intentions SET is_archived = 1 WHERE id = ?', [
        _selected,
      ]);
    });

    expect(
      _lines(facts),
      _lines([
        GraphEntityChanged(
          _intention(_selected, 'Выбранное действие', archived: true),
        ),
        GraphEntityChanged(
          _relationRecord(_relation, _source, _selected, archived: true),
        ),
        GraphEntityChanged(
          _relationRecord(_secondRelation, _selected, _other, archived: true),
        ),
      ]),
    );
  });

  test('переименование тега даёт факт «изменена» с новым названием', () async {
    await addGraph();

    final facts = await capture(
      () => write("UPDATE tags SET name = 'Дача' WHERE id = ?", [_tagA]),
    );

    expect(
      _lines(facts),
      _lines([
        GraphEntityChanged(
          TagRecord(
            Tag(
              id: _tagId(_tagA),
              name: TagName.fromStored('Дача'),
              color: null,
              position: tagPosition('a1'),
            ),
          ),
        ),
      ]),
    );
  });

  test('изменение только цвета тега даёт факт «изменена» с новым '
      'цветом', () async {
    await addGraph();

    final facts = await capture(
      () => write("UPDATE tags SET color = 'blue' WHERE id = ?", [_tagA]),
    );

    expect(
      _lines(facts),
      _lines([
        GraphEntityChanged(
          TagRecord(
            Tag(
              id: _tagId(_tagA),
              name: TagName.fromStored('Дом'),
              color: TagColor.blue,
              position: tagPosition('a1'),
            ),
          ),
        ),
      ]),
    );
  });

  test('удаление тега даёт факты «удалена» для тега и каждого его '
      'назначения', () async {
    await addGraph();
    await arrange(() async {
      await assign(_tagA, _selected);
      await assign(_tagA, _source);
      await assign(_tagB, _source);
    });

    final facts = await capture(
      () => write('DELETE FROM tags WHERE id = ?', [_tagA]),
    );

    expect(
      _lines(facts),
      _lines([
        GraphEntityDeleted(TagKey(_tagId(_tagA))),
        GraphEntityDeleted(TagAssignmentKey(_tagAssignment(_tagA, _source))),
        GraphEntityDeleted(TagAssignmentKey(_tagAssignment(_tagA, _selected))),
      ]),
    );
  });

  group('действие и надгробия', () {
    /// Граф [addGraph] с действием по всему пути «источник → выбранное →
    /// другое» и действием по его началу.
    Future<void> addActions() async {
      await addGraph();
      await arrange(() async {
        await addAction(_fullAction, [_source, _selected, _other]);
        await addAction(_shortAction, [_source, _selected]);
      });
    }

    test('изменение полей действия даёт один факт «изменена» с полями и '
        'путём', () async {
      await addActions();

      final facts = await capture(() async {
        await write("UPDATE actions SET title = 'Черновик' WHERE id = ?", [
          _fullAction,
        ]);
        await write(
          "UPDATE actions SET title = 'Пробежка у реки', "
          "description = 'Не спеша', date = '2026-10-19', "
          'scheduled_hour = 7, priority = 1, is_completed = 1, '
          'updated_at = ? WHERE id = ?',
          [_updatedAt.microsecondsSinceEpoch, _fullAction],
        );
      });

      expect(
        _lines(facts),
        _lines([
          GraphEntityChanged(
            ActionRecord(
              id: _actionId(_fullAction),
              title: ActionTitle('Пробежка у реки'),
              description: ActionDescription.fromInput('Не спеша'),
              path: _actionPath([_source, _selected, _other]),
              date: CalendarDate.parseCanonical('2026-10-19'),
              schedule: ActionAtHour(7),
              priority: ActionPriority.p1,
              isCompleted: true,
              createdAt: ActionTimestamp(_createdAt),
              updatedAt: ActionTimestamp(_updatedAt),
            ),
          ),
        ]),
      );
    });

    test('удаление намерения со связями из путей двух действий даёт по '
        'факту на надгробие и ни одного факта действий', () async {
      await addActions();

      final facts = await capture(() async {
        await write('DELETE FROM long_term_relations WHERE id IN (?, ?)', [
          _relation,
          _secondRelation,
        ]);
        await write('DELETE FROM intentions WHERE id = ?', [_selected]);
      });

      expect(
        _lines(facts),
        _lines([
          GraphEntityDeleted(IntentionKey(_intentionId(_selected))),
          GraphEntityCreated(
            DeletedIntentionRecord(
              id: _intentionId(_selected),
              title: 'Выбранное действие',
            ),
          ),
          GraphEntityDeleted(LongTermRelationKey(_relationId(_relation))),
          GraphEntityDeleted(LongTermRelationKey(_relationId(_secondRelation))),
          GraphEntityCreated(_pair(_source, _selected)),
          GraphEntityCreated(_pair(_selected, _other)),
        ]),
      );
    });

    test('новая связь пары снимает её надгробие фактом «удалена»', () async {
      await addActions();
      await arrange(
        () =>
            write('DELETE FROM long_term_relations WHERE id = ?', [_relation]),
      );

      final facts = await capture(
        () => addRelation(_directRelation, _source, _selected),
      );

      expect(
        _lines(facts),
        _lines([
          GraphEntityCreated(
            _relationRecord(
              _directRelation,
              _source,
              _selected,
              archived: false,
            ),
          ),
          GraphEntityDeleted(
            DeletedRelationPairKey(
              sourceIntentionId: _intentionId(_source),
              relatedIntentionId: _intentionId(_selected),
            ),
          ),
        ]),
      );
    });

    test('удаление последнего действия с удалёнными звеньями снимает их '
        'надгробия, а путь не даёт своих фактов', () async {
      await addActions();
      await arrange(() async {
        await write('DELETE FROM long_term_relations WHERE id = ?', [
          _secondRelation,
        ]);
        await write('DELETE FROM intentions WHERE id = ?', [_other]);
      });

      final facts = await capture(
        () => write('DELETE FROM actions WHERE id = ?', [_fullAction]),
      );

      expect(
        _lines(facts),
        _lines([
          GraphEntityDeleted(DeletedIntentionKey(_intentionId(_other))),
          GraphEntityDeleted(
            DeletedRelationPairKey(
              sourceIntentionId: _intentionId(_selected),
              relatedIntentionId: _intentionId(_other),
            ),
          ),
          GraphEntityDeleted(ActionKey(_actionId(_fullAction))),
        ]),
      );
    });
  });

  test('сущности, созданные и удалённые в одной транзакции, фактов не '
      'дают', () async {
    await addGraph();

    final facts = await capture(() async {
      await addIntention(_created, 'Временное намерение');
      await addTag(
        '018f0b5d-6b2e-7c80-8000-000000000023',
        'Временный тег',
        'Zz',
      );
      await assign(_tagA, _created);
      await write('DELETE FROM intentions WHERE id = ?', [_created]);
      await write('DELETE FROM tags WHERE id = ?', [
        '018f0b5d-6b2e-7c80-8000-000000000023',
      ]);
    });

    expect(facts, isEmpty);
    expect(await remainingMarks(), 0);
  });
}

/// Строки пакета: кодирование каноническое и передаёт каждое поле, поэтому
/// совпадение строк означает совпадение фактов.
List<String> _lines(List<GraphFact> facts) => const LineSplitter().convert(
  utf8.decode(GraphFormatCodec.encodePackage(facts)),
);

IntentionRecord _intention(
  String id,
  String title, {
  String? description,
  IntentionKind kind = IntentionKind.main,
  bool archived = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => IntentionRecord(
  Intention(
    id: _intentionId(id),
    title: title,
    description: description,
    kind: kind,
    archiveState: archived
        ? IntentionArchiveState.archived
        : IntentionArchiveState.active,
    createdAt: IntentionTimestamp(createdAt ?? _createdAt),
    updatedAt: IntentionTimestamp(updatedAt ?? createdAt ?? _createdAt),
  ),
);

TagAssignmentRecord _assignment(String tagId, String intentionId) =>
    TagAssignmentRecord(_tagAssignment(tagId, intentionId));

TagAssignment _tagAssignment(String tagId, String intentionId) =>
    TagAssignment(tagId: _tagId(tagId), intentionId: _intentionId(intentionId));

LongTermRelationRecord _relationRecord(
  String id,
  String source,
  String related, {
  required bool archived,
}) => LongTermRelationRecord(
  id: _relationId(id),
  sourceIntentionId: _intentionId(source),
  relatedIntentionId: _intentionId(related),
  type: LongTermRelationType.need,
  priority: RelationPriority.p1,
  description: null,
  scope: archived ? RelationScope.archived : RelationScope.active,
  createdAt: RelationTimestamp(_relationCreatedAt),
  updatedAt: RelationTimestamp(_relationUpdatedAt),
);

DeletedRelationPairRecord _pair(String source, String related) =>
    DeletedRelationPairRecord(
      sourceIntentionId: _intentionId(source),
      relatedIntentionId: _intentionId(related),
      type: LongTermRelationType.need,
    );

ActionPath _actionPath(List<String> intentions) =>
    ActionPath([for (final id in intentions) _intentionId(id)]);

ActionId _actionId(String value) =>
    (ActionId.decode(value) as ActionIdDecodingSuccess).id;

TagId _tagId(String value) => (TagId.decode(value) as TagIdDecodingSuccess).id;

IntentionId _intentionId(String value) =>
    (IntentionId.decode(value) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(String value) =>
    (LongTermRelationId.decode(value) as LongTermRelationIdDecodingSuccess).id;
