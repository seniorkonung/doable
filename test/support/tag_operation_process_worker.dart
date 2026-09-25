import 'dart:async';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_diagnostics_sink.dart';
import 'tag_storage_fixture.dart';

const tagWorkerDatabasePath = 'DOABLE_TAG_DATABASE_PATH';
const tagWorkerOperation = 'DOABLE_TAG_OPERATION';
const tagWorkerStarted = 'DOABLE_TAG_WORKER_STARTED';
const tagWorkerReady = 'DOABLE_TAG_WORKER_READY';
const tagWorkerDone = 'DOABLE_TAG_WORKER_DONE';

void main() {
  test('дочерний процесс выполняет команды тега на файловой базе', () async {
    stdout.writeln('$tagWorkerStarted:$pid');
    await stdout.flush();
    final path = Platform.environment[tagWorkerDatabasePath];
    final operation = Platform.environment[tagWorkerOperation];
    if (path == null || operation == null) {
      throw StateError('Не заданы параметры дочернего процесса тегов.');
    }
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(File(path)),
        _StopBeforeCommit(operation),
      ),
    );
    await database.open();
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(1999, 1, 1),
      InMemoryDiagnosticsSink(),
    );
    final container = ProviderContainer.test(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final firstId =
        (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
    final lastId =
        (TagId.decode(tagFixtureId(lastTagNumber)) as TagIdDecodingSuccess).id;
    try {
      if (operation == 'mutate') {
        await _expectSuccess(
          coordinator.acceptTagRename(
            RenameTag(tagId: firstId, name: TagName.fromInput('Быт')),
          ),
        );
        await _expectSuccess(coordinator.acceptTagDelete(DeleteTag(lastId)));
        final accepted = coordinator.acceptTagCreation(
          TagCreationFormKey(),
          CreateTag(TagName.fromInput('Работа')),
        );
        // Штатное закрытие ждёт уже принятую команду.
        await coordinator.shutdown();
        await _expectSuccess(accepted);
      } else if (operation == 'delete_before_commit' ||
          operation == 'delete_after_commit') {
        await _expectSuccess(coordinator.acceptTagDelete(DeleteTag(firstId)));
        if (operation == 'delete_after_commit') await _reportReadyAndWait();
        await coordinator.shutdown();
      } else {
        throw StateError('Неизвестная операция дочернего процесса.');
      }
    } finally {
      await coordinator.shutdown();
      container.dispose();
      await database.close();
    }
    stdout.writeln(tagWorkerDone);
    await stdout.flush();
  }, timeout: Timeout.none);
}

Future<void> _expectSuccess(TagCommandStart start) async {
  if (start is! TagCommandAccepted) {
    throw StateError('Команда тега не принята.');
  }
  final completion = await start.future;
  if (completion.confirmedResult is! TagCommandSucceeded) {
    throw StateError('Принятая команда тега не подтверждена.');
  }
}

final class _StopBeforeCommit extends LocalDatabaseConnectionObserver {
  _StopBeforeCommit(this.operation);

  final String operation;

  @override
  Future<void> afterStatement(LocalDatabaseSqlStatement statement) async {
    if (operation == 'delete_before_commit' &&
        statement.statements.any(
          (sql) =>
              sql.toUpperCase().contains('DELETE FROM') && sql.contains('tags'),
        )) {
      await _reportReadyAndWait();
    }
  }
}

Future<Never> _reportReadyAndWait() async {
  stdout.writeln('$tagWorkerReady:$pid');
  await stdout.flush();
  await Completer<void>().future;
  throw StateError('Недостижимое завершение ожидания процесса тегов.');
}
