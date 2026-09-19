import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
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
  CreateLongTermRelation command,
  LongTermRelationCommandResult result,
) async {
  final coordinator = container.read(graphCommandCoordinatorProvider.notifier);
  final commandIndex = repository.relationCommands.length;
  final start = coordinator.acceptRelationCreation(
    LongTermRelationCreationFormKey(),
    command,
  );
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
