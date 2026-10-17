import 'dart:convert';
import 'dart:typed_data';

import 'package:doable/src/data/local/app_database.dart'
    show AppDatabase, GraphLogPackagesCompanion;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 17, 12),
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
        CreateTag(TagName.fromInput('Дом')),
      );

      expect(result, isA<GraphResultSuccess<Object?, GraphCommandFailure>>());
      expect(await repository.readCurrentPosition(), 1);
      final [package] = await repository.readPackages(after: 0, upTo: 1);
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
      expect(first.first.facts, _facts('пакет 0'));
      expect(second.last.facts, _facts('пакет ${2 * limit - 1}'));
    },
  );

  test(
    'пакет отдаётся с версией формата из своей строки, а не с текущей',
    () async {
      final storedVersion = GraphFormatVersion.current.number + 1;
      await appendPackages(1, formatVersion: storedVersion);

      final [package] = await repository.readPackages(after: 0, upTo: 1);

      expect(package.formatVersion, storedVersion);
      expect(package.facts, _facts('пакет 0'));
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
          .execute(CreateTag(TagName.fromInput('Дом')))
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

  test('регистрация сохраняет снимок, а поиск выбирает ближайший не новее позиции и последний из одной позиции', () async {
    await appendPackages(9);
    final registered = GraphSnapshotEntry(
      position: 2,
      formatVersion: GraphFormatVersion.current.number,
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
    expect(atTwo?.formatVersion, registered.formatVersion);
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

    final removed = await repository.removeHistoryBefore(6);

    expect(removed, ['снимок-2']);
    expect(await repository.readSnapshotFileNames(), {'снимок-5', 'снимок-8'});
    expect(await readAllPositions(), [6, 7, 8, 9, 10]);
  });

  test('граница раньше первого снимка оставляет все пакеты и только последний снимок', () async {
    await appendPackages(10);
    await registerSnapshotsAt([4, 7, 9]);

    final removed = await repository.removeHistoryBefore(3);

    expect(removed, unorderedEquals(['снимок-4', 'снимок-7']));
    expect(await repository.readSnapshotFileNames(), {'снимок-9'});
    expect(await readAllPositions(), [for (var p = 1; p <= 10; p++) p]);
  });

  test(
    'промежуточные снимки между базовым и последним удаляются вместе с ранними',
    () async {
      await appendPackages(10);
      await registerSnapshotsAt([2, 4, 6, 8, 10]);

      final removed = await repository.removeHistoryBefore(4);

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

    final removed = await repository.removeHistoryBefore(10);

    expect(removed, ['снимок-3']);
    expect(await repository.readSnapshotFileNames(), {'снимок-10'});
    expect(await repository.readCurrentPosition(), 10);
    expect(await readAllPositions(), isEmpty);
  });
}

Uint8List _facts(String text) => utf8.encode('$text\n');

GraphSnapshotEntry _snapshot(int position, {String? fileName}) =>
    GraphSnapshotEntry(
      position: position,
      formatVersion: GraphFormatVersion.current.number,
      fileName: fileName ?? 'снимок-$position',
      byteSize: 1,
      checksum: Uint8List(32),
    );
