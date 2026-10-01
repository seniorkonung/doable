import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_support.dart';

ProviderContainer reconciliationCatalogContainer(
  ControlledCatalogRepository repository, {
  Duration filterDebounce = const Duration(milliseconds: 250),
  int pageSize = 100,
  int prefetchRemaining = 30,
}) => ProviderContainer(
  overrides: [
    personalGraphRepositoryProvider.overrideWithValue(repository),
    catalogPagingPolicyProvider.overrideWithValue(
      CatalogPagingPolicy(
        pageSize: pageSize,
        prefetchRemaining: prefetchRemaining,
        filterDebounce: filterDebounce,
      ),
    ),
  ],
  retry: (retryCount, error) => null,
);

Future<void> waitForCatalogQueries(
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (repository.queries.length >= count) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Не дождались $count запросов каталога.');
}

Future<void> waitForReconciliationQueries(
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (repository.reconciliationQueries.length >= count) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Не дождались $count чтений согласования каталога.');
}

Future<IntentionCommandCompletion> completeCatalogCommand(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  IntentionCommand command,
  IntentionCommandSuccess success,
) async {
  final coordinator = container.read(graphCommandCoordinatorProvider.notifier);
  final commandIndex = repository.commands.length;
  final start = switch (command) {
    CreateIntention() => coordinator.acceptCreation(
      IntentionCreationFormKey(),
      command,
    ),
    ExistingIntentionCommand() => coordinator.acceptExisting(
      command,
      presentationTitle: 'Намерение',
    ),
  };
  expect(start, isA<IntentionCommandAccepted>());
  final accepted = start as IntentionCommandAccepted;
  repository.completeCommand(commandIndex, ResultSuccess(success));
  final completion = await accepted.future;
  await Future<void>.delayed(Duration.zero);
  return completion;
}

/// Проводит команду связи через coordinator до опубликованного завершения.
///
/// Ревизия задаётся явно: пакет подтверждённого изменения связи содержит
/// только изменения графа без каталожной мутации.
Future<LongTermRelationCommandCompletion> completeRelationCommand(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  LongTermRelationCommand command,
  LongTermRelationCommandResult result,
) async {
  final coordinator = container.read(graphCommandCoordinatorProvider.notifier);
  final commandIndex = repository.relationCommands.length;
  final start = switch (command) {
    CreateLongTermRelation() => coordinator.acceptRelationCreation(
      LongTermRelationCreationFormKey(),
      command,
    ),
    UpdateLongTermRelation() => coordinator.acceptRelationUpdate(command),
    ArchiveLongTermRelation() => coordinator.acceptRelationArchive(command),
    RestoreLongTermRelation() => coordinator.acceptRelationRestore(command),
    DeleteLongTermRelation() => coordinator.acceptRelationDelete(command),
  };
  expect(start, isA<LongTermRelationCommandAccepted>());
  final accepted = start as LongTermRelationCommandAccepted;
  repository.completeRelationCommand(commandIndex, result);
  final completion = await accepted.future;
  await Future<void>.delayed(Duration.zero);
  return completion;
}

/// Собирает успешный результат создания связи с абсолютными количествами.
LongTermRelationCommandResult relationCreationSuccess({
  required GraphRevision revision,
  required LongTermRelationCreated success,
}) =>
    GraphCommandSucceeded<
      LongTermRelationCommandSuccess,
      LongTermRelationCommandFailure
    >(ConfirmedGraphResult(revision: revision, value: success));

/// Принимает команду тега через coordinator и подтверждает её в репозитории.
///
/// Завершение команды публикуется асинхронно: вызывающий код сам ждёт его
/// обычным ожиданием либо кадрами виджет-теста.
TagCommandAccepted acceptTagCommand(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  TagCommand command,
  TagCommandResult result,
) {
  final coordinator = container.read(graphCommandCoordinatorProvider.notifier);
  final commandIndex = repository.tagCommands.length;
  final start = switch (command) {
    AssignTag() => coordinator.acceptTagAssign(command),
    RemoveTagAssignment() => coordinator.acceptTagRemoveAssignment(command),
    CreateTag() => coordinator.acceptTagCreation(TagCreationFormKey(), command),
    RenameTag() => coordinator.acceptTagRename(command),
    DeleteTag() => coordinator.acceptTagDelete(command),
  };
  expect(start, isA<TagCommandAccepted>());
  final accepted = start as TagCommandAccepted;
  repository.completeTagCommand(commandIndex, result);
  return accepted;
}

/// Проводит команду тега через coordinator до опубликованного завершения.
Future<TagCommandCompletion> completeTagCommand(
  ProviderContainer container,
  ControlledCatalogRepository repository,
  TagCommand command,
  TagCommandResult result,
) async {
  final accepted = acceptTagCommand(container, repository, command, result);
  final completion = await accepted.future;
  await Future<void>.delayed(Duration.zero);
  return completion;
}

/// Проводит назначение или снятие тега намерению с пакетом реальной команды.
///
/// Пакет несёт компактный факт пары и каталожную мутацию с полными
/// краткими снимками намерения до и после операции на одной ревизии.
Future<TagCommandCompletion> completeIntentionTagAssignment(
  ProviderContainer container,
  ControlledCatalogRepository repository, {
  required TagAssignmentState state,
  required TagId tagId,
  required IntentionSummary before,
  required IntentionSummary after,
  required GraphRevision revision,
}) {
  final (command, result) = intentionTagAssignment(
    state: state,
    tagId: tagId,
    before: before,
    after: after,
    revision: revision,
  );
  return completeTagCommand(container, repository, command, result);
}

/// Собирает команду назначения или снятия тега намерению и её подтверждение.
///
/// Подтверждение повторяет пакет реальной команды: компактный факт пары и
/// каталожную мутацию с полными краткими снимками на одной ревизии.
(TagCommand, TagCommandResult) intentionTagAssignment({
  required TagAssignmentState state,
  required TagId tagId,
  required IntentionSummary before,
  required IntentionSummary after,
  required GraphRevision revision,
}) {
  final assignment = TagAssignment(tagId: tagId, intentionId: after.id);
  return (
    switch (state) {
      TagAssignmentState.assigned => AssignTag(
        tagId: tagId,
        intentionId: after.id,
      ),
      TagAssignmentState.absent => RemoveTagAssignment(
        tagId: tagId,
        intentionId: after.id,
      ),
    },
    TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: revision,
        value: TagAssignmentChanged(
          TagAssignmentChangedChange(
            revision: revision,
            assignment: assignment,
            state: state,
          ),
          catalogMutation: IntentionCatalogUpdated(
            revision: revision,
            before: TestCatalogEntrySnapshot(before),
            after: TestCatalogEntrySnapshot(after),
          ),
        ),
      ),
    ),
  );
}

/// Собирает подтверждение физического удаления тега с компактным фактом.
TagCommandResult tagDeletionSuccess({
  required TagId tagId,
  required GraphRevision revision,
}) => TagCommandSucceeded(
  ConfirmedGraphResult(
    revision: revision,
    value: TagDeleted(TagDeletedChange(revision: revision, tagId: tagId)),
  ),
);

/// Первая успешная порция чтения согласования с абсолютным количеством.
Result<IntentionCatalogReconciliationOutcome> reconciliationFirstPortion(
  List<IntentionSummary> items, {
  required int totalCount,
  IntentionCatalogReconciliationCursor? nextCursor,
  required int revision,
}) => ResultSuccess(
  IntentionCatalogReconciliationFirstPortion(
    items: items,
    totalCount: totalCount,
    nextCursor: nextCursor,
    revision: TestCatalogRevision(revision),
  ),
);

/// Последующая успешная порция чтения согласования той же ревизии.
Result<IntentionCatalogReconciliationOutcome> reconciliationContinuationPortion(
  List<IntentionSummary> items, {
  IntentionCatalogReconciliationCursor? nextCursor,
  required int revision,
}) => ResultSuccess(
  IntentionCatalogReconciliationContinuationPortion(
    items: items,
    nextCursor: nextCursor,
    revision: TestCatalogRevision(revision),
  ),
);
