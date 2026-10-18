import 'dart:convert';
import 'dart:io';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final version1 = GraphFormatVersion.ofCarrier(1);

  group('формат данных графа версии 1', () {
    test('эталонный пакет фактов читается в ожидаемые факты каждого вида и '
        'повторно кодируется в те же байты', () {
      final golden = File(
        'test/graph_format/golden/graph_fact_package_v1.jsonl',
      ).readAsBytesSync();

      final facts = GraphFormatCodec.decodePackage(golden, version1);

      // Кодирование каноническое и передаёт вид и каждое поле, поэтому
      // совпадение байтов означает совпадение прочитанных фактов с ожидаемыми.
      expect(GraphFormatCodec.encodePackage(facts), golden);
      expect(GraphFormatCodec.encodePackage(_expectedGoldenFacts()), golden);
    });

    test('удаление сущности читается только как факт пакета', () {
      final deletion = utf8.encode(
        '{"fact":"deleted","entity":"tag","id":"${_tagIds[1]}"}',
      );

      expect(
        GraphFormatCodec.decodeFact(deletion, version1).single,
        isA<GraphEntityDeleted>(),
      );
      expect(
        () => GraphFormatCodec.decodeEntityRecord(deletion, version1),
        throwsA(isA<GraphFormatCorruption>()),
      );
    });

    test('запись ровно на пределе кодируется и читается, '
        'а на байт длиннее отклоняется', () {
      IntentionRecord withDescription(String description) => IntentionRecord(
        Intention(
          id: _intentionId(_intentionIds[0]),
          title: 'Заметки',
          description: description,
          readiness: IntentionReadiness.notReady,
          archiveState: IntentionArchiveState.active,
          createdAt: IntentionTimestamp(DateTime.utc(2026, 10, 17)),
          updatedAt: IntentionTimestamp(DateTime.utc(2026, 10, 17)),
        ),
      );
      // Один графемный кластер из буквы с комбинирующими знаками по два байта
      // UTF-8 укладывается в предел описания, но не в предел записи.
      final base = GraphFormatCodec.encode(withDescription('a')).length;
      final missing = graphFormatRecordByteLimit - base;
      final atLimit = withDescription(
        'a${'́' * (missing ~/ 2)}${'b' * (missing % 2)}',
      );
      final overLimit = withDescription('${atLimit.intention.description}b');

      final encoded = GraphFormatCodec.encode(atLimit);

      expect(encoded, hasLength(graphFormatRecordByteLimit));
      expect(
        GraphFormatCodec.encode(
          GraphFormatCodec.decodeEntityRecord(encoded, version1).single,
        ),
        encoded,
      );
      expect(
        () => GraphFormatCodec.encode(overLimit),
        throwsA(isA<GraphRecordTooLong>()),
      );
    });

    test('отклоняет неизвестное поле, неизвестный или отсутствующий вид '
        'факта, неизвестный вид записи и недопустимое значение отказом '
        'повреждения', () {
      const created = '"fact":"created"';
      final tag = '$created,"kind":"tag","id":"${_tagIds[0]}"';
      final intention =
          '$created,"kind":"intention","id":"${_intentionIds[0]}",'
          '"title":"Здоровье","description":null,'
          '"actionReady":false,"archived":false';
      const createdAt = '"createdAt":"2026-03-29T00:00:00.000000Z"';
      const updatedAt = '"updatedAt":"2026-10-17T21:04:05.123456Z"';
      final relation =
          '$created,"kind":"longTermRelation","id":"${_relationIds[0]}",'
          '"sourceIntentionId":"${_intentionIds[0]}",'
          '"relatedIntentionId":"${_intentionIds[1]}"';
      final choice =
          '$created,"kind":"dailyChoice","id":"${_dailyChoiceIds[0]}",'
          '"sourceIntentionId":"${_intentionIds[0]}"';
      final selected = '"selectedIntentionId":"${_intentionIds[1]}"';
      const choiceDate = '"date":"2026-10-17"';
      const choiceRest = '"priority":"P2","completed":false,"description":null';
      final path =
          '"path":[{"id":"${_stepIds[0]}","relationId":"${_relationIds[0]}"}]';
      String validChoice({
        String date = choiceDate,
        String time = '"time":null',
        required String path,
      }) => '{$choice,$selected,$date,$time,$choiceRest,$path}';

      // Каждая недопустимая строка отличается от одной из этих лишь причиной.
      final validLines = [
        '{$tag,"name":"Дом"}',
        '{$intention,$createdAt,$updatedAt}',
        '{$relation,"type":"need","priority":"P1","description":null,'
            '"archived":false}',
        validChoice(path: path),
        '{"fact":"deleted","entity":"tag","id":"${_tagIds[0]}"}',
      ];
      for (final line in validLines) {
        expect(
          GraphFormatCodec.decodeFact(utf8.encode(line), version1),
          hasLength(1),
        );
      }

      final invalidLines = {
        'неизвестное поле': '{$tag,"name":"Дом","color":"red"}',
        'отсутствующее поле': '{$tag}',
        // Так записаны факты в пакетах сборок этапов 1 и 2.
        'отсутствующий вид факта':
            '{"kind":"tag","id":"${_tagIds[0]}","name":"Дом"}',
        'неизвестный вид факта':
            '{"fact":"renamed","kind":"tag","id":"${_tagIds[0]}",'
            '"name":"Дом"}',
        'неизвестный вид записи':
            '{$created,"kind":"note","id":"${_tagIds[0]}"}',
        'неизвестный вид удалённой сущности':
            '{"fact":"deleted","entity":"note","id":"${_tagIds[0]}"}',
        'значение не того типа JSON':
            '{$created,"kind":"intention","id":"${_intentionIds[0]}",'
            '"title":"Здоровье","description":null,"actionReady":false,'
            '"archived":"false",$createdAt,$updatedAt}',
        'строка не объект JSON': '["kind","tag"]',
        'неполный JSON': '{$tag,"name":"Дом"',
        'идентификатор не в канонической записи':
            '{$created,"kind":"tag","id":"${_tagIds[0].toUpperCase()}",'
            '"name":"Дом"}',
        'название намерения с окружающими пробелами':
            '{$created,"kind":"intention","id":"${_intentionIds[0]}",'
            '"title":" Здоровье","description":null,"actionReady":false,'
            '"archived":false,$createdAt,$updatedAt}',
        'пробельное описание намерения':
            '{$created,"kind":"intention","id":"${_intentionIds[0]}",'
            '"title":"Здоровье","description":" \\n","actionReady":false,'
            '"archived":false,$createdAt,$updatedAt}',
        'название тега с окружающими пробелами': '{$tag,"name":"Дом "}',
        'время без микросекунд':
            '{$intention,"createdAt":"2026-03-29T00:00:00.000Z",$updatedAt}',
        'время не в UTC':
            '{$intention,"createdAt":"2026-03-29T03:00:00.000000+03:00",'
            '$updatedAt}',
        'несуществующий момент времени':
            '{$intention,"createdAt":"2026-02-30T00:00:00.000000Z",'
            '$updatedAt}',
        'неизвестный тип связи':
            '{$relation,"type":"must","priority":"P1","description":null,'
            '"archived":false}',
        'неизвестный приоритет':
            '{$relation,"type":"need","priority":"P5","description":null,'
            '"archived":false}',
        'пробельное описание связи':
            '{$relation,"type":"need","priority":"P1","description":"  ",'
            '"archived":false}',
        'несуществующая дата дневного выбора': validChoice(
          date: '"date":"2026-02-30"',
          path: path,
        ),
        'время дня вне суток': validChoice(time: '"time":"24:00"', path: path),
        'время дня без ведущего нуля': validChoice(
          time: '"time":"9:05"',
          path: path,
        ),
        'пустой путь выбора': validChoice(path: '"path":[]'),
        'повторный шаг пути': validChoice(
          path:
              '"path":[{"id":"${_stepIds[0]}","relationId":"${_relationIds[0]}"},'
              '{"id":"${_stepIds[0]}","relationId":"${_relationIds[1]}"}]',
        ),
        'дневной выбор с совпадающими участниками':
            '{$choice,"selectedIntentionId":"${_intentionIds[0]}",'
            '$choiceDate,"time":null,$choiceRest,$path}',
      };

      for (final MapEntry(key: reason, value: line) in invalidLines.entries) {
        expect(
          () => GraphFormatCodec.decodeFact(utf8.encode(line), version1),
          throwsA(isA<GraphFormatCorruption>()),
          reason: reason,
        );
      }
      expect(
        () => GraphFormatCodec.decodeFact([0x7b, 0xff, 0x7d], version1),
        throwsA(isA<GraphFormatCorruption>()),
        reason: 'недопустимый UTF-8',
      );
    });

    test('отказ повреждения не раскрывает содержимое записи', () {
      final line = utf8.encode('{"kind":"tag","name":"Личный секрет"');

      Object? failure;
      try {
        GraphFormatCodec.decodeFact(line, version1);
      } on GraphFormatCorruption catch (error) {
        failure = error;
      }

      expect(failure, isA<GraphFormatCorruption>());
      expect(failure.toString(), isNot(contains('секрет')));
    });

    test('версия носителя новее текущей отклоняется отдельным отказом', () {
      expect(GraphFormatVersion.current.number, 1);
      expect(
        () => GraphFormatVersion.ofCarrier(2),
        throwsA(isA<GraphFormatVersionTooNew>()),
      );
      expect(
        () => GraphFormatVersion.ofCarrier(0),
        throwsA(isA<GraphFormatCorruption>()),
      );
    });
  });
}

const _tagIds = [
  '7b0e2f4c-1d3a-4c5e-8f60-0a1b2c3d4e01',
  '7b0e2f4c-1d3a-4c5e-8f60-0a1b2c3d4e02',
  '7b0e2f4c-1d3a-4c5e-8f60-0a1b2c3d4e03',
];
const _intentionIds = [
  '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f01',
  '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f02',
  '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f03',
  '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f04',
];
const _relationIds = [
  '2a3b4c5d-6e7f-4a80-b91c-0d1e2f3a4b01',
  '2a3b4c5d-6e7f-4a80-b91c-0d1e2f3a4b02',
  '2a3b4c5d-6e7f-4a80-b91c-0d1e2f3a4b03',
];
const _dailyChoiceIds = [
  '3c4d5e6f-7a8b-4c9d-a0e1-1f2a3b4c5d01',
  '3c4d5e6f-7a8b-4c9d-a0e1-1f2a3b4c5d02',
  '3c4d5e6f-7a8b-4c9d-a0e1-1f2a3b4c5d03',
];
const _stepIds = [
  '4d5e6f7a-8b9c-4dae-bf01-2a3b4c5d6e01',
  '4d5e6f7a-8b9c-4dae-bf01-2a3b4c5d6e02',
  '4d5e6f7a-8b9c-4dae-bf01-2a3b4c5d6e03',
];

List<GraphFact> _expectedGoldenFacts() {
  final health = _intentionId(_intentionIds[0]);
  final running = _intentionId(_intentionIds[1]);
  final jogging = _intentionId(_intentionIds[2]);
  final needRunning = _relationId(_relationIds[0]);
  final canJog = _relationId(_relationIds[1]);
  final allDayChoice = _dailyChoiceId(_dailyChoiceIds[0]);
  final midnightChoice = _dailyChoiceId(_dailyChoiceIds[1]);
  final home = _tagId(_tagIds[0]);
  final work = _tagId(_tagIds[2]);

  return [
    GraphEntityCreated(
      TagRecord(Tag(id: home, name: TagName.fromStored('Дом'))),
    ),
    GraphEntityChanged(
      TagRecord(Tag(id: work, name: TagName.fromStored('Работа'))),
    ),
    GraphEntityChanged(
      IntentionRecord(
        Intention(
          id: health,
          title: 'Здоровье',
          description: null,
          readiness: IntentionReadiness.notReady,
          archiveState: IntentionArchiveState.active,
          createdAt: IntentionTimestamp(DateTime.utc(2026, 3, 29)),
          updatedAt: IntentionTimestamp(
            DateTime.utc(2026, 10, 17, 21, 4, 5, 123, 456),
          ),
        ),
      ),
    ),
    GraphEntityChanged(
      IntentionRecord(
        Intention(
          id: running,
          title: 'Бегать по утрам 🏃',
          description: '  Первая строка\n\tвторая "строка"  \n',
          readiness: IntentionReadiness.ready,
          archiveState: IntentionArchiveState.archived,
          createdAt: IntentionTimestamp(
            DateTime.utc(2026, 10, 1, 6, 30, 0, 0, 1),
          ),
          updatedAt: IntentionTimestamp(
            DateTime.utc(2026, 10, 2, 7, 0, 0, 500),
          ),
        ),
      ),
    ),
    GraphEntityCreated(
      IntentionRecord(
        Intention(
          id: jogging,
          title: 'Пробежка 5 км',
          description: null,
          readiness: IntentionReadiness.ready,
          archiveState: IntentionArchiveState.active,
          createdAt: IntentionTimestamp(DateTime.utc(2026, 10, 1, 6, 31)),
          updatedAt: IntentionTimestamp(DateTime.utc(2026, 10, 1, 6, 31)),
        ),
      ),
    ),
    GraphEntityCreated(
      TagAssignmentRecord(TagAssignment(tagId: home, intentionId: health)),
    ),
    GraphEntityChanged(
      TagAssignmentRecord(TagAssignment(tagId: work, intentionId: running)),
    ),
    GraphEntityCreated(
      LongTermRelationRecord(
        id: needRunning,
        sourceIntentionId: health,
        relatedIntentionId: running,
        type: LongTermRelationType.need,
        priority: RelationPriority.p1,
        description: null,
        scope: RelationScope.active,
      ),
    ),
    GraphEntityChanged(
      LongTermRelationRecord(
        id: canJog,
        sourceIntentionId: running,
        relatedIntentionId: jogging,
        type: LongTermRelationType.can,
        priority: RelationPriority.p4,
        description: LongTermRelationDescription.fromInput(
          '\n Темп\nлёгкий \n',
        ),
        scope: RelationScope.archived,
      ),
    ),
    GraphEntityCreated(
      DailyChoiceRecord(
        choice: DailyChoice(
          id: allDayChoice,
          sourceIntentionId: health,
          selectedIntentionId: jogging,
          date: CalendarDate.fromParts(2026, 10, 17),
          description: null,
          isCompleted: false,
          priority: DailyChoicePriority.p2,
        ),
        path: StoredChoicePath([
          ChoicePathStep(
            id: _stepId(_stepIds[0]),
            dailyChoiceId: allDayChoice,
            relationId: needRunning,
            previousStepId: null,
          ),
          ChoicePathStep(
            id: _stepId(_stepIds[1]),
            dailyChoiceId: allDayChoice,
            relationId: canJog,
            previousStepId: _stepId(_stepIds[0]),
          ),
        ]),
      ),
    ),
    GraphEntityChanged(
      DailyChoiceRecord(
        choice: DailyChoice(
          id: midnightChoice,
          sourceIntentionId: health,
          selectedIntentionId: running,
          date: CalendarDate.fromParts(2026, 2, 28),
          description: DailyChoiceDescription.fromStored('  утром\n'),
          isCompleted: true,
          schedule: DailyChoiceTime(hour: 0, minute: 0),
          priority: DailyChoicePriority.p4,
        ),
        path: StoredChoicePath([
          ChoicePathStep(
            id: _stepId(_stepIds[2]),
            dailyChoiceId: midnightChoice,
            relationId: needRunning,
            previousStepId: null,
          ),
        ]),
      ),
    ),
    GraphEntityDeleted(TagKey(_tagId(_tagIds[1]))),
    GraphEntityDeleted(IntentionKey(_intentionId(_intentionIds[3]))),
    GraphEntityDeleted(
      TagAssignmentKey(TagAssignment(tagId: home, intentionId: running)),
    ),
    GraphEntityDeleted(LongTermRelationKey(_relationId(_relationIds[2]))),
    GraphEntityDeleted(DailyChoiceKey(_dailyChoiceId(_dailyChoiceIds[2]))),
  ];
}

TagId _tagId(String value) => (TagId.decode(value) as TagIdDecodingSuccess).id;

IntentionId _intentionId(String value) =>
    (IntentionId.decode(value) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(String value) =>
    (LongTermRelationId.decode(value) as LongTermRelationIdDecodingSuccess).id;

DailyChoiceId _dailyChoiceId(String value) =>
    (DailyChoiceId.decode(value) as DailyChoiceIdDecodingSuccess).id;

ChoicePathStepId _stepId(String value) =>
    (ChoicePathStepId.decode(value) as ChoicePathStepIdDecodingSuccess).id;
