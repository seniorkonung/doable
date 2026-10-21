import 'dart:convert';
import 'dart:typed_data';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart'
    show AppDatabase, GraphLogPackagesCompanion, GraphSnapshotsCompanion;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_log_completeness_reference.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late DateTime now;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
    now = DateTime.utc(2026, 10, 17, 12);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      InMemoryDiagnosticsSink(),
    );
  });

  tearDown(() => harness.dispose());

  /// Дописывает в лог [count] пакетов «изменение» в обход команд: содержимое
  /// пакета репозиторий не читает, поэтому оно лишь различает пакеты.
  Future<void> appendPackages(int count, {int formatVersion = 1}) async {
    for (var index = 0; index < count; index++) {
      await database
          .into(database.graphLogPackages)
          .insert(
            GraphLogPackagesCompanion.insert(
              recordedAt: 0,
              kind: 'change',
              formatVersion: Value(formatVersion),
              facts: Value(_facts('пакет $index')),
            ),
          );
    }
  }

  Future<T> confirm<T extends GraphCommandOutcome>(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await repository.execute(command);
    final confirmed =
        (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
            as ConfirmedGraphResult;
    return confirmed.value as T;
  }

  Future<Tag> createTag(String name) async => (await confirm<TagCreated>(
    CreateTag(name: TagName.fromInput(name), color: null),
  )).tag;

  /// Все порции записей графа от начала до конца.
  Future<List<GraphRecordPortion>> readAllRecordPortions() async {
    final portions = <GraphRecordPortion>[];
    GraphRecordOrderKey? after;
    do {
      final portion = await repository.readGraphRecords(after: after);
      portions.add(portion);
      after = portion.next;
    } while (after != null);
    return portions;
  }

  Future<void> registerSnapshotsAt(List<int> positions) async {
    for (final position in positions) {
      await repository.registerSnapshot(_snapshot(position));
    }
  }

  /// Позиции всех пакетов лога до текущей позиции, прочитанные порциями.
  Future<List<int>> readAllPositions() async {
    final upTo = await repository.readCurrentPosition();
    final positions = <int>[];
    var next = 0;
    while (true) {
      final portion = await repository.readPackages(after: next, upTo: upTo);
      if (portion.isEmpty) return positions;
      positions.addAll(portion.map((package) => package.position));
      next = portion.last.position;
    }
  }

  test(
    'позиция пустого лога — 0, а после команды — позиция её пакета',
    () async {
      expect(await repository.readCurrentPosition(), 0);

      final result = await repository.execute(
        CreateTag(name: TagName.fromInput('Дом'), color: null),
      );

      expect(result, isA<GraphResultSuccess<Object?, GraphCommandFailure>>());
      expect(await repository.readCurrentPosition(), 1);
      final [package as StoredGraphChangePackage] = await repository
          .readPackages(after: 0, upTo: 1);
      expect(package.position, 1);
      expect(package.formatVersion, GraphFormatVersion.current.number);
    },
  );

  test(
    'пакеты диапазона отдаются ограниченными порциями без пропусков и повторов',
    () async {
      const limit = graphFactLogPortionLimit;
      await appendPackages(2 * limit + 1);

      final first = await repository.readPackages(after: 0, upTo: 2 * limit);
      final second = await repository.readPackages(
        after: first.last.position,
        upTo: 2 * limit,
      );
      final rest = await repository.readPackages(
        after: second.last.position,
        upTo: 2 * limit,
      );

      expect(first.map((package) => package.position), [
        for (var position = 1; position <= limit; position++) position,
      ]);
      expect(second.map((package) => package.position), [
        for (var position = limit + 1; position <= 2 * limit; position++)
          position,
      ]);
      expect(rest, isEmpty);
      expect(
        (first.first as StoredGraphChangePackage).facts,
        _facts('пакет 0'),
      );
      expect(
        (second.last as StoredGraphChangePackage).facts,
        _facts('пакет ${2 * limit - 1}'),
      );
    },
  );

  test(
    'пакет отдаётся с версией формата из своей строки, а не с текущей',
    () async {
      final storedVersion = GraphFormatVersion.current.number + 1;
      await appendPackages(1, formatVersion: storedVersion);

      final [package as StoredGraphChangePackage] = await repository
          .readPackages(after: 0, upTo: 1);

      expect(package.formatVersion, storedVersion);
      expect(package.facts, _facts('пакет 0'));
    },
  );

  test(
    'пакет «сброс» отдаётся между пакетами «изменение» отдельным вариантом со '
    'своей позицией',
    () async {
      await appendPackages(1);
      final snapshot = _snapshot(2);
      // Схема требует от пакета «сброс» ссылку на зарегистрированный снимок.
      final snapshotId = await database
          .into(database.graphSnapshots)
          .insert(
            GraphSnapshotsCompanion.insert(
              position: snapshot.position,
              fileName: snapshot.fileName,
              byteSize: snapshot.byteSize,
              checksum: snapshot.checksum,
            ),
          );
      await database
          .into(database.graphLogPackages)
          .insert(
            GraphLogPackagesCompanion.insert(
              recordedAt: 0,
              kind: 'reset',
              snapshotId: Value(snapshotId),
            ),
          );
      await appendPackages(1);

      final [before, reset as StoredGraphResetPackage, after] = await repository
          .readPackages(after: 0, upTo: 3);

      expect(
        before,
        isA<StoredGraphChangePackage>()
            .having((package) => package.position, 'position', 1)
            .having((package) => package.facts, 'facts', _facts('пакет 0')),
      );
      expect(reset.position, 2);
      expect(
        after,
        isA<StoredGraphChangePackage>().having(
          (package) => package.position,
          'position',
          3,
        ),
      );
    },
  );

  test(
    'команда, отправленная между порциями, подтверждается до следующей порции',
    () async {
      const limit = graphFactLogPortionLimit;
      await appendPackages(limit + 1);
      const upTo = limit + 1;
      final completions = <String>[];

      final first = await repository.readPackages(after: 0, upTo: upTo);
      final command = repository
          .execute(CreateTag(name: TagName.fromInput('Дом'), color: null))
          .whenComplete(() => completions.add('команда'));
      final second = repository
          .readPackages(after: first.last.position, upTo: upTo)
          .whenComplete(() => completions.add('следующая порция'));
      await Future.wait([command, second]);

      expect(completions, ['команда', 'следующая порция']);
      expect(await repository.readCurrentPosition(), upTo + 1);
      expect((await second).map((package) => package.position), [upTo]);
    },
  );

  test('записи графа отдаются полными порциями в каноническом порядке с '
      'границами внутри каждой секции и группы намерений с одним временем '
      'создания', () async {
    // По 100 записей в порции границы приходятся на середину секции тегов,
    // намерений, назначений, связей и дневных выборов. После 149 тегов
    // граница в секции намерений проходит внутри пары с одним временем
    // создания.
    expect(graphFactLogPortionLimit, 100);
    final tags = [
      for (var index = 0; index < 149; index++) await createTag('Тег $index'),
    ];
    final root = (await confirm<IntentionSaved>(
      CreateIntention.withInitialState(
        title: 'Корень',
        description: null,
        readiness: IntentionReadiness.notReady,
        tagIds: const {},
      ),
    )).intention;
    final clockStart = now;
    final related = <Intention>[];
    for (var index = 0; index < 100; index++) {
      // Часы идут назад, и пары намерений получают одно время создания:
      // порядок по времени создания и идентификатору расходится с порядком
      // создания.
      now = clockStart.subtract(Duration(seconds: index ~/ 2 + 1));
      related.add(
        (await confirm<IntentionSaved>(
          CreateIntention.withInitialState(
            title: 'Намерение $index',
            description: null,
            readiness: IntentionReadiness.ready,
            tagIds: {tags[index].id},
          ),
        )).intention,
      );
    }
    for (final intention in related) {
      final relation = (await confirm<LongTermRelationCreated>(
        CreateLongTermRelation(
          sourceIntentionId: root.id,
          relatedIntentionId: intention.id,
          type: LongTermRelationType.need,
          priority: RelationPriority.p2,
          description: null,
        ),
      )).relation;
      await confirm(
        CreateDailyChoice(
          sourceIntentionId: root.id,
          selectedIntentionId: intention.id,
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: relation.id,
              sourceIntentionId: root.id,
              type: relation.type,
              relatedIntentionId: intention.id,
            ),
          ]),
          date: CalendarDate.fromParts(2026, 10, 17),
          description: null,
          isCompleted: false,
        ),
      );
    }

    final portions = await readAllRecordPortions();

    expect(portions.map((portion) => portion.records.length), [
      100,
      100,
      100,
      100,
      100,
      50,
    ]);
    final beforeBoundary =
        (portions[1].records.last as IntentionRecord).intention;
    final afterBoundary =
        (portions[2].records.first as IntentionRecord).intention;
    expect(afterBoundary.createdAt, beforeBoundary.createdAt);
    expect(
      portions.map((portion) => portion.position),
      everyElement(await repository.readCurrentPosition()),
    );
    expect(
      _lines(portions.expand((portion) => portion.records)),
      _lines(await referenceGraphRecords(database)),
    );
  });

  test('порция записей переносит цвет тега и его отсутствие', () async {
    final colored = await createTag('Дом');
    await createTag('Работа');
    await seedGraph(
      database,
      () => database.customStatement(
        "UPDATE tags SET color = 'blue' WHERE id = ?",
        [colored.id.toCanonicalString()],
      ),
    );

    final portion = await repository.readGraphRecords();

    expect(
      [for (final record in portion.records) (record as TagRecord).tag.color],
      [TagColor.blue, null],
    );
  });

  test('команда, отправленная между порциями записей, подтверждается до '
      'следующей порции и попадает в неё', () async {
    for (var index = 0; index <= graphFactLogPortionLimit; index++) {
      await createTag('Тег $index');
    }
    final completions = <String>[];

    final first = await repository.readGraphRecords();
    final command = repository
        .execute(CreateTag(name: TagName.fromInput('Новый'), color: null))
        .whenComplete(() => completions.add('команда'));
    final second = repository
        .readGraphRecords(after: first.next)
        .whenComplete(() => completions.add('следующая порция'));
    await Future.wait([command, second]);

    expect(completions, ['команда', 'следующая порция']);
    final rest = await second;
    expect(rest.position, first.position + 1);
    expect(
      [for (final record in rest.records) (record as TagRecord).tag.name.value],
      ['Тег $graphFactLogPortionLimit', 'Новый'],
    );
    expect(rest.next, isNull);
  });

  test('регистрация сохраняет снимок, а поиск выбирает ближайший не новее позиции и последний из одной позиции', () async {
    await appendPackages(9);
    final registered = GraphSnapshotEntry(
      position: 2,
      fileName: 'снимок-2',
      byteSize: 4096,
      checksum: Uint8List.fromList(List.generate(32, (index) => index)),
    );
    await repository.registerSnapshot(registered);
    await repository.registerSnapshot(_snapshot(5, fileName: 'снимок-5-а'));
    await repository.registerSnapshot(_snapshot(5, fileName: 'снимок-5-б'));

    final atTwo = await repository.readSnapshotAtOrBefore(2);

    expect(await repository.readSnapshotAtOrBefore(1), isNull);
    expect(atTwo?.position, registered.position);
    expect(atTwo?.fileName, registered.fileName);
    expect(atTwo?.byteSize, registered.byteSize);
    expect(atTwo?.checksum, registered.checksum);
    expect((await repository.readSnapshotAtOrBefore(4))?.fileName, 'снимок-2');
    expect(
      (await repository.readSnapshotAtOrBefore(5))?.fileName,
      'снимок-5-б',
    );
    expect(
      (await repository.readSnapshotAtOrBefore(9))?.fileName,
      'снимок-5-б',
    );
    expect(await repository.readSnapshotFileNames(), {
      'снимок-2',
      'снимок-5-а',
      'снимок-5-б',
    });
  });

  test('граница посередине лога оставляет ближайший к ней снимок, последний снимок и пакеты после ближайшего', () async {
    await appendPackages(10);
    await registerSnapshotsAt([2, 5, 8]);

    final removed = await repository.removeHistoryBefore(6, retained: const []);

    expect(removed, ['снимок-2']);
    expect(await repository.readSnapshotFileNames(), {'снимок-5', 'снимок-8'});
    expect(await readAllPositions(), [6, 7, 8, 9, 10]);
  });

  test('граница раньше первого снимка оставляет все пакеты и только последний снимок', () async {
    await appendPackages(10);
    await registerSnapshotsAt([4, 7, 9]);

    final removed = await repository.removeHistoryBefore(3, retained: const []);

    expect(removed, unorderedEquals(['снимок-4', 'снимок-7']));
    expect(await repository.readSnapshotFileNames(), {'снимок-9'});
    expect(await readAllPositions(), [for (var p = 1; p <= 10; p++) p]);
  });

  test(
    'промежуточные снимки между базовым и последним удаляются вместе с ранними',
    () async {
      await appendPackages(10);
      await registerSnapshotsAt([2, 4, 6, 8, 10]);

      final removed = await repository.removeHistoryBefore(
        4,
        retained: const [],
      );

      expect(removed, unorderedEquals(['снимок-2', 'снимок-6', 'снимок-8']));
      expect(await repository.readSnapshotFileNames(), {
        'снимок-4',
        'снимок-10',
      });
      expect(await readAllPositions(), [5, 6, 7, 8, 9, 10]);
    },
  );

  test('граница на последнем снимке оставляет только его и не уменьшает текущую позицию', () async {
    await appendPackages(10);
    await registerSnapshotsAt([3, 10]);

    final removed = await repository.removeHistoryBefore(
      10,
      retained: const [],
    );

    expect(removed, ['снимок-3']);
    expect(await repository.readSnapshotFileNames(), {'снимок-10'});
    expect(await repository.readCurrentPosition(), 10);
    expect(await readAllPositions(), isEmpty);
  });
}

Uint8List _facts(String text) => utf8.encode('$text\n');

List<String> _lines(Iterable<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];

GraphSnapshotEntry _snapshot(int position, {String? fileName}) =>
    GraphSnapshotEntry(
      position: position,
      fileName: fileName ?? 'снимок-$position',
      byteSize: 1,
      checksum: Uint8List(32),
    );
