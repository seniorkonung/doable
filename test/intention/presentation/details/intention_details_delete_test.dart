import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';

import '../../../support/intention_cascade_execution.dart';

import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging_policy.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/intention_options.dart';
import '../../../support/ordinary_page_test_app.dart';
import 'details_test_support.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'подтверждение показывает последствия и передаёт выбранный состав',
    (tester) async {
      final child = testDetailsIntentionId(2);
      final main = testDetailsIntentionId(3);
      final departing = DeleteCascadeComposition(
        departing: [child],
        promoted: [],
        archivedByInvariant: [],
        mainsLosingRelation: [main],
        deletedRelationCount: 3,
        archivedRelationCount: 0,
      );
      final only = DeleteCascadeComposition(
        departing: [],
        promoted: [child],
        archivedByInvariant: [],
        mainsLosingRelation: [],
        deletedRelationCount: 1,
        archivedRelationCount: 0,
      );
      final repository = ControlledDetailsRepository()
        ..onPreviewCascade = (subject, operation) =>
            operation == CascadeOperation.delete
            ? IntentionDeleteCascadePreview(
                revision: const TestDetailsRevision(0),
                plan: CascadePlan(
                  withSupporting: departing,
                  onlyThis: only,
                  asksQuestion: true,
                ),
                titles: {child: 'Много ходить', main: 'Высыпаться'},
                isInActionPath: true,
              )
            : givenCascadePreview(
                subject,
                operation,
                const TestDetailsRevision(0),
              );
      final intention = testDetailsIntention();
      await _pumpDetailsPage(
        tester,
        repository,
        intention.id,
        locale: const Locale('ru'),
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      await chooseIntentionOption(tester, IntentionOption.delete);
      expect(find.text('Удалить 2 намерения?'), findsOneWidget);
      expect(find.textContaining('3 связи'), findsOneWidget);
      final supportingList = _listWithTitle(
        'Вспомогательные, уходят вместе с ним · 1',
      );
      final mainsList = _listWithTitle('Главные, теряют только связь · 1');
      expect(_inList(supportingList, 'Много ходить'), findsOneWidget);
      expect(_inList(mainsList, 'Высыпаться'), findsOneWidget);
      expect(find.text('Хорошая обувь'), findsNothing);
      expect(find.text('Сходить в поход'), findsNothing);
      expect(find.text('Только это: 1 станет главным'), findsOneWidget);
      await tester.tap(find.text('Только это'));
      await tester.pump();
      final command = repository.commands.single as DeleteIntention;
      expect(command.execution.choice, CascadeChoice.onlyThis);
      expect(command.execution.expected, same(only));
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('подтверждение называет уходящие в архив намерения', (
    tester,
  ) async {
    final child = testDetailsIntentionId(2);
    final shoe = testDetailsIntentionId(3);
    final lacing = testDetailsIntentionId(4);
    final cascade = DeleteCascadeComposition(
      departing: [child],
      promoted: [],
      archivedByInvariant: [shoe, lacing],
      mainsLosingRelation: [],
      deletedRelationCount: 2,
      archivedRelationCount: 1,
    );
    final only = DeleteCascadeComposition(
      departing: [],
      promoted: [child],
      archivedByInvariant: [],
      mainsLosingRelation: [],
      deletedRelationCount: 1,
      archivedRelationCount: 0,
    );
    final repository = ControlledDetailsRepository()
      ..onPreviewCascade = (subject, operation) =>
          operation == CascadeOperation.delete
          ? IntentionDeleteCascadePreview(
              revision: const TestDetailsRevision(0),
              plan: CascadePlan(
                withSupporting: cascade,
                onlyThis: only,
                asksQuestion: true,
              ),
              titles: {
                child: 'Много ходить',
                shoe: 'Хорошая обувь',
                lacing: 'Шнуровка',
              },
              isInActionPath: false,
            )
          : givenCascadePreview(
              subject,
              operation,
              const TestDetailsRevision(0),
            );
    final intention = testDetailsIntention();
    await _pumpDetailsPage(
      tester,
      repository,
      intention.id,
      locale: const Locale('ru'),
    );
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await tester.pumpAndSettle();
    await chooseIntentionOption(tester, IntentionOption.delete);
    expect(find.text('Удалить 2 намерения?'), findsOneWidget);
    expect(find.textContaining('2 связи'), findsOneWidget);
    final supportingList = _listWithTitle(
      'Вспомогательные, уходят вместе с ним · 1',
    );
    final archivedList = _listWithTitle('Уйдут в архив · 2');
    expect(_inList(supportingList, 'Много ходить'), findsOneWidget);
    expect(_inList(archivedList, 'Хорошая обувь'), findsOneWidget);
    expect(_inList(archivedList, 'Шнуровка'), findsOneWidget);
    expect(find.textContaining('Главные, теряют только связь'), findsNothing);
    await tester.tap(intentionDeletionCancel);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'длинные списки раскрываются независимо, главные видны полностью',
    (tester) async {
      final children = List.generate(5, (i) => testDetailsIntentionId(10 + i));
      final mains = List.generate(5, (i) => testDetailsIntentionId(20 + i));
      final archived = List.generate(5, (i) => testDetailsIntentionId(30 + i));
      final cascade = DeleteCascadeComposition(
        departing: children,
        promoted: [],
        archivedByInvariant: archived,
        mainsLosingRelation: mains,
        deletedRelationCount: 6,
        archivedRelationCount: 5,
      );
      final only = DeleteCascadeComposition(
        departing: [],
        promoted: [children.first],
        archivedByInvariant: archived,
        mainsLosingRelation: [],
        deletedRelationCount: 1,
        archivedRelationCount: 5,
      );
      final titles = <IntentionId, String>{
        for (var i = 0; i < children.length; i++)
          children[i]: 'Вспомогательное $i',
        for (var i = 0; i < mains.length; i++) mains[i]: 'Главное $i',
        for (var i = 0; i < archived.length; i++) archived[i]: 'Архивное $i',
      };
      final repository = ControlledDetailsRepository()
        ..onPreviewCascade = (subject, operation) =>
            operation == CascadeOperation.delete
            ? IntentionDeleteCascadePreview(
                revision: const TestDetailsRevision(0),
                plan: CascadePlan(
                  withSupporting: cascade,
                  onlyThis: only,
                  asksQuestion: true,
                ),
                titles: titles,
                isInActionPath: false,
              )
            : givenCascadePreview(
                subject,
                operation,
                const TestDetailsRevision(0),
              );
      final intention = testDetailsIntention();
      await _pumpDetailsPage(
        tester,
        repository,
        intention.id,
        locale: const Locale('ru'),
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      await chooseIntentionOption(tester, IntentionOption.delete);
      const dialogTitle = 'Удалить 6 намерений?';
      const supportingTitle = 'Вспомогательные, уходят вместе с ним · 5';
      const mainsTitle = 'Главные, теряют только связь · 5';
      const archivedTitle = 'Уйдут в архив · 5';
      final supportingList = _listWithTitle(supportingTitle);
      final mainsList = _listWithTitle(mainsTitle);
      final archivedList = _listWithTitle(archivedTitle);
      expect(find.text(dialogTitle), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(_inList(mainsList, 'Главное $i'), findsOneWidget);
        expect(
          _inList(supportingList, 'Вспомогательное $i'),
          i < 4 ? findsOneWidget : findsNothing,
        );
        expect(
          _inList(archivedList, 'Архивное $i'),
          i < 4 ? findsOneWidget : findsNothing,
        );
      }
      await tester.ensureVisible(_inList(supportingList, 'Показать все 5'));
      await tester.tap(_inList(supportingList, 'Показать все 5'));
      await tester.pumpAndSettle();
      expect(find.text(dialogTitle), findsOneWidget);
      expect(find.text(supportingTitle), findsOneWidget);
      expect(find.text(archivedTitle), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(_inList(supportingList, 'Вспомогательное $i'), findsOneWidget);
        expect(
          _inList(archivedList, 'Архивное $i'),
          i < 4 ? findsOneWidget : findsNothing,
        );
      }
      await tester.ensureVisible(_inList(archivedList, 'Показать все 5'));
      await tester.tap(_inList(archivedList, 'Показать все 5'));
      await tester.pumpAndSettle();
      expect(find.text(dialogTitle), findsOneWidget);
      expect(find.text(archivedTitle), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(_inList(archivedList, 'Архивное $i'), findsOneWidget);
      }
      expect(find.textContaining('в архив уйдут 5'), findsOneWidget);
      await tester.tap(intentionDeletionCancel);
      await tester.pumpAndSettle();
      expect(repository.commands, isEmpty);
    },
  );

  testWidgets(
    'без каскада подтверждение показывает связи и архивируемые намерения',
    (tester) async {
      final main = testDetailsIntentionId(2);
      final archived = testDetailsIntentionId(3);
      final composition = DeleteCascadeComposition(
        departing: [],
        promoted: [],
        archivedByInvariant: [archived],
        mainsLosingRelation: [main],
        deletedRelationCount: 21,
        archivedRelationCount: 1,
      );
      final repository = ControlledDetailsRepository()
        ..onPreviewCascade = (subject, operation) =>
            operation == CascadeOperation.delete
            ? IntentionDeleteCascadePreview(
                revision: const TestDetailsRevision(0),
                plan: CascadePlan(
                  withSupporting: composition,
                  onlyThis: composition,
                  asksQuestion: false,
                ),
                titles: {main: 'Главное', archived: 'В архив'},
                isInActionPath: true,
              )
            : givenCascadePreview(
                subject,
                operation,
                const TestDetailsRevision(0),
              );
      final intention = testDetailsIntention();
      await _pumpDetailsPage(
        tester,
        repository,
        intention.id,
        locale: const Locale('ru'),
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      await chooseIntentionOption(tester, IntentionOption.delete);
      expect(find.text('Удалить намерение?'), findsOneWidget);
      expect(find.textContaining('21 связь'), findsOneWidget);
      expect(find.textContaining('Теги сохранятся'), findsOneWidget);
      expect(find.textContaining('пометкой «Удалено»'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Главное'),
        ),
        findsOneWidget,
      );
      expect(find.text('В архив'), findsOneWidget);
      expect(find.text('Только это'), findsNothing);
      await tester.tap(intentionDeletionConfirm);
      await tester.pump();
      final command = repository.commands.single as DeleteIntention;
      expect(command.execution.expected, same(composition));
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('удаляет архивированное намерение из параметров без '
      'восстановления и показывает выполнение на странице', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      index: 121,
      archiveState: IntentionArchiveState.archived,
    );
    await _pumpDetailsPage(tester, repository, intention.id);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    await _deleteFromOptions(tester);

    expect(repository.commands.single, isA<DeleteIntention>());
    expect(
      find.widgetWithText(PageHead, intention.title, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Saving changes…'), findsOneWidget);

    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'отдаёт отказы удаления общей поверхности, а повтор — новое удаление',
    (tester) async {
      final scenarios = <(IntentionFailure Function(IntentionId), String, bool)>[
        (
          (_) => const IntentionNotFoundFailure(),
          'The intention no longer exists. It wasn’t deleted.',
          false,
        ),
        (
          (_) => const IntentionUnavailableFailure(),
          'The intention couldn’t be deleted. Try again.',
          true,
        ),
        (
          (_) => const IntentionCorruptionFailure(),
          'Stored data is damaged. The intention wasn’t deleted.',
          false,
        ),
        (
          (_) => const IntentionUnexpectedFailure(),
          'The intention couldn’t be deleted because of an unexpected error.',
          false,
        ),
      ];

      for (var index = 0; index < scenarios.length; index += 1) {
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(index: 130 + index);
        await _pumpDetailsPage(tester, repository, intention.id);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(ResultSuccess(intention));
        await tester.pumpAndSettle();

        await _deleteFromOptions(tester);

        final (failureFor, message, retries) = scenarios[index];
        repository.completeCommand(0, ResultFailure(failureFor(intention.id)));
        await tester.pumpAndSettle();

        expect(find.textContaining(message), findsOneWidget);
        expect(
          find.text('Delete — “${intention.title}”: $message'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(PageHead, intention.title, skipOffstage: false),
          findsOneWidget,
        );
        if (retries) {
          await _closeOperationMessage(tester);
          await _deleteFromOptions(tester);
          expect(repository.commands, hasLength(2));
          expect(repository.commands.last, isA<DeleteIntention>());
          repository.completeCommand(
            1,
            const ResultFailure(IntentionUnexpectedFailure()),
          );
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'успешное удаление после Back предъявляется оболочкой и обновляет каталог',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(
        index: 73,
        title: 'Удаляемое после ухода намерение',
      );
      repository.catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testDetailsSummary(intention)],
          totalCount: 1,
          nextCursor: null,
          revision: const _DeleteTestRevision(),
        ),
      );
      final router = AppRouter();
      final container = _detailsContainer(repository);
      addTearDown(router.dispose);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: doableTheme(Brightness.light),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
            builder: (context, child) => GraphOperationPresenter(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openIntentionGraph(tester, content: find.text(intention.title));
      await tester.tap(find.text(intention.title));
      await tester.pump();
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      await _deleteFromOptions(tester);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      repository.catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const _DeleteTestRevision(),
        ),
      );
      repository.completeCommand(0, testDetailsDeletedResult(intention));
      await tester.pumpAndSettle();

      expectIntentionGraphRootPage(router);
      expect(
        find.text(
          'Delete — “Удаляемое после ухода намерение”: Intention deleted.',
        ),
        findsOneWidget,
      );
      expect(find.text(intention.title), findsNothing);
    },
  );
}

Future<void> _pumpDetailsPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  IntentionId intentionId, {
  RelationGroupPagingPolicy? pagingPolicy,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        if (pagingPolicy case final policy?)
          relationGroupPagingPolicyProvider.overrideWithValue(policy),
      ],
      retry: (retryCount, error) => null,
      child: _localizedApp(
        IntentionDetailsPage(intentionId: intentionId),
        locale: locale,
      ),
    ),
  );
  await tester.pump();
}

ProviderContainer _detailsContainer(ControlledDetailsRepository repository) =>
    ProviderContainer(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
    );

Widget _localizedApp(Widget home, {Locale locale = const Locale('en')}) =>
    OrdinaryPageTestApp(
      locale: locale,
      builder: (context, child) =>
          GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
      home: home,
    );

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

final class _DeleteTestRevision implements GraphRevision {
  const _DeleteTestRevision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is _DeleteTestRevision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

/// Выбирает «Удалить» в параметрах намерения и подтверждает удаление.
Future<void> _deleteFromOptions(WidgetTester tester) async {
  await chooseIntentionOption(tester, IntentionOption.delete);
  await tester.tap(intentionDeletionConfirm);
  await tester.pump();
}

Finder _listWithTitle(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Column)).first;

Finder _inList(Finder list, String title) =>
    find.descendant(of: list, matching: find.text(title));
