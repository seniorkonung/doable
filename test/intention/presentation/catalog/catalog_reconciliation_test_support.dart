import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
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
  final claim = coordinator.claimInitiator(completion.token);
  if (claim != null) {
    coordinator.confirmPresentation(claim);
  }
  await Future<void>.delayed(Duration.zero);
  return completion;
}
