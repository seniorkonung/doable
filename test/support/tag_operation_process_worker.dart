import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_id_generator.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
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
const tagWorkerLocale = 'DOABLE_TAG_LOCALE';
const tagWorkerClockYear = 'DOABLE_TAG_CLOCK_YEAR';

void main() {
  test('дочерний процесс выполняет команды тега на файловой базе', () async {
    stdout.writeln('$tagWorkerStarted:$pid');
    await stdout.flush();
    final path = Platform.environment[tagWorkerDatabasePath];
    final operation = Platform.environment[tagWorkerOperation];
    if (path == null || operation == null) {
      throw StateError('Не заданы параметры дочернего процесса тегов.');
    }
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.localeTestValue = Locale(
      Platform.environment[tagWorkerLocale] ?? 'ru',
    );
    addTearDown(binding.platformDispatcher.clearLocaleTestValue);
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
      () => DateTime.utc(
        int.parse(Platform.environment[tagWorkerClockYear] ?? '1999'),
      ),
      InMemoryDiagnosticsSink(),
      tagIdGenerator: switch (operation) {
        'assignments_mutate' => _FixtureTagIdGenerator(),
        _ => null,
      },
    );
    final container = ProviderContainer.test(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    try {
      if (operation == 'assignments_mutate') {
        await _mutateAssignments(coordinator);
      } else if (operation == 'assignment_before_commit_verify' ||
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
            AssignTag(tagId: _tag(303), intentionId: _intention(2)),
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

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

Future<void> _mutateAssignments(GraphCommandCoordinator coordinator) async {
  for (final (number, name) in [
    (301, 'Дом'),
    (302, 'Временный'),
    (303, 'Работа'),
  ]) {
    final created = await _expectSuccess(
      coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(name: TagName.fromInput(name), color: null),
      ),
    );
    expect((created as TagCreated).tag.id, _tag(number));
  }
  await _expectSuccess(
    coordinator.acceptTagUpdate(
      UpdateTag(tagId: _tag(301), name: TagName.fromInput('Быт'), color: null),
    ),
  );

  for (final (number, target) in <(int, IntentionId)>[
    (301, _intention(1)),
    (303, _intention(1)),
    (301, _intention(2)),
    (302, _intention(3)),
    (301, _intention(4)),
  ]) {
    await _expectSuccess(
      coordinator.acceptTagAssign(
        AssignTag(tagId: _tag(number), intentionId: target),
      ),
    );
  }
  await _expectSuccess(
    coordinator.acceptTagRemoveAssignment(
      RemoveTagAssignment(tagId: _tag(301), intentionId: _intention(1)),
    ),
  );
  await _expectSuccess(
    coordinator.acceptTagRemoveAssignment(
      RemoveTagAssignment(tagId: _tag(301), intentionId: _intention(2)),
    ),
  );
  await _expectSuccess(coordinator.acceptTagDelete(DeleteTag(_tag(302))));

  final relationDelete = coordinator.acceptRelationDelete(
    DeleteLongTermRelation(_relation(103)),
  );
  if (relationDelete is! LongTermRelationCommandAccepted ||
      (await relationDelete.future).isFailure) {
    throw StateError('Удаление долговременной связи не подтверждено.');
  }
  final intentionDelete = coordinator.acceptExisting(
    DeleteIntention(_intention(4)),
    presentationTitle: 'Удаляемое намерение',
  );
  if (intentionDelete is! IntentionCommandAccepted ||
      (await intentionDelete.future).isFailure) {
    throw StateError('Удаление намерения не подтверждено.');
  }

  final accepted = coordinator.acceptTagAssign(
    AssignTag(tagId: _tag(301), intentionId: _intention(1)),
  );
  await coordinator.shutdown();
  await _expectSuccess(accepted);
}

Future<void> _verifyAssignments(
  AppDatabase database,
  DriftPersonalGraphRepository repository, {
  required bool secondIntentionAssigned,
}) async {
  final catalog = (await repository.getTagCatalog(
    const TagCatalogBrowseMode(),
  ) as TagCatalogSuccess).value;
  // Каждый новый тег встаёт первым, поэтому созданный позже «Работа» стоит
  // перед «Быт».
  expect(catalog.items.map((tag) => (tag.id, tag.name.value)).toList(), [
    (_tag(303), 'Работа'),
    (_tag(301), 'Быт'),
  ]);
  for (final target in <IntentionId>[_intention(1)]) {
    final snapshot = (await repository.getTagAssignments(
      target,
    ) as TagAssignmentsSuccess).value;
    expect(snapshot.intentionId, target);
    expect(snapshot.items.map((tag) => (tag.id, tag.name.value)), [
      (_tag(303), 'Работа'),
      (_tag(301), 'Быт'),
    ]);
  }
  final secondPage = (await repository.getTagAssignments(
    _intention(2),
  ) as TagAssignmentsSuccess).value;
  expect(
    secondPage.items.map((tag) => tag.id).toList(),
    secondIntentionAssigned ? [_tag(303)] : isEmpty,
  );
  final rows = await database.customSelect('PRAGMA foreign_key_check').get();
  expect(rows, isEmpty);
  await _expectNavigation(
    repository,
    _tag(301),
    'Быт',
    active: [_intention(1)],
    archived: [],
  );
  await _expectNavigation(
    repository,
    _tag(303),
    'Работа',
    active: [_intention(1)],
    archived: secondIntentionAssigned ? [_intention(2)] : [],
  );
}

Future<void> _expectNavigation(
  DriftPersonalGraphRepository repository,
  TagId tagId,
  String name, {
  required List<IntentionId> active,
  required List<IntentionId> archived,
}) async {
  final locale = TestWidgetsFlutterBinding.instance.platformDispatcher.locale;
  final l10n = await AppLocalizations.delegate.load(locale);
  expect(l10n.localeName, locale.languageCode);
  for (final (scope, expected) in [
    (TaggedIntentionsScope.active, active),
    (TaggedIntentionsScope.archived, archived),
  ]) {
    for (final pageSize in [1, 2, 50, 100]) {
      final targets = <IntentionId>[];
      TaggedIntentionsCursor? cursor;
      GraphRevision? revision;
      do {
        final result = await repository.getTaggedIntentionsPage(
          TaggedIntentionsQuery(
            tagId: tagId,
            scope: scope,
            pageSize: pageSize,
            cursor: cursor,
          ),
        );
        expect(result, isA<TaggedIntentionsPageSuccess>());
        final page = (result as TaggedIntentionsPageSuccess).value;
        expect(page.tag.id, tagId);
        expect(page.tag.name.value, name);
        expect(l10n.tagNavigationTag(page.tag.name.value), contains(name));
        expect(page.scope, scope);
        expect(page.items.length, lessThanOrEqualTo(pageSize));
        expect(
          revision?.compareTo(page.revision) ?? GraphRevisionOrder.same,
          GraphRevisionOrder.same,
        );
        revision = page.revision;
        targets.addAll(page.items.map((item) => item.id));
        expect(targets.toSet(), hasLength(targets.length));
        expect(targets.length, lessThanOrEqualTo(expected.length));
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(targets, expected, reason: '$scope, порция $pageSize');
    }
  }
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
    if (operation == 'assignment_before_commit' &&
        statement.operation == LocalDatabaseSqlOperation.insert &&
        statement.statements.any((sql) => sql.contains('tag_assignments'))) {
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
