import 'dart:async';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_id_generator.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
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
      tagIdGenerator: operation == 'assignments_mutate'
          ? _FixtureTagIdGenerator()
          : null,
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
      } else if (operation == 'assignments_mutate') {
        await _mutateAssignments(coordinator);
      } else if (operation == 'assignments_verify' ||
          operation == 'assignment_before_commit_verify' ||
          operation == 'assignment_after_commit_verify') {
        await _verifyAssignments(
          database,
          repository,
          secondIntentionAssigned:
              operation == 'assignment_after_commit_verify',
        );
      } else if (operation == 'assignment_before_commit' ||
          operation == 'assignment_after_commit') {
        await _expectSuccess(
          coordinator.acceptTagAssign(
            AssignTag(tagId: _tag(303), target: _intention(2)),
          ),
        );
        if (operation == 'assignment_after_commit') await _reportReadyAndWait();
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

Future<TagCommandSuccess> _expectSuccess(TagCommandStart start) async {
  if (start is! TagCommandAccepted) {
    throw StateError('Команда тега не принята.');
  }
  final completion = await start.future;
  if (completion.confirmedResult is! TagCommandSucceeded) {
    throw StateError('Принятая команда тега не подтверждена.');
  }
  return (completion.confirmedResult as TagCommandSucceeded).value.value;
}

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionTagTarget _intention(int number) => IntentionTagTarget(
  (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id,
);

LongTermRelationTagTarget _relation(int number) => LongTermRelationTagTarget(
  (LongTermRelationId.decode(
    tagFixtureId(number),
  ) as LongTermRelationIdDecodingSuccess).id,
);

Future<void> _mutateAssignments(GraphCommandCoordinator coordinator) async {
  for (final (number, name) in [
    (301, 'Дом'),
    (302, 'Временный'),
    (303, 'Работа'),
  ]) {
    final created = await _expectSuccess(
      coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(TagName.fromInput(name)),
      ),
    );
    expect((created as TagCreated).tag.id, _tag(number));
  }
  await _expectSuccess(
    coordinator.acceptTagRename(
      RenameTag(tagId: _tag(301), name: TagName.fromInput('Быт')),
    ),
  );

  for (final (number, target) in <(int, TagTarget)>[
    (301, _intention(1)),
    (303, _intention(1)),
    (301, _intention(2)),
    (301, _relation(101)),
    (303, _relation(101)),
    (301, _relation(102)),
    (302, _intention(3)),
    (302, _relation(102)),
    (301, _intention(4)),
    (303, _relation(103)),
  ]) {
    await _expectSuccess(
      coordinator.acceptTagAssign(
        AssignTag(tagId: _tag(number), target: target),
      ),
    );
  }
  await _expectSuccess(
    coordinator.acceptTagRemoveAssignment(
      RemoveTagAssignment(tagId: _tag(301), target: _intention(1)),
    ),
  );
  await _expectSuccess(
    coordinator.acceptTagRemoveAssignment(
      RemoveTagAssignment(tagId: _tag(301), target: _intention(2)),
    ),
  );
  await _expectSuccess(coordinator.acceptTagDelete(DeleteTag(_tag(302))));

  final relationDelete = coordinator.acceptRelationDelete(
    DeleteLongTermRelation(_relation(103).relationId),
  );
  if (relationDelete is! LongTermRelationCommandAccepted ||
      (await relationDelete.future).isFailure) {
    throw StateError('Удаление долговременной связи не подтверждено.');
  }
  final intentionDelete = coordinator.acceptExisting(
    DeleteIntention(_intention(4).intentionId),
    presentationTitle: 'Удаляемое намерение',
  );
  if (intentionDelete is! IntentionCommandAccepted ||
      (await intentionDelete.future).isFailure) {
    throw StateError('Удаление намерения не подтверждено.');
  }

  final accepted = coordinator.acceptTagAssign(
    AssignTag(tagId: _tag(301), target: _intention(1)),
  );
  await coordinator.shutdown();
  await _expectSuccess(accepted);
}

Future<void> _verifyAssignments(
  AppDatabase database,
  DriftPersonalGraphRepository repository, {
  required bool secondIntentionAssigned,
}) async {
  final catalog = (await repository.getTagCatalogPage(
    TagCatalogQuery(),
  ) as TagCatalogPageSuccess).value;
  expect(catalog.items.map((tag) => (tag.id, tag.name.value)).toList(), [
    (_tag(301), 'Быт'),
    (_tag(303), 'Работа'),
  ]);
  for (final target in <TagTarget>[_intention(1), _relation(101)]) {
    final page = (await repository.getTagAssignmentsPage(
      TagAssignmentsQuery(target: target, pageSize: 1),
    ) as TagAssignmentsPageSuccess).value;
    expect(page.items.single.id, _tag(301));
    expect(page.items.single.name.value, 'Быт');
    final next = (await repository.getTagAssignmentsPage(
      TagAssignmentsQuery(target: target, pageSize: 1, cursor: page.nextCursor),
    ) as TagAssignmentsPageSuccess).value;
    expect(next.items.single.id, _tag(303));
    expect(next.items.single.name.value, 'Работа');
    expect(next.nextCursor, isNull);
  }
  final secondPage = (await repository.getTagAssignmentsPage(
    TagAssignmentsQuery(target: _intention(2)),
  ) as TagAssignmentsPageSuccess).value;
  expect(
    secondPage.items.map((tag) => tag.id).toList(),
    secondIntentionAssigned ? [_tag(303)] : isEmpty,
  );
  final rows = await database.customSelect('PRAGMA foreign_key_check').get();
  expect(rows, isEmpty);
}

final class _FixtureTagIdGenerator implements TagIdGenerator {
  var _next = 301;

  @override
  TagId generate() => _tag(_next++);
}

final class _StopBeforeCommit extends LocalDatabaseConnectionObserver {
  _StopBeforeCommit(this.operation);

  final String operation;

  @override
  Future<void> afterStatement(LocalDatabaseSqlStatement statement) async {
    if ((operation == 'delete_before_commit' &&
            statement.statements.any(
              (sql) =>
                  sql.toUpperCase().contains('DELETE FROM') &&
                  sql.contains('tags'),
            )) ||
        (operation == 'assignment_before_commit' &&
            statement.operation == LocalDatabaseSqlOperation.insert &&
            statement.statements.any(
              (sql) => sql.contains('tag_assignments'),
            ))) {
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
