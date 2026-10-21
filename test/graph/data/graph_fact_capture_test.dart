import 'dart:convert';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/graph/data/graph_fact_capture.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_seed.dart';
import '../../support/local_database_harness.dart';

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
const _choice = '018f0b5d-6b2e-7c80-8000-000000000031';
const _firstStep = '018f0b5d-6b2e-7c80-8000-000000000041';
const _secondStep = '018f0b5d-6b2e-7c80-8000-000000000042';
const _directStep = '018f0b5d-6b2e-7c80-8000-000000000043';

final _createdAt = DateTime.utc(2026, 10, 17, 9);
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
    bool ready = false,
    DateTime? createdAt,
  }) => write(
    'INSERT INTO intentions '
    '(id, title, description, is_action_ready, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [
      id,
      title,
      description,
      ready ? 1 : 0,
      (createdAt ?? _createdAt).microsecondsSinceEpoch,
      (createdAt ?? _createdAt).microsecondsSinceEpoch,
    ],
  );

  Future<void> addRelation(String id, String source, String related) => write(
    'INSERT INTO long_term_relations '
    '(id, source_intention_id, related_intention_id, type, priority) '
    "VALUES (?, ?, ?, 'need', 1)",
    [id, source, related],
  );

  Future<void> addTag(String id, String name) =>
      write('INSERT INTO tags (id, name) VALUES (?, ?)', [id, name]);

  Future<void> assign(String tagId, String intentionId) => write(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagId, intentionId],
  );

  Future<void> addChoice() => write(
    'INSERT INTO daily_choices '
    '(id, source_intention_id, selected_intention_id, choice_date, '
    'description, is_completed, scheduled_minute, priority) '
    "VALUES (?, ?, ?, '2026-10-17', 'Сначала прогулка', 0, 570, 2)",
    [_choice, _source, _other],
  );

  Future<void> addStep(String id, String relation, [String? previous]) => write(
    'INSERT INTO daily_choice_path_steps '
    '(id, daily_choice_id, long_term_relation_id, previous_step_id) '
    'VALUES (?, ?, ?, ?)',
    [id, _choice, relation, previous],
  );

  /// Три намерения, связи «источник → выбранное → другое» и два тега.
  Future<void> addGraph() => arrange(() async {
    await addIntention(_source, 'Исходное намерение');
    await addIntention(_selected, 'Выбранное действие');
    await addIntention(_other, 'Другое действие');
    await addRelation(_relation, _source, _selected);
    await addRelation(_secondRelation, _selected, _other);
    await addTag(_tagA, 'Дом');
    await addTag(_tagB, 'Работа');
  });

  Future<int> remainingMarks() async {
    final row = await database.customSelect('''
      SELECT
        (SELECT count(*) FROM graph_log_tag_marks) +
        (SELECT count(*) FROM graph_log_intention_marks) +
        (SELECT count(*) FROM graph_log_tag_assignment_marks) +
        (SELECT count(*) FROM graph_log_long_term_relation_marks) +
        (SELECT count(*) FROM graph_log_daily_choice_marks) AS marks
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
        ready: true,
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
            ready: true,
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
        _source,
      ]);
      await write(
        "UPDATE intentions SET title = 'Новое название', "
        "description = 'Описание', is_action_ready = 1, updated_at = ? "
        'WHERE id = ?',
        [_updatedAt.microsecondsSinceEpoch, _source],
      );
    });

    expect(
      _lines(facts),
      _lines([
        GraphEntityChanged(
          _intention(
            _source,
            'Новое название',
            description: 'Описание',
            ready: true,
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

  group('дневной выбор', () {
    test('создание даёт факт «создана» со всем путём от исходного намерения '
        'к выбранному', () async {
      await addGraph();

      final facts = await capture(() async {
        await addChoice();
        await addStep(_secondStep, _secondRelation, _firstStep);
        await addStep(_firstStep, _relation);
      });

      expect(
        _lines(facts),
        _lines([
          GraphEntityCreated(
            _choiceRecord([
              _step(_firstStep, _relation),
              _step(_secondStep, _secondRelation, _firstStep),
            ]),
          ),
        ]),
      );
    });

    test('замена пути даёт факт «изменена» с новым путём', () async {
      await addGraph();
      await arrange(() async {
        await addRelation(_directRelation, _source, _other);
        await addChoice();
        await addStep(_firstStep, _relation);
        await addStep(_secondStep, _secondRelation, _firstStep);
      });

      final facts = await capture(() async {
        await write('DELETE FROM daily_choice_path_steps');
        await addStep(_directStep, _directRelation);
      });

      expect(
        _lines(facts),
        _lines([
          GraphEntityChanged(
            _choiceRecord([_step(_directStep, _directRelation)]),
          ),
        ]),
      );
    });

    test(
      'удаление вместе с шагами пути даёт факт «удалена» для выбора',
      () async {
        await addGraph();
        await arrange(() async {
          await addChoice();
          await addStep(_firstStep, _relation);
          await addStep(_secondStep, _secondRelation, _firstStep);
        });

        final facts = await capture(
          () => write('DELETE FROM daily_choices WHERE id = ?', [_choice]),
        );

        expect(
          _lines(facts),
          _lines([GraphEntityDeleted(DailyChoiceKey(_dailyChoiceId(_choice)))]),
        );
      },
    );
  });

  test('сущности, созданные и удалённые в одной транзакции, фактов не '
      'дают', () async {
    await addGraph();

    final facts = await capture(() async {
      await addIntention(_created, 'Временное намерение');
      await addTag('018f0b5d-6b2e-7c80-8000-000000000023', 'Временный тег');
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
  bool ready = false,
  bool archived = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => IntentionRecord(
  Intention(
    id: _intentionId(id),
    title: title,
    description: description,
    readiness: ready ? IntentionReadiness.ready : IntentionReadiness.notReady,
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
);

DailyChoiceRecord _choiceRecord(List<ChoicePathStep> path) => DailyChoiceRecord(
  choice: DailyChoice(
    id: _dailyChoiceId(_choice),
    sourceIntentionId: _intentionId(_source),
    selectedIntentionId: _intentionId(_other),
    date: CalendarDate.parseCanonical('2026-10-17'),
    description: DailyChoiceDescription.fromStored('Сначала прогулка'),
    isCompleted: false,
    schedule: DailyChoiceTime(hour: 9, minute: 30),
    priority: DailyChoicePriority.p2,
  ),
  path: StoredChoicePath(path),
);

ChoicePathStep _step(String id, String relation, [String? previous]) =>
    ChoicePathStep(
      id: _stepId(id),
      dailyChoiceId: _dailyChoiceId(_choice),
      relationId: _relationId(relation),
      previousStepId: previous == null ? null : _stepId(previous),
    );

TagId _tagId(String value) => (TagId.decode(value) as TagIdDecodingSuccess).id;

IntentionId _intentionId(String value) =>
    (IntentionId.decode(value) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(String value) =>
    (LongTermRelationId.decode(value) as LongTermRelationIdDecodingSuccess).id;

DailyChoiceId _dailyChoiceId(String value) =>
    (DailyChoiceId.decode(value) as DailyChoiceIdDecodingSuccess).id;

ChoicePathStepId _stepId(String value) =>
    (ChoicePathStepId.decode(value) as ChoicePathStepIdDecodingSuccess).id;
