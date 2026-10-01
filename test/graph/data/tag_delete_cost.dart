import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

final class _DeleteCostProbe extends LocalDatabaseConnectionObserver {
  _DeleteCostProbe(this.file);

  final File file;
  final statements = <LocalDatabaseSqlStatement>[];
  final selectRows = <int>[];
  int? assignmentsVisibleBeforeCommit;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    statements.add(statement);
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    selectRows.add(rows.length);
    return rows;
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.delete ||
        !statement.statements.single.contains('tags')) {
      return;
    }
    final reader = sqlite.sqlite3.open(file.path);
    try {
      assignmentsVisibleBeforeCommit =
          reader.select(
                'SELECT COUNT(*) AS total FROM tag_assignments WHERE tag_id = ?',
                [tagFixtureId(9000)],
              ).single['total']
              as int;
    } finally {
      reader.close();
    }
  }
}

Future<void> measureWidelyAssignedTagDeletion() async {
  const recipients = 2400;
  final durations = <int>[];
  List<String>? observedSql;
  List<int>? observedRows;
  int? sqliteBytes;
  String? sqliteVersion;
  for (var repetition = 0; repetition < 5; repetition++) {
    final directory = await Directory.systemTemp.createTemp(
      'doable_tag_delete_cost_',
    );
    final file = File('${directory.path}/delete.sqlite');
    final probe = _DeleteCostProbe(file);
    late sqlite.Database raw;
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(
          file,
          setup: (connection) => raw = connection,
        ),
        probe,
      ),
    );
    try {
      await database.open();
      seedWidelyAssignedTagFixture(raw, recipients: recipients);
      final repository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 27),
        InMemoryDiagnosticsSink(),
      );
      expect(
        raw.select('SELECT COUNT(*) FROM tag_assignments').single.values.single,
        recipients * 2 + 1,
      );
      probe.statements.clear();
      probe.selectRows.clear();
      final timer = Stopwatch()..start();
      final result = await repository.execute(DeleteTag(_tagId(9000)));
      timer.stop();
      expect(result, isA<TagCommandSucceeded>());
      final confirmed = (result as TagCommandSucceeded).value;
      expect(confirmed.value, isA<TagDeleted>());
      expect(confirmed.value.changes, hasLength(1));
      expect(confirmed.value.changes.single, isA<TagDeletedChange>());
      expect(probe.assignmentsVisibleBeforeCommit, recipients);
      // Назначения сохраняемого тега тем же получателям не затронуты.
      expect(
        raw
            .select(
              'SELECT tag_id, COUNT(*) FROM tag_assignments GROUP BY tag_id',
            )
            .map((row) => row.values.toList()),
        [
          [tagFixtureId(9001), recipients + 1],
        ],
      );
      expect(raw.select('SELECT COUNT(*) FROM tags').single.values.single, 1);
      expect(
        raw.select('SELECT COUNT(*) FROM intentions').single.values.single,
        recipients + 1,
      );
      expect(
        raw
            .select('SELECT COUNT(*) FROM long_term_relations')
            .single
            .values
            .single,
        recipients,
      );
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      final sql = [
        for (final statement in probe.statements) ...statement.statements,
      ];
      expect(
        probe.statements.where(
          (statement) =>
              statement.operation == LocalDatabaseSqlOperation.delete,
        ),
        hasLength(1),
      );
      expect(
        sql.where((statement) => statement.contains('tag_assignments')),
        isEmpty,
      );
      expect(
        sql.where((statement) => statement.toUpperCase().contains('OFFSET')),
        isEmpty,
      );
      expect(
        sql.where((statement) => statement.toUpperCase().contains('COUNT(')),
        isEmpty,
      );
      expect(probe.selectRows, [1]);
      durations.add(timer.elapsedMicroseconds);
      observedSql ??= sql;
      observedRows ??= List<int>.of(probe.selectRows);
      final pageCount =
          raw.select('PRAGMA page_count').single.values.single as int;
      final pageSize =
          raw.select('PRAGMA page_size').single.values.single as int;
      sqliteBytes ??= pageCount * pageSize;
      sqliteVersion ??=
          raw.select('SELECT sqlite_version()').single.values.single as String;
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  }
  debugPrintSynchronously(
    jsonEncode({
      'kind': 'widely_assigned_tag_delete',
      'recipients': recipients,
      'activeIntentionRecipients': recipients ~/ 2,
      'archivedIntentionRecipients': recipients ~/ 2,
      'deletedAssignments': recipients,
      'retainedAssignments': recipients + 1,
      'repetitions': durations.length,
      'elapsedMicroseconds': durations,
      'statements': observedSql,
      'materializedRowsPerSelect': observedRows,
      'sqliteBytes': sqliteBytes,
      'sqliteVersion': sqliteVersion,
      'platform': Platform.operatingSystem,
      'buildMode': const bool.fromEnvironment('dart.vm.profile')
          ? 'profile'
          : const bool.fromEnvironment('dart.vm.product')
          ? 'release'
          : 'debug',
    }),
  );
}
