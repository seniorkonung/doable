import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_picker_context.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show testSummary;
import '../../../long_term_relation/presentation/participant_picker/participant_picker_test_support.dart';
import '../../../support/app_root_pages.dart';
import '../daily_choice_picker_tag_search_test_support.dart';
import '../daily_choice_picker_context_test_support.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  defineDailyChoicePickerContextTests(
    route: (pickerContext) =>
        DailyChoiceActionPickerRoute(pickerContext: pickerContext),
    keyPrefix: 'daily-choice-action',
    readinessFilter: IntentionReadinessFilter.readyOnly,
    ruTexts: (
      title: 'Выбор действия',
      header: 'Действия',
      pathReplacementCancel: 'Отменить выбор действия',
    ),
    emptyMessage: 'No active actions are available.',
    noMatchesMessage: 'No actions with this name',
  );
  defineDailyChoicePickerTagSearchTests(
    DailyChoicePickerTagSearchCase(
      route: DailyChoiceActionPickerRoute(
        pickerContext: const PathReplacementDailyChoicePickerContext(),
      ),
      keyPrefix: 'daily-choice-action',
      readinessFilter: IntentionReadinessFilter.readyOnly,
      rowReadiness: const [IntentionReadiness.ready],
      header: 'Actions',
      unavailableMessage: 'Actions couldn’t be loaded. Try again.',
    ),
  );

  testWidgets('различает загрузку, пустой результат и устранимую ошибку', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpApp(tester, repository);
    addTearDown(router.dispose);

    unawaited(
      router.push<IntentionId>(
        DailyChoiceActionPickerRoute(
          pickerContext: const PathReplacementDailyChoicePickerContext(),
        ),
      ),
    );
    await _settleRoute(tester);
    expect(find.text('Loading actions…'), findsOneWidget);
    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await tester.pumpAndSettle();
    expect(find.text('Actions couldn’t be loaded. Try again.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    _completeFirst(repository, 2, []);
    await tester.pumpAndSettle();
    expect(find.text('No active actions are available.'), findsOneWidget);
  });

  testWidgets(
    'буквальный фильтр сохраняет режим выбора действия и отменяется',
    (tester) async {
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpApp(tester, repository);
      addTearDown(router.dispose);
      final selection = router.push<IntentionId>(
        DailyChoiceActionPickerRoute(
          pickerContext: const PathReplacementDailyChoicePickerContext(),
        ),
      );
      await _settleRoute(tester);
      _completeFirst(repository, 1, [
        testSummary(
          index: 1,
          title: '100%',
          readiness: IntentionReadiness.ready,
        ),
      ]);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-action-filter')),
        '100%',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(repository.queryAt(2).titleFilter?.map((value) => value), '100%');
      expect(repository.queryAt(2).scope, IntentionScope.active);
      expect(
        repository.queryAt(2).readinessFilter,
        IntentionReadinessFilter.readyOnly,
      );
      _completeFirst(repository, 2, []);
      await tester.pumpAndSettle();
      expect(find.text('No actions with this name'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('daily-choice-action-cancel')),
      );
      await tester.pumpAndSettle();
      expect(await selection, isNull);
    },
  );
}

void _completeFirst(
  ControlledParticipantPickerRepository repository,
  int index,
  List<IntentionSummary> items,
) => repository.complete(
  index,
  ResultSuccess(
    IntentionCatalogFirstPage(
      items: items,
      totalCount: items.length,
      nextCursor: null,
      revision: const TestPickerRevision(1),
    ),
  ),
);

Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<AppRouter> _pumpApp(
  WidgetTester tester,
  ControlledParticipantPickerRepository repository, {
  Locale locale = const Locale('en'),
}) async {
  final router = AppRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: 50,
            prefetchRemaining: 20,
            filterDebounce: const Duration(milliseconds: 250),
          ),
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  _completeFirst(repository, 0, []);
  await tester.pumpAndSettle();
  return router;
}
