import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';
import '../../long_term_relation/presentation/details/relation_details_test_support.dart'
    show ControlledRelationWatch, testRelationDetails;
import '../../long_term_relation/presentation/neighborhood/neighborhood_test_support.dart'
    show testRelationId;
import '../../support/in_memory_diagnostics_sink.dart';

const _archive = ValueKey('intention-details-archive');
const _message = ValueKey('graph-operation-message');
const _success = 'Архивирование — «Намерение»: Намерение архивировано.';
const _failure =
    'Архивирование — «Намерение»: Не удалось изменить состояние намерения. Повторите попытку.';
const _deleteSuccess = 'Удаление — «Намерение»: Намерение удалено.';
const _relationDeleteSuccess = 'Удаление — «связь»: Связь удалена.';
const _description = ValueKey('relation-editor-description');

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final destination in [
    AppDestination.intentionGraph,
    AppDestination.home,
  ]) {
    final resetKind = destination == AppDestination.intentionGraph
        ? 'текущему'
        : 'другому';
    testWidgets('позднее удаление намерения после сброса к $resetKind пункту '
        'сохраняет повторно открытую страницу того же намерения', (
      tester,
    ) async {
      final app = await _ControlledApp.start(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(IntentionCatalogPage)),
      );
      final catalogProvider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final catalogBefore = container.read(catalogProvider).value!;
      await app.openDetails(tester);
      final previousPage = tester.state(find.byType(IntentionDetailsPage));
      final previousRouteId = app.router.stackData.last.matchId;
      await app.delete(tester);

      await _select(tester, destination, settle: false);
      unawaited(
        app.router.push(IntentionDetailsRoute(intentionId: app.intention.id)),
      );
      await tester.pump();
      await tester.pump();
      final newPage = tester
          .stateList(find.byType(IntentionDetailsPage))
          .singleWhere((page) => !identical(page, previousPage));
      final newRouteId = app.router.stackData.last.matchId;
      expect(newPage, isNot(same(previousPage)));
      expect(newRouteId, isNot(previousRouteId));
      expect(previousPage.mounted, isTrue);
      expect(
        app.router.stackData.any((route) => route.matchId == previousRouteId),
        isFalse,
      );
      expect(app.coordinator.isRunning(app.intention.id), isTrue);

      app.complete(
        testDetailsDeletedResult(
          app.intention,
          revision: const TestDetailsRevision(1),
        ),
      );
      await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
      expect(previousPage.mounted, isTrue);
      expect(app.router.stackData.last.matchId, newRouteId);
      expect(newPage.mounted, isTrue);
      expect(
        container.read(intentionDetailsViewModelProvider(app.intention.id)),
        isA<IntentionDetailsDeleted>(),
      );
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(IntentionDetailsPage)), same(newPage));
      expect(app.router.stackData.last.matchId, newRouteId);
      expect(app.router.stack.map((page) => page.name), [
        AppShellRoute.name,
        IntentionDetailsRoute.name,
      ]);
      expect(previousPage.mounted, isFalse);
      final l10n = AppLocalizations.of(newPage.context);
      expect(find.text(l10n.detailsNotFound), findsOneWidget);
      expect(find.text(app.intention.title), findsNothing);
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        destination,
      );
      final catalogAfter = container.read(catalogProvider).value!;
      expect(catalogAfter.selection, same(catalogBefore.selection));
      expect(
        catalogAfter,
        isA<IntentionCatalogConfirmedState>()
            .having((state) => state.totalCount, 'число намерений', 0)
            .having(
              (state) => state.revision.compareTo(const TestDetailsRevision(1)),
              'ревизия каталога',
              GraphRevisionOrder.same,
            ),
      );
      expect(find.text(_deleteSuccess), findsOneWidget);
      await _expireMessages(tester);
      expect(app.router.stackData.last.matchId, newRouteId);
      expect(app.repository.commands.single, isA<DeleteIntention>());
      expect(app.repository.catalogQueries, hasLength(1));
      unawaited(app.router.maybePop());
      await tester.pumpAndSettle();
      _expectRoot(tester, app.router, destination);
    });

    testWidgets('позднее удаление связи после сброса к $resetKind пункту '
        'сохраняет повторно открытый просмотр той же связи', (tester) async {
      final app = await _ControlledApp.start(tester, activeRelationCount: 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(IntentionCatalogPage)),
      );
      final catalogProvider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final catalogBefore = container.read(catalogProvider).value!;
      await app.openRelationDetails(tester);
      final previousPage = tester.element(find.byType(RelationDetailsPage));
      final previousRouteId = app.router.stackData.last.matchId;
      await app.deleteRelation(tester);

      await _select(tester, destination, settle: false);
      unawaited(
        app.router.push(
          RelationDetailsRoute(relationId: app.relationDetails.relation.id),
        ),
      );
      await tester.pump();
      await tester.pump();
      final newPage = tester
          .elementList(find.byType(RelationDetailsPage))
          .singleWhere((page) => !identical(page, previousPage));
      final newRouteId = app.router.stackData.last.matchId;
      expect(newRouteId, isNot(previousRouteId));
      expect(previousPage.mounted, isTrue);
      expect(
        app.router.stackData.any((route) => route.matchId == previousRouteId),
        isFalse,
      );
      expect(
        app.coordinator.isRelationRunning(app.relationDetails.relation.id),
        isTrue,
      );

      app.completeRelationDelete();
      await _until(
        tester,
        () =>
            !app.coordinator.isRelationRunning(app.relationDetails.relation.id),
      );
      expect(previousPage.mounted, isTrue);
      expect(app.router.stackData.last.matchId, newRouteId);
      expect(newPage.mounted, isTrue);
      expect(
        container.read(
          relationDetailsViewModelProvider(app.relationDetails.relation.id),
        ),
        isA<RelationDetailsDeleted>(),
      );
      await tester.pumpAndSettle();

      expect(tester.element(find.byType(RelationDetailsPage)), same(newPage));
      expect(app.router.stackData.last.matchId, newRouteId);
      expect(app.router.stack.map((page) => page.name), [
        AppShellRoute.name,
        RelationDetailsRoute.name,
      ]);
      expect(previousPage.mounted, isFalse);
      final l10n = AppLocalizations.of(newPage);
      expect(find.text(l10n.relationDetailsNotFound), findsOneWidget);
      expect(
        find.byKey(const ValueKey('relation-details-phrase')),
        findsNothing,
      );
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        destination,
      );
      final catalogAfter = container.read(catalogProvider).value!;
      expect(catalogAfter.selection, same(catalogBefore.selection));
      expect(
        catalogAfter,
        isA<IntentionCatalogLoaded>()
            .having(
              (state) => state.items.single.activeRelationCount,
              'число связей после удаления',
              0,
            )
            .having(
              (state) => state.revision.compareTo(const TestDetailsRevision(1)),
              'ревизия каталога',
              GraphRevisionOrder.same,
            ),
      );
      expect(find.text(_relationDeleteSuccess), findsOneWidget);
      await _expireMessages(tester);
      expect(app.router.stackData.last.matchId, newRouteId);
      expect(
        app.repository.relationCommands.single,
        isA<DeleteLongTermRelation>(),
      );
      expect(app.repository.commands, isEmpty);
      expect(app.repository.catalogQueries, hasLength(1));
      unawaited(app.router.maybePop());
      await tester.pumpAndSettle();
      _expectRoot(tester, app.router, destination);
    });

    testWidgets('позднее удаление связи после сброса к $resetKind пункту '
        'сохраняет новую форму и её ввод до освобождения прежней страницы', (
      tester,
    ) async {
      final app = await _ControlledApp.start(tester, activeRelationCount: 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(IntentionCatalogPage)),
      );
      final catalogProvider = intentionCatalogViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      expect(
        container.read(catalogProvider).value,
        isA<IntentionCatalogLoaded>().having(
          (state) => state.items.single.activeRelationCount,
          'число связей до удаления',
          1,
        ),
      );
      await app.openRelationDetails(tester);
      final previousPage = tester.element(find.byType(RelationDetailsPage));
      final previousRouteId = app.router.stackData.last.matchId;
      await app.deleteRelation(tester);

      await _select(tester, destination, settle: false);
      unawaited(
        app.router.push(
          RelationEditorRoute(
            editorContext: RelationCreationContext(
              participant: RelationParticipantSummary(
                id: testDetailsIntentionId(3),
                title: 'Независимый участник',
                archiveState: IntentionArchiveState.active,
                activeRelationCount: 0,
              ),
              direction: RelationDirection.outgoing,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      const text = 'Несохранённое описание после сброса просмотра связи';
      await tester.enterText(find.byKey(_description), text);
      final form = tester.state(find.byType(RelationEditorPage));
      final formRouteId = app.router.stackData.last.matchId;
      expect(find.text(text), findsOneWidget);
      expect(previousPage.mounted, isTrue);
      expect(
        app.router.stackData.any((route) => route.matchId == previousRouteId),
        isFalse,
      );
      expect(
        app.coordinator.isRelationRunning(app.relationDetails.relation.id),
        isTrue,
      );

      app.completeRelationDelete();
      await _until(
        tester,
        () =>
            !app.coordinator.isRelationRunning(app.relationDetails.relation.id),
      );
      expect(previousPage.mounted, isTrue);
      expect(app.router.stackData.last.matchId, formRouteId);
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(RelationEditorPage)), same(form));
      expect(find.text(text), findsOneWidget);
      expect(app.router.stack.map((page) => page.name), [
        AppShellRoute.name,
        RelationEditorRoute.name,
      ]);
      expect(find.text(_relationDeleteSuccess), findsOneWidget);
      expect(
        container.read(catalogProvider).value,
        isA<IntentionCatalogLoaded>()
            .having(
              (state) => state.items.single.activeRelationCount,
              'число связей после удаления',
              0,
            )
            .having(
              (state) => state.revision.compareTo(const TestDetailsRevision(1)),
              'ревизия каталога',
              GraphRevisionOrder.same,
            ),
      );
      await _expireMessages(tester);
      expect(
        app.repository.relationCommands.single,
        isA<DeleteLongTermRelation>(),
      );
      expect(app.repository.commands, isEmpty);

      unawaited(app.router.maybePop());
      await tester.pumpAndSettle();
      _expectRoot(tester, app.router, destination);
      expect(
        find.byType(RelationDetailsPage, skipOffstage: false),
        findsNothing,
      );
      expect(app.repository.catalogQueries, hasLength(1));
    });
    testWidgets(
      'позднее удаление намерения после сброса к $resetKind пункту '
      'сохраняет новую форму связи и её ввод до освобождения прежней страницы',
      (tester) async {
        final app = await _ControlledApp.start(tester);
        await app.openDetails(tester);
        final previousPage = tester.state(find.byType(IntentionDetailsPage));
        final previousRouteId = app.router.stackData.last.matchId;
        await app.delete(tester);

        await _select(tester, destination, settle: false);
        unawaited(
          app.router.push(
            RelationEditorRoute(
              editorContext: RelationCreationContext(
                participant: RelationParticipantSummary(
                  id: testDetailsIntentionId(2),
                  title: 'Независимый участник',
                  archiveState: IntentionArchiveState.active,
                  activeRelationCount: 0,
                ),
                direction: RelationDirection.outgoing,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        const text = 'Несохранённое описание новой связи';
        await tester.enterText(find.byKey(_description), text);
        expect(find.text(text), findsOneWidget);
        final form = tester.state(find.byType(RelationEditorPage));
        final formRouteId = app.router.stackData.last.matchId;
        expect(previousPage.mounted, isTrue);
        expect(
          app.router.stackData.any((route) => route.matchId == previousRouteId),
          isFalse,
        );
        expect(app.coordinator.isRunning(app.intention.id), isTrue);

        app.complete(
          testDetailsDeletedResult(
            app.intention,
            revision: const TestDetailsRevision(1),
          ),
        );
        await _until(
          tester,
          () => !app.coordinator.isRunning(app.intention.id),
        );
        expect(previousPage.mounted, isTrue);
        expect(app.router.stackData.last.matchId, formRouteId);
        await tester.pumpAndSettle();

        expect(tester.state(find.byType(RelationEditorPage)), same(form));
        expect(find.text(text), findsOneWidget);
        expect(app.router.stack.map((page) => page.name), [
          AppShellRoute.name,
          RelationEditorRoute.name,
        ]);
        expect(find.text(_deleteSuccess), findsOneWidget);
        await _expireMessages(tester);
        expect(app.repository.commands.single, isA<DeleteIntention>());
        expect(app.repository.relationCommands, isEmpty);

        unawaited(app.router.maybePop());
        await tester.pumpAndSettle();
        _expectRoot(tester, app.router, destination);
        await _select(tester, AppDestination.intentionGraph);
        expect(find.text(app.intention.title), findsNothing);
        expect(app.repository.catalogQueries, hasLength(1));
      },
    );
  }

  testWidgets('удаление связи с актуальной верхней страницы закрывает только '
      'её просмотр и один раз предъявляет результат', (tester) async {
    final app = await _ControlledApp.start(tester, activeRelationCount: 1);
    await tester.tap(find.byTooltip('Теги'));
    await tester.pumpAndSettle();
    final catalogRouteId = app.router.stackData.last.matchId;
    await app.openRelationDetails(tester);
    await app.deleteRelation(tester);

    app.completeRelationDelete();
    await _until(
      tester,
      () => !app.coordinator.isRelationRunning(app.relationDetails.relation.id),
    );
    await tester.pumpAndSettle();

    expect(app.router.stackData.last.matchId, catalogRouteId);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      TagCatalogRoute.name,
    ]);
    expect(find.byType(RelationDetailsPage, skipOffstage: false), findsNothing);
    expect(find.text(_relationDeleteSuccess), findsOneWidget);
    await _expireMessages(tester);
    expect(
      app.repository.relationCommands.single,
      isA<DeleteLongTermRelation>(),
    );
    expect(app.repository.commands, isEmpty);
  });

  testWidgets('позднее удаление намерения сохраняет каталог тегов, '
      'открытый через «Теги» до освобождения сброшенной страницы', (
    tester,
  ) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    final previousPage = tester.state(find.byType(IntentionDetailsPage));
    final previousRouteId = app.router.stackData.last.matchId;
    await app.delete(tester);

    await _select(tester, AppDestination.intentionGraph, settle: false);
    await tester.pump();
    await tester.tap(find.byTooltip('Теги'));
    await tester.pump();
    await tester.pump();
    final catalog = tester.element(find.byType(TagCatalogPage));
    final catalogRouteId = app.router.stackData.last.matchId;
    expect(app.router.stackData.last.name, TagCatalogRoute.name);
    expect(previousPage.mounted, isTrue);
    expect(
      app.router.stackData.any((route) => route.matchId == previousRouteId),
      isFalse,
    );
    expect(app.coordinator.isRunning(app.intention.id), isTrue);

    app.complete(
      testDetailsDeletedResult(
        app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    expect(previousPage.mounted, isTrue);
    expect(app.router.stackData.last.matchId, catalogRouteId);
    await tester.pumpAndSettle();

    expect(tester.element(find.byType(TagCatalogPage)), same(catalog));
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      TagCatalogRoute.name,
    ]);
    expect(find.text(_deleteSuccess), findsOneWidget);
    await _expireMessages(tester);
    expect(app.repository.commands.single, isA<DeleteIntention>());
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, AppDestination.intentionGraph);
    expect(find.text(app.intention.title), findsNothing);
    expect(app.repository.catalogQueries, hasLength(1));
  });

  testWidgets('удаление с актуальной верхней страницы закрывает только её '
      'и один раз предъявляет результат', (tester) async {
    final app = await _ControlledApp.start(tester);
    await tester.tap(find.byTooltip('Теги'));
    await tester.pumpAndSettle();
    final catalogRouteId = app.router.stackData.last.matchId;
    await app.openDetails(tester);
    await app.delete(tester);

    app.complete(
      testDetailsDeletedResult(
        app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    expect(app.router.stackData.last.matchId, catalogRouteId);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      TagCatalogRoute.name,
    ]);
    expect(
      find.byType(IntentionDetailsPage, skipOffstage: false),
      findsNothing,
    );
    expect(find.text(_deleteSuccess), findsOneWidget);
    await _expireMessages(tester);
    expect(app.repository.commands.single, isA<DeleteIntention>());
  });

  testWidgets('успешный повтор удаления после отказа закрывает только '
      'принявшую повтор страницу', (tester) async {
    final app = await _ControlledApp.start(tester);
    await tester.tap(find.byTooltip('Теги'));
    await tester.pumpAndSettle();
    final catalogRouteId = app.router.stackData.last.matchId;
    await app.openDetails(tester);
    final detailsRouteId = app.router.stackData.last.matchId;
    await app.delete(tester);
    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();
    expect(app.router.stackData.last.matchId, detailsRouteId);

    final retry = find.byKey(
      const ValueKey('intention-details-state-change-retry'),
    );
    await tester.ensureVisible(retry);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pump();
    expect(app.repository.commands, hasLength(2));
    expect(app.repository.commands.last, isA<DeleteIntention>());
    app.complete(
      testDetailsDeletedResult(
        app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    expect(app.router.stackData.last.matchId, catalogRouteId);
    expect(
      find.byType(IntentionDetailsPage, skipOffstage: false),
      findsNothing,
    );
    expect(find.text(_deleteSuccess), findsOneWidget);
    await _expireMessages(tester);
  });

  testWidgets('сброс сохраняет принятое архивирование и предъявляет поздний '
      'успех один раз после уже показанного сообщения', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    final previous = testDetailsIntention(index: 2, title: 'Прежнее намерение');
    app.coordinator.acceptExisting(
      DeleteIntention(previous.id),
      presentationTitle: previous.title,
    );
    app.complete(testDetailsDeletedResult(previous));
    await _until(tester, () => !app.coordinator.isRunning(previous.id));
    await tester.pumpAndSettle();
    final previousMessage = tester
        .widget<Semantics>(find.byKey(_message))
        .properties
        .label!;
    expect(find.text(previousMessage), findsOneWidget);
    final messenger = ScaffoldMessenger.of(
      tester.element(find.byType(IntentionDetailsPage)),
    );
    await app.archive(tester);

    await _select(tester, AppDestination.home);
    expect(app.coordinator.isRunning(app.intention.id), isTrue);
    expect(app.repository.commands, hasLength(2));
    expect(
      app.coordinator.acceptExisting(
        ArchiveIntention(app.intention.id),
        presentationTitle: app.intention.title,
      ),
      isA<IntentionCommandAlreadyRunning>(),
    );

    app.complete(
      testDetailsSavedResult(
        testDetailsIntention(archiveState: IntentionArchiveState.archived),
        before: app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, AppDestination.home);
    expect(app.coordinator.isRunning(app.intention.id), isFalse);
    expect(find.text(previousMessage), findsOneWidget);
    expect(find.text(_success), findsNothing);

    messenger.hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text(_success), findsOneWidget);
    expect(find.byKey(_message), findsOneWidget);
    await _expireMessages(tester);
    expect(app.repository.commands, hasLength(2));
    _expectRoot(tester, app.router, AppDestination.home);
  });

  testWidgets('ошибка архивирования после сброса переходит общей поверхности '
      'без восстановления страницы или повтора команды', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.archive(tester);
    await _select(tester, AppDestination.intentionGraph);

    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    expect(find.text(_failure), findsOneWidget);
    _expectRoot(tester, app.router, AppDestination.intentionGraph);
    expect(app.coordinator.isRunning(app.intention.id), isFalse);
    await _expireMessages(tester);
    expect(app.repository.commands, hasLength(1));
  });

  testWidgets('сброс до пригодного кадра освобождает ошибку renderer, а его '
      'запоздалое подтверждение не поглощает сообщение общей поверхности', (
    tester,
  ) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.archive(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();
    final claim = tester
        .widget<OperationFailurePresentation>(
          find.byType(OperationFailurePresentation),
        )
        .claim!;
    expect(app.coordinator.claimInitiatorFailure(claim.token), same(claim));
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

    await _select(tester, AppDestination.home);
    expect(
      find.byType(OperationFailurePresentation, skipOffstage: false),
      findsNothing,
    );
    app.coordinator.confirmPresentation(claim);
    app.coordinator.releaseInitiatorClaim(claim);
    await tester.pump();
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(_failure), findsOneWidget);
    expect(app.coordinator.claimInitiatorFailure(claim.token), isNull);
    _expectRoot(tester, app.router, AppDestination.home);
    await _expireMessages(tester);
    expect(app.repository.commands, hasLength(1));
  });

  testWidgets('сброс после пригодного кадра не предъявляет уже показанную '
      'инлайн-ошибку повторно', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.archive(tester);
    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();
    final renderer = tester.widget<OperationFailurePresentation>(
      find.byType(OperationFailurePresentation),
    );
    final claim = renderer.claim!;
    expect(find.text(renderer.message).hitTestable(), findsOneWidget);
    expect(app.coordinator.claimInitiatorFailure(claim.token), isNull);

    await _select(tester, AppDestination.home);
    app.coordinator.confirmPresentation(claim);
    app.coordinator.releaseInitiatorClaim(claim);
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, AppDestination.home);
    await _expireMessages(tester);
    expect(app.repository.commands, hasLength(1));
  });

  testWidgets('сброс над поиском участника возвращает отмену и освобождает '
      'ожидающую форму без продолжения потока', (tester) async {
    final app = await _ControlledApp.start(tester);
    unawaited(
      app.router.push(
        RelationEditorRoute(
          editorContext: RelationCreationContext(
            participant: RelationParticipantSummary(
              id: testDetailsIntentionId(2),
              title: 'Исходное намерение',
              archiveState: IntentionArchiveState.active,
              activeRelationCount: 0,
            ),
            direction: RelationDirection.outgoing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final caller = tester.state(find.byType(RelationEditorPage));
    await tester.tap(
      find.byKey(const ValueKey('relation-editor-select-related')),
    );
    await tester.pumpAndSettle();
    final picker = find.byType(RelationParticipantPickerPage);
    final pickerResult = ModalRoute.of(tester.element(picker))!.popped;
    final l10n = AppLocalizations.of(tester.element(picker));
    await tester.tap(find.byTooltip(l10n.participantPickerOpenDetails));
    await tester.pump();
    await tester.pump();
    app.repository.detailRequests.single.add(ResultSuccess(app.intention));
    await tester.pumpAndSettle();

    await _select(tester, AppDestination.home);

    expect(await pickerResult, isNull);
    expect(caller.mounted, isFalse);
    expect(find.byType(RelationEditorPage, skipOffstage: false), findsNothing);
    expect(picker, findsNothing);
    _expectRoot(tester, app.router, AppDestination.home);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, AppDestination.home);
    expect(app.repository.commands, isEmpty);
    expect(app.repository.relationCommands, isEmpty);
  });
}

Future<void> _select(
  WidgetTester tester,
  AppDestination destination, {
  bool settle = true,
}) async {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(AppNavigationBar)),
  );
  await tester.tap(find.byTooltip(destination.title(l10n)));
  if (settle) await tester.pumpAndSettle();
}

void _expectRoot(
  WidgetTester tester,
  AppRouter router,
  AppDestination destination,
) {
  expect(router.stack.map((page) => page.name), [AppShellRoute.name]);
  expect(router.topRoute.name, destination.page.name);
  expect(router.hasPagelessTopRoute, isFalse);
  expect(find.byType(IntentionDetailsPage, skipOffstage: false), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _expireMessages(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

final class _ControlledApp {
  _ControlledApp(this.runtime, this.router, this.repository);

  final AppRuntime runtime;
  final AppRouter router;
  final ControlledDetailsRepository repository;
  final intention = testDetailsIntention(description: null);
  final relationDetails = testRelationDetails(
    relationId: testRelationId(101),
    sourceId: testDetailsIntentionId(1),
    relatedId: testDetailsIntentionId(2),
    sourceTitle: 'Намерение',
  );
  var completedCommands = 0;
  var completedRelationCommands = 0;
  GraphCommandCoordinator get coordinator => runtime.commandCoordinator;

  static Future<_ControlledApp> start(
    WidgetTester tester, {
    int activeRelationCount = 0,
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final repository = ControlledDetailsRepository()
      ..catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testDetailsSummary(
              testDetailsIntention(description: null),
              activeRelationCount: activeRelationCount,
            ),
          ],
          totalCount: 1,
          nextCursor: null,
          revision: const TestDetailsRevision(0),
        ),
      );
    final runtime = AppRuntime(
      connectionFactory: () => openInMemoryLocalDatabase(),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      repositoryFactory: (_) => repository,
    );
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    final app = _ControlledApp(
      runtime,
      ready.container.read(appRouterProvider),
      repository,
    );
    addTearDown(() async {
      while (app.completedCommands < repository.commands.length) {
        app.complete(const ResultFailure(IntentionUnavailableFailure()));
      }
      while (app.completedRelationCommands <
          repository.relationCommands.length) {
        repository.completeRelationCommand(
          app.completedRelationCommands++,
          const GraphCommandFailed(LongTermRelationUnavailableFailure()),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      for (final request in repository.detailRequests) {
        await request.close();
      }
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await tester.pumpAndSettle();
    await _select(tester, AppDestination.intentionGraph);
    return app;
  }

  Future<void> openDetails(WidgetTester tester) async {
    unawaited(router.push(IntentionDetailsRoute(intentionId: intention.id)));
    await tester.pump();
    await tester.pump();
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();
  }

  Future<void> openRelationDetails(WidgetTester tester) async {
    final watch = ControlledRelationWatch(relationDetails.relation.id);
    addTearDown(watch.close);
    repository.onWatchRelation = (id) {
      expect(id, relationDetails.relation.id);
      return watch.stream;
    };
    unawaited(
      router.push(
        RelationDetailsRoute(relationId: relationDetails.relation.id),
      ),
    );
    await tester.pump();
    await tester.pump();
    watch.emitDetails(relationDetails, revision: const TestDetailsRevision(0));
    await tester.pumpAndSettle();
  }

  Future<void> deleteRelation(WidgetTester tester) async {
    final delete = find.byKey(
      const ValueKey('relation-details-delete-relation'),
    );
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('relation-details-confirm-delete')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.relationCommands.single, isA<DeleteLongTermRelation>());
    expect(coordinator.isRelationRunning(relationDetails.relation.id), isTrue);
  }

  void completeRelationDelete() {
    const revision = TestDetailsRevision(1);
    repository.completeRelationCommand(
      completedRelationCommands++,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationDeleted(
            relation: relationDetails.relation,
            changes: [
              LongTermRelationDeletedChange(
                revision: revision,
                relation: relationDetails.relation,
              ),
              for (final id in [
                relationDetails.source.id,
                relationDetails.related.id,
              ])
                IntentionRelationCountsChanged(
                  revision: revision,
                  intentionId: id,
                  counts: testRelationCounts(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> archive(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_archive));
    await tester.tap(find.byKey(_archive));
    await tester.pump();
    expect(repository.commands.last, isA<ArchiveIntention>());
    expect(coordinator.isRunning(intention.id), isTrue);
  }

  Future<void> delete(WidgetTester tester) async {
    final delete = find.byKey(const ValueKey('intention-details-delete'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('intention-details-confirm-delete')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.commands.single, isA<DeleteIntention>());
    expect(coordinator.isRunning(intention.id), isTrue);
  }

  void complete(Result<IntentionCommandSuccess> result) {
    repository.completeCommand(completedCommands++, result);
  }
}
