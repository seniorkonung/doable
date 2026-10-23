import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_file.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tag_positions.dart';

void main() {
  final golden = File('test/graph_format/golden/graph_format_v1.jsonl')
      .readAsBytesSync();

  group('файл формата данных графа', () {
    test('проверка только заголовка закрывает подписку без ожидания '
        'остатка документа', () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(source.close);
      source.add(
        gzip.encode([
          ...GraphFormatCodec.encodeHeader(_expectedGoldenHeader()),
          0x0a,
        ]),
      );

      final reading = await GraphFormatFile.read(source.stream);
      await reading.close();

      expect(cancelled, isTrue);
    });

    test('эталонный файл версии 1 читается в ожидаемые записи, а повторная '
        'запись с тем же заголовком даёт те же байты JSON Lines', () async {
      final reading = await GraphFormatFile.read(
        Stream.value(gzip.encode(golden)),
      );
      final records = await reading.records.toList();

      // Кодирование каноническое и передаёт каждое поле, поэтому совпадение
      // байтов означает совпадение прочитанного с ожидаемым.
      expect(await _decompressed(reading.header, records), golden);
      expect(
        await _decompressed(_expectedGoldenHeader(), _expectedGoldenRecords()),
        golden,
      );
    });

    test(
      'записи пишутся и читаются потоком, не дожидаясь конца файла',
      () async {
        const tagCount = 200000;
        final header = GraphFormatHeader(
          writtenAt: DateTime.utc(2026, 10, 17),
          counts: GraphRecordCounts(
            tags: tagCount,
            intentions: 0,
            tagAssignments: 0,
            longTermRelations: 0,
            dailyChoices: 0,
          ),
        );
        var producedTags = 0;
        Stream<GraphEntityRecord> tags() async* {
          for (; producedTags < tagCount; producedTags++) {
            yield TagRecord(
              Tag(
                id: _tagId(_tagIds[0]),
                name: TagName.fromStored('Тег $producedTags'),
                color: null,
                position: tagPositionAt(producedTags),
              ),
            );
          }
        }

        final reading = await GraphFormatFile.read(
          GraphFormatFile.write(header, tags()),
        );
        final records = await reading.records.take(1000).toList();

        expect(records.map((record) => (record as TagRecord).tag.name.value), [
          for (var number = 0; number < 1000; number++) 'Тег $number',
        ]);
        // Первые записи прочитаны, когда большая часть файла ещё не записана.
        expect(producedTags, lessThan(tagCount ~/ 2));
      },
    );

    test('строка записи ровно на пределе читается, '
        'а на байт длиннее отклоняется отказом повреждения', () async {
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
      final base = GraphFormatCodec.encode(withDescription('a')).length;
      final missing = graphFormatRecordByteLimit - base;
      final atLimit = GraphFormatCodec.encode(
        withDescription('a${'́' * (missing ~/ 2)}${'b' * (missing % 2)}'),
      );
      // Пробел допустим в JSON, поэтому эту строку отклоняет только предел.
      final overLimit = [atLimit.first, 0x20, ...atLimit.skip(1)];
      final header = GraphFormatCodec.encodeHeader(
        GraphFormatHeader(
          writtenAt: DateTime.utc(2026, 10, 17),
          counts: GraphRecordCounts(
            tags: 0,
            intentions: 1,
            tagAssignments: 0,
            longTermRelations: 0,
            dailyChoices: 0,
          ),
        ),
      );
      List<int> fileWith(List<int> line) =>
          gzip.encode([...header, 0x0a, ...line, 0x0a]);

      final records = await _readAll(Stream.value(fileWith(atLimit)));

      expect(atLimit, hasLength(graphFormatRecordByteLimit));
      expect(GraphFormatCodec.encode(records.single), atLimit);
      await expectLater(
        _readAll(Stream.value(fileWith(overLimit))),
        throwsA(isA<GraphFormatCorruption>()),
      );
    });

    test('строка без перевода строки длиннее предела отклоняется, '
        'не дочитывая файл', () async {
      final header = GraphFormatCodec.encodeHeader(_expectedGoldenHeader());
      final cases = {
        'строка записи после заголовка': [...header, 0x0a],
        'первая строка чужого файла': <int>[],
      };

      for (final MapEntry(key: reason, value: prefix) in cases.entries) {
        final file = _UnterminatedLineFile(prefix);

        await expectLater(
          _readAll(file.compressed()),
          throwsA(isA<GraphFormatCorruption>()),
          reason: reason,
        );
        expect(
          file.sentLineBytes,
          lessThan(_UnterminatedLineFile.lineBytes ~/ 8),
          reason: reason,
        );
      }
    });

    test('чужой, повреждённый, обрезанный или несогласованный с заголовком '
        'файл отклоняется отказом повреждения', () async {
      final lines = utf8.decode(golden).split('\n')..removeLast();
      List<int> file(Iterable<String> lines) =>
          gzip.encode(utf8.encode('${lines.join('\n')}\n'));
      final compressed = gzip.encode(golden);
      final deletion =
          '{"kind":"deletion","entity":"dailyChoice",'
          '"id":"${_dailyChoiceIds[1]}"}';

      final invalidFiles = <String, List<int>>{
        'не gzip': [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
        'пустой файл': [],
        'сжатие zlib вместо gzip': zlib.encode(golden),
        'gzip с посторонним текстом': file(['Список покупок']),
        'заголовок без маркера Doable': file([
          lines.first.replaceFirst('doable-graph', 'other-app'),
          ...lines.skip(1),
        ]),
        'неизвестное поле заголовка': file([
          lines.first.replaceFirst('"version":1', '"version":1,"app":"x"'),
          ...lines.skip(1),
        ]),
        'обрезан по границе строки': file(lines.take(lines.length - 1)),
        'обрезан посреди строки': gzip.encode(
          golden.sublist(0, golden.length - 10),
        ),
        'незавершённая строка после последней записи': gzip.encode([
          ...golden,
          ...utf8.encode('{"kind":"tag"'),
        ]),
        'обрезан сжатый поток': compressed.sublist(0, compressed.length ~/ 2),
        'повреждена контрольная сумма gzip': Uint8List.fromList(compressed)
          ..[compressed.length - 8] ^= 0x01,
        'запись сверх количества в заголовке': file([...lines, lines.last]),
        'запись вне своей секции': file([
          lines.first,
          ...lines.skip(2),
          lines[1],
        ]),
        'удаление сущности': file([...lines.take(lines.length - 1), deletion]),
        'повторённое место тега': file([
          ...lines.take(2),
          lines[2].replaceFirst('"position":"a0V"', '"position":"a1"'),
          ...lines.skip(3),
        ]),
        'намерения не по возрастанию времени создания': file([
          ...lines.take(3),
          lines[4],
          lines[3],
          ...lines.skip(5),
        ]),
        'намерения одного времени создания не по возрастанию идентификатора':
            file([...lines.take(5), lines[6], lines[5], ...lines.skip(7)]),
        'повторённые время создания и идентификатор намерения': file([
          ...lines.take(6),
          lines[5],
          ...lines.skip(7),
        ]),
      };

      for (final MapEntry(key: reason, value: bytes) in invalidFiles.entries) {
        await expectLater(
          _readAll(Stream.value(bytes)),
          throwsA(isA<GraphFormatCorruption>()),
          reason: reason,
        );
      }
    });

    test('файл более новой версии отклоняется отдельным отказом', () async {
      // Поля заголовка новой версии неизвестны, поэтому версия проверяется
      // раньше них.
      final newer = utf8.encode(
        '{"format":"doable-graph","version":2,'
        '"writtenAt":"2030-01-01T00:00:00.000000Z","layout":"v2"}\n',
      );

      await expectLater(
        _readAll(Stream.value(gzip.encode(newer))),
        throwsA(isA<GraphFormatVersionTooNew>()),
      );
    });

    test('ошибка потока файла передаётся как есть, '
        'а не как повреждение', () async {
      final compressed = gzip.encode(golden);
      final failing = Stream<List<int>>.multi((controller) {
        controller
          ..add(compressed.sublist(0, compressed.length ~/ 2))
          ..addError(const FileSystemException('Доступ к документу отозван'))
          ..close();
      });

      await expectLater(_readAll(failing), throwsA(isA<FileSystemException>()));
    });

    test('запись отклоняет записи вне секций и количеств заголовка и '
        'намерения не в каноническом порядке', () async {
      final header = GraphFormatHeader(
        writtenAt: DateTime.utc(2026, 10, 17),
        counts: GraphRecordCounts(
          tags: 1,
          intentions: 2,
          tagAssignments: 0,
          longTermRelations: 0,
          dailyChoices: 0,
        ),
      );
      final [tag, _, health, running, ..., lastChoice] =
          _expectedGoldenRecords();
      final invalidRecords = {
        'запись вне своей секции': [health, tag, running],
        'записей больше, чем в заголовке': [tag, health, running, lastChoice],
        'записей меньше, чем в заголовке': [tag, health],
        'намерения не в каноническом порядке': [tag, running, health],
      };

      for (final MapEntry(key: reason, value: records)
          in invalidRecords.entries) {
        await expectLater(
          GraphFormatFile.write(
            header,
            Stream.fromIterable(records),
          ).drain<void>(),
          throwsStateError,
          reason: reason,
        );
      }
    });
  });
}

Future<List<GraphEntityRecord>> _readAll(Stream<List<int>> file) async {
  final reading = await GraphFormatFile.read(file);
  return reading.records.toList();
}

Future<List<int>> _decompressed(
  GraphFormatHeader header,
  List<GraphEntityRecord> records,
) async {
  final compressed = await GraphFormatFile.write(
    header,
    Stream.fromIterable(records),
  ).expand((chunk) => chunk).toList();
  return gzip.decode(compressed);
}

/// Сжатый файл, последняя строка которого после [prefix] занимает
/// [lineBytes] байтов без перевода строки.
final class _UnterminatedLineFile {
  _UnterminatedLineFile(this.prefix);

  static const lineBytes = 64 * 1024 * 1024;

  /// Буквы без повторов в окне deflate, чтобы сжатие отдавало их сразу, а
  /// отданное почти совпадало с прочитанным.
  static final _letters = () {
    var seed = 1;
    return Uint8List.fromList([
      for (var index = 0; index < 64 * 1024; index++)
        0x61 + (seed = (seed * 1103515245 + 12345) & 0x7fffffff) % 26,
    ]);
  }();

  final List<int> prefix;

  /// Сколько байтов строки отдано на сжатие к текущему моменту.
  var sentLineBytes = 0;

  Stream<List<int>> compressed() async* {
    final output = _Chunks();
    final encoder = gzip.encoder.startChunkedConversion(output)..add(prefix);
    while (sentLineBytes < lineBytes) {
      encoder.add(_letters);
      sentLineBytes += _letters.length;
      for (final chunk in output.take()) {
        yield chunk;
      }
    }
    encoder.close();
    for (final chunk in output.take()) {
      yield chunk;
    }
  }
}

final class _Chunks implements Sink<List<int>> {
  var _chunks = <List<int>>[];

  List<List<int>> take() {
    final chunks = _chunks;
    _chunks = [];
    return chunks;
  }

  @override
  void add(List<int> chunk) => _chunks.add(chunk);

  @override
  void close() {}
}

const _tagIds = [
  '7b0e2f4c-1d3a-4c5e-8f60-0a1b2c3d4e11',
  '7b0e2f4c-1d3a-4c5e-8f60-0a1b2c3d4e12',
];
const _intentionIds = [
  '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f11',
  '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f12',
  '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f13',
  '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f14',
];
const _relationIds = [
  '2a3b4c5d-6e7f-4a80-b91c-0d1e2f3a4b11',
  '2a3b4c5d-6e7f-4a80-b91c-0d1e2f3a4b12',
  '2a3b4c5d-6e7f-4a80-b91c-0d1e2f3a4b13',
];
const _dailyChoiceIds = [
  '3c4d5e6f-7a8b-4c9d-a0e1-1f2a3b4c5d11',
  '3c4d5e6f-7a8b-4c9d-a0e1-1f2a3b4c5d12',
];
const _stepIds = [
  '4d5e6f7a-8b9c-4dae-bf01-2a3b4c5d6e11',
  '4d5e6f7a-8b9c-4dae-bf01-2a3b4c5d6e12',
  '4d5e6f7a-8b9c-4dae-bf01-2a3b4c5d6e13',
];

GraphFormatHeader _expectedGoldenHeader() => GraphFormatHeader(
  writtenAt: DateTime.utc(2026, 10, 3, 18, 42, 7, 654, 321),
  counts: GraphRecordCounts(
    tags: 2,
    intentions: 4,
    tagAssignments: 3,
    longTermRelations: 3,
    dailyChoices: 2,
  ),
);

/// Допустимый сохранённый граф: путь первого дневного выбора проходит через
/// ныне архивированную связь к архивированному намерению, а синий тег «Дом»
/// назначен сначала намерению «Бегать по утрам», затем «Здоровье»; тег
/// «Спорт» без цвета.
List<GraphEntityRecord> _expectedGoldenRecords() {
  final home = _tagId(_tagIds[0]);
  final sport = _tagId(_tagIds[1]);
  final health = _intentionId(_intentionIds[0]);
  final running = _intentionId(_intentionIds[1]);
  final jogging = _intentionId(_intentionIds[2]);
  final swimming = _intentionId(_intentionIds[3]);
  final needRunning = _relationId(_relationIds[0]);
  final needJogging = _relationId(_relationIds[1]);
  final canSwim = _relationId(_relationIds[2]);
  final allDayChoice = _dailyChoiceId(_dailyChoiceIds[0]);
  final midnightChoice = _dailyChoiceId(_dailyChoiceIds[1]);

  return [
    TagRecord(
      Tag(
        id: home,
        name: TagName.fromStored('Дом'),
        color: TagColor.blue,
        position: tagPosition('a1'),
      ),
    ),
    TagRecord(
      Tag(
        id: sport,
        name: TagName.fromStored('Спорт'),
        color: null,
        position: tagPosition('a0V'),
      ),
    ),
    IntentionRecord(
      Intention(
        id: health,
        title: 'Здоровье',
        description: null,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 3, 29)),
        updatedAt: IntentionTimestamp(
          DateTime.utc(2026, 9, 30, 21, 4, 5, 123, 456),
        ),
      ),
    ),
    IntentionRecord(
      Intention(
        id: running,
        title: 'Бегать по утрам 🏃',
        description: '  Первая строка\n\tвторая "строка"  \n',
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.active,
        createdAt: IntentionTimestamp(
          DateTime.utc(2026, 10, 1, 6, 30, 0, 0, 1),
        ),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 10, 2, 7, 0, 0, 500)),
      ),
    ),
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
    IntentionRecord(
      Intention(
        id: swimming,
        title: 'Плавать в бассейне',
        description: null,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.archived,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 10, 1, 6, 31)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 10, 2, 8, 15, 30)),
      ),
    ),
    TagAssignmentRecord(TagAssignment(tagId: home, intentionId: running)),
    TagAssignmentRecord(TagAssignment(tagId: sport, intentionId: jogging)),
    TagAssignmentRecord(TagAssignment(tagId: home, intentionId: health)),
    LongTermRelationRecord(
      id: needRunning,
      sourceIntentionId: health,
      relatedIntentionId: running,
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      description: null,
      scope: RelationScope.active,
    ),
    LongTermRelationRecord(
      id: needJogging,
      sourceIntentionId: health,
      relatedIntentionId: jogging,
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      description: LongTermRelationDescription.fromInput('\n Темп\nлёгкий \n'),
      scope: RelationScope.active,
    ),
    LongTermRelationRecord(
      id: canSwim,
      sourceIntentionId: running,
      relatedIntentionId: swimming,
      type: LongTermRelationType.can,
      priority: RelationPriority.p4,
      description: null,
      scope: RelationScope.archived,
    ),
    DailyChoiceRecord(
      choice: DailyChoice(
        id: allDayChoice,
        sourceIntentionId: health,
        selectedIntentionId: swimming,
        date: CalendarDate.fromParts(2026, 10, 2),
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
          relationId: canSwim,
          previousStepId: _stepId(_stepIds[0]),
        ),
      ]),
    ),
    DailyChoiceRecord(
      choice: DailyChoice(
        id: midnightChoice,
        sourceIntentionId: health,
        selectedIntentionId: jogging,
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
          relationId: needJogging,
          previousStepId: null,
        ),
      ]),
    ),
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
