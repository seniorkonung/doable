import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:auto_route/auto_route.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement,
        observeConfiguredLocalDatabaseConnection,
        openInMemoryLocalDatabase;
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as catalog_page;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/favorite_read_contract_test_fallback.dart';
import '../support/favorite_storage_fixture.dart';
import '../support/tag_read_contract_test_fallback.dart';
import '../support/catalog_reconciliation_test_fallback.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/quick_creation.dart';

void main() {
  testWidgets(
    'ошибка массового удаления после ухода из собранного экрана предъявляется один раз',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final intentionA = _intention(title: 'A', description: null);
      final intentionB = _intention(
        uuid: '018f0000-0000-7000-8000-000000000002',
        title: 'B',
        description: null,
      );
      final repository = _DelayedPersonalGraphRepository(
        relation: _relationSummary(intentionA, intentionB),
      );
      final runtime = await _pumpCatalog(tester, repository, [
        intentionA,
        intentionB,
      ]);
      await _openDetails(tester, repository, intentionA, requestIndex: 0);
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-delete')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await _pumpUntil(tester, () => repository.commands.length == 1);
      repository.completeCommand(
        0,
        ResultFailure(IntentionHasBlockingRelationsFailure(intentionA.id)),
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('intention-details-show-blocking-relations'))
            .evaluate()
            .isNotEmpty,
      );
      final showBlocking = find.byKey(
        const ValueKey('intention-details-show-blocking-relations'),
      );
      await tester.ensureVisible(showBlocking);
      await tester.tap(showBlocking);
      await tester.pumpAndSettle();
      final select = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${_relationId.toCanonicalString()}',
        ),
      );
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('blocking-relations-review'));
      await tester.ensureVisible(review);
      await tester.tap(review);
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('blocking-relations-confirm-delete'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(
        find.byKey(const ValueKey('blocking-relations-confirm-delete')),
      );
      await _pumpUntil(
        tester,
        () => repository.blockingRelationsCommands.length == 1,
      );
      expect(repository.blockingRelationsCommands.single.relationIds, {
        _relationId,
      });

      await tester.pumpAndSettle();
      await _goBack(tester);
      await _openDetails(tester, repository, intentionB, requestIndex: 1);
      expect(runtime.commandCoordinator.isRunning(intentionA.id), isTrue);
      repository.completeBlockingRelationsCommand(
        0,
        const GraphCommandFailed<
          BlockingRelationsDeleted,
          DeleteBlockingRelationsFailure
        >(DeleteBlockingRelationsUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      const message =
          'Delete selected relations — “A”: Selected relations couldn’t be deleted. Try again.';
      expect(find.text(message), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: message,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      await _closeOperationMessage(tester);
      expect(find.text(message), findsNothing);
      expect(repository.blockingRelationsCommands, hasLength(1));
      semantics.dispose();
    },
  );

  testWidgets(
    'оболочка показывает результат ушедшего экрана поверх другого намерения один раз',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final repository = _DelayedPersonalGraphRepository();
      final intentionA = _intention(
        uuid: '018f0000-0000-7000-8000-000000000001',
        title: 'A',
        description: null,
      );
      final intentionB = _intention(
        uuid: '018f0000-0000-7000-8000-000000000002',
        title: 'B',
        description: null,
      );
      await _pumpCatalog(tester, repository, [intentionA, intentionB]);

      await _openDetails(tester, repository, intentionA, requestIndex: 0);
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-archive')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-archive')));
      await tester.pump();
      expect(repository.commands.single, isA<ArchiveIntention>());

      await _goBack(tester);
      await tester.pumpAndSettle();
      await _openDetails(tester, repository, intentionB, requestIndex: 1);

      final archivedA = _copyIntention(
        intentionA,
        archiveState: IntentionArchiveState.archived,
        updatedDay: 2,
      );
      repository.completeCommand(
        0,
        _saved(archivedA, before: intentionA, revision: 1),
      );
      await tester.pumpAndSettle();

      const message = 'Archive — “A”: Intention archived.';
      expect(find.text(message), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: message,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      semantics.dispose();

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _goBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      expect(find.text(message), findsNothing);
    },
  );

  testWidgets(
    'массовый отказ после ухода предъявляется оболочкой над другим намерением один раз',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final repository = _DelayedPersonalGraphRepository();
      final intentionA = _intention(
        uuid: '018f0000-0000-7000-8000-000000000001',
        title: 'A',
        description: null,
      );
      final intentionB = _intention(
        uuid: '018f0000-0000-7000-8000-000000000002',
        title: 'B',
        description: null,
      );
      final runtime = await _pumpCatalog(tester, repository, [
        intentionA,
        intentionB,
      ]);
      await _openDetails(tester, repository, intentionA, requestIndex: 0);

      final accepted = runtime.commandCoordinator.acceptBlockingRelationsDelete(
        DeleteBlockingRelations.longTerm(
          intentionId: intentionA.id,
          relationIds: {_relationId},
        ),
        presentationTitle: intentionA.title,
      ) as BlockingRelationsDeleteAccepted;
      expect(repository.blockingRelationsCommands, hasLength(1));
      await _goBack(tester);
      runtime.commandCoordinator.releaseInitiatorPresentation(accepted.token);
      await _openDetails(tester, repository, intentionB, requestIndex: 1);
      expect(runtime.commandCoordinator.isRunning(intentionA.id), isTrue);
      expect(runtime.commandCoordinator.isRelationRunning(_relationId), isTrue);

      repository.completeBlockingRelationsCommand(
        0,
        const GraphCommandFailed<
          BlockingRelationsDeleted,
          DeleteBlockingRelationsFailure
        >(DeleteBlockingRelationsUnavailableFailure()),
      );
      final completion = await accepted.future;
      await tester.pumpAndSettle();

      const message =
          'Delete selected relations — “A”: Selected relations couldn’t be deleted. Try again.';
      expect(completion.token, same(accepted.token));
      expect(runtime.commandCoordinator.isRunning(intentionA.id), isFalse);
      expect(
        runtime.commandCoordinator.isRelationRunning(_relationId),
        isFalse,
      );
      expect(find.text(message), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: message,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      semantics.dispose();

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _goBack(tester);
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(repository.blockingRelationsCommands, hasLength(1));
    },
  );

  for (final scenario in <({Locale locale, String message})>[
    (
      locale: Locale('en'),
      message:
          'Archive — “A”: The intention state couldn’t be changed. Try again.',
    ),
    (
      locale: Locale('ru'),
      message: 'Архивирование — «A»: Не удалось изменить состояние намерения. Повторите попытку.',
    ),
  ]) {
    testWidgets(
      'оболочка ждёт возвращения приложения перед показом failure (${scenario.locale.languageCode})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.binding.platformDispatcher.localesTestValue = [scenario.locale];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        final repository = _DelayedPersonalGraphRepository();
        final intentionA = _intention(
          uuid: '018f0000-0000-7000-8000-000000000001',
          title: 'A',
          description: null,
        );
        final intentionB = _intention(
          uuid: '018f0000-0000-7000-8000-000000000002',
          title: 'B',
          description: null,
        );
        await _pumpCatalog(tester, repository, [intentionA, intentionB]);

        await _openDetails(tester, repository, intentionA, requestIndex: 0);
        await tester.ensureVisible(
          find.byKey(const ValueKey('intention-details-archive')),
        );
        await tester.tap(
          find.byKey(const ValueKey('intention-details-archive')),
        );
        await tester.pump();
        await _goBack(tester);
        await tester.pumpAndSettle();
        await _openDetails(tester, repository, intentionB, requestIndex: 1);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        expect(find.text(scenario.message), findsNothing);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(find.text(scenario.message), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: scenario.message,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'проходит полный app-level lifecycle через задерживаемый repository',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final repository = _DelayedPersonalGraphRepository();
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: openInMemoryLocalDatabase,
        diagnosticsSink: InMemoryDiagnosticsSink(),
        repositoryFactory: (_) => repository,
      );
      addTearDown(() async {
        await runtime.shutdown();
        await repository.close();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(
        tester,
        waitFor: (tester, finder) =>
            _pumpUntil(tester, () => finder.evaluate().isNotEmpty),
      );
      await _pumpUntil(tester, () => repository.pageQueries.isNotEmpty);
      repository.completePage(
        0,
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const _Revision(0),
        ),
      );
      await tester.pumpAndSettle();

      await _openPanel(tester);
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        '  Быть здоровым  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-description')),
        '  Пользовательское описание\n',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await tester.pump();
      expect(repository.commands.single, isA<CreateIntention>());
      expect(find.text('Saving…'), findsOneWidget);

      // Уход во время принятой отправки подтверждается и её не отменяет.
      await tester.tap(find.byKey(const ValueKey('intention-editor-close')));
      await tester.pumpAndSettle();
      expect(find.text('Close the form?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('intention-editor-close-discard')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('intention-editor-title')),
        findsNothing,
      );
      expect(repository.commands, hasLength(1));
      final created = _intention(
        title: 'Быть здоровым',
        description: '  Пользовательское описание\n',
      );
      repository.completeCommand(0, _saved(created, revision: 1));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('Create — “Быть здоровым”: Intention created.'),
        findsOneWidget,
      );
      expect(find.text(created.title), findsOneWidget);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('Create — “Быть здоровым”: Intention created.'),
        findsNothing,
      );

      await tester.tap(find.text(created.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 2);
      repository.emitDetail(0, created);
      await tester.pumpAndSettle();
      expect(find.text(created.description!), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-edit')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-edit')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        'Укреплять здоровье',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-description')),
        'Новое описание',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pump();
      final updated = _copyIntention(
        created,
        title: 'Укреплять здоровье',
        description: 'Новое описание',
        updatedDay: 2,
      );
      repository.completeCommand(
        1,
        _saved(updated, before: created, revision: 2),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 3);

      repository.emitDetail(0, created);
      await tester.pump();
      await _scrollCurrentPageToTop(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('intention-details-title')))
            .data,
        created.title,
      );
      expect(find.text(updated.title), findsNothing);
      repository.emitDetail(2, updated);
      await tester.pumpAndSettle();
      expect(
        find.text('Edit — “Укреплять здоровье”: Changes saved.'),
        findsOneWidget,
      );
      await _closeOperationMessage(tester);

      final enableReadiness = find.byKey(
        const ValueKey('intention-details-enable-readiness'),
      );
      await Scrollable.ensureVisible(
        tester.element(enableReadiness),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(enableReadiness);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as ready'));
      await tester.pump();
      final ready = _copyIntention(
        updated,
        readiness: IntentionReadiness.ready,
        updatedDay: 3,
      );
      repository.completeCommand(
        2,
        _saved(ready, before: updated, revision: 3),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 4);
      repository.emitDetail(3, ready);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(find.text('Ready for action'), findsOneWidget);
      await _closeOperationMessage(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-archive')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-archive')));
      await tester.pump();
      final archived = _copyIntention(
        ready,
        archiveState: IntentionArchiveState.archived,
        updatedDay: 4,
      );
      repository.completeCommand(
        3,
        _saved(archived, before: ready, revision: 4),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 5);
      repository.emitDetail(4, archived);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(find.text('Archived'), findsOneWidget);
      await _closeOperationMessage(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No active intentions yet.'), findsOneWidget);
      await _selectScope(tester, 'Archived');
      await _pumpUntil(tester, () => repository.pageQueries.length == 2);
      repository.completePage(
        1,
        IntentionCatalogFirstPage(
          items: [_summary(archived)],
          totalCount: 1,
          nextCursor: null,
          revision: const _Revision(4),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(archived.title), findsOneWidget);

      await tester.tap(find.text(archived.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 7);
      repository.emitDetail(4, archived);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-restore')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-restore')));
      await tester.pump();
      final restored = _copyIntention(
        archived,
        archiveState: IntentionArchiveState.active,
        updatedDay: 5,
      );
      repository.completeCommand(
        4,
        _saved(restored, before: archived, revision: 5),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 8);
      repository.emitDetail(5, restored);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(find.text('Active'), findsOneWidget);
      await _closeOperationMessage(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No archived intentions yet.'), findsOneWidget);
      await _selectScope(tester, 'Active');
      await _pumpUntil(tester, () => repository.pageQueries.length == 3);
      repository.completePage(
        2,
        IntentionCatalogFirstPage(
          items: [_summary(restored)],
          totalCount: 1,
          nextCursor: null,
          revision: const _Revision(5),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(restored.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 10);
      repository.emitDetail(6, restored);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('intention-details-delete')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await tester.pump();
      expect(repository.commands.last, isA<DeleteIntention>());

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(catalog_page.IntentionCatalogPage), findsOneWidget);
      repository.completeCommand(5, _deleted(restored, revision: 6));
      await tester.pumpAndSettle();

      expect(
        find.text('Delete — “Укреплять здоровье”: Intention deleted.'),
        findsOneWidget,
      );
      expect(find.text(restored.title), findsNothing);
      expect(find.text('No active intentions yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'подтверждение закрытия на настоящем маршруте сохраняет черновик при '
    'продолжении, сброс ничего не создаёт, а уход во время записи не отменяет '
    'сохранение',
    (tester) async {
      const title = ValueKey('intention-editor-title');
      String? titleText() =>
          tester.widget<TextField>(find.byKey(title)).controller?.text;
      final writeGate = _CreationWriteGate();
      final app = await _RealStorageApp.start(
        tester,
        const Locale('ru'),
        observer: writeGate,
      );
      final before = _storedGraph(app.raw);

      await _openPanel(tester);
      await tester.enterText(find.byKey(title), '  Черновик  ');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Сбросить черновик?'), findsOneWidget);
      await tester.tap(find.text('Продолжить ввод'));
      await tester.pumpAndSettle();
      expect(titleText(), '  Черновик  ');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сбросить'));
      await tester.pumpAndSettle();

      expect(find.byKey(title), findsNothing);
      expect(find.byType(catalog_page.IntentionCatalogPage), findsOneWidget);
      expect(_storedGraph(app.raw), before);

      await _openPanel(tester);
      expect(titleText(), isEmpty);

      writeGate.hold();
      addTearDown(writeGate.release);
      await tester.enterText(find.byKey(title), 'Сохранённое намерение');
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await _waitForStorage(tester, () => writeGate.isHolding);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Закрыть форму?'), findsOneWidget);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.byKey(title), findsNothing);
      expect(find.byType(catalog_page.IntentionCatalogPage), findsOneWidget);
      expect(_storedIntentionCount(app.raw), 0);

      writeGate.release();
      await _waitForStorage(
        tester,
        () => find.byKey(_operationMessage).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Создание — «Сохранённое намерение»: Намерение создано.'),
        findsOneWidget,
      );
      expect(_storedIntentionCount(app.raw), 1);
      await _closeOperationMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      await _closeOperationMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(_storedIntentionCount(app.raw), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'принятое полное создание завершается настоящим хранилищем после ухода '
    'инициатора и предъявляется общей поверхностью один раз',
    (tester) async {
      final writeGate = _CreationWriteGate();
      final app = await _RealStorageApp.start(
        tester,
        const Locale('en'),
        observer: writeGate,
      );
      final completions = <IntentionCommandCompletion>[];
      final subscription = app.coordinator.intentionCompletions.listen(
        completions.add,
      );
      addTearDown(subscription.cancel);
      final formKey = IntentionCreationFormKey();

      writeGate.hold();
      addTearDown(writeGate.release);
      final accepted = app.coordinator.acceptCreation(
        formKey,
        CreateIntention.withInitialState(
          title: 'Полное намерение',
          description: null,
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
          tagIds: [_storedTag(_homeTag), _storedTag(_weekendTag)],
        ),
      ) as IntentionCommandAccepted;
      await _waitForStorage(tester, () => writeGate.isHolding);

      // Форма ушла до результата: команда продолжается, повтор той же
      // формы не принимается, а запись ещё не подтверждена.
      app.coordinator.releaseInitiatorPresentation(accepted.token);
      expect(
        app.coordinator.acceptCreation(
          formKey,
          const CreateIntention(title: 'Повтор', description: null),
        ),
        isA<IntentionCommandAlreadyRunning>(),
      );
      await tester.pump();
      expect(app.coordinator.isKeyRunning(formKey), isTrue);
      expect(completions, isEmpty);
      expect(find.byKey(_operationMessage), findsNothing);
      expect(_storedIntentionCount(app.raw), 0);

      writeGate.release();
      await _waitForStorage(
        tester,
        () => find.byKey(_operationMessage).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('Create — “Полное намерение”: Intention created.'),
        findsOneWidget,
      );
      expect(app.coordinator.isKeyRunning(formKey), isFalse);
      expect(completions, hasLength(1));
      final changes = completions.single.confirmedChange!.changes.toList();
      expect(changes, [
        isA<IntentionCatalogCreated>(),
        isA<TagAssignmentChangedChange>(),
        isA<TagAssignmentChangedChange>(),
      ]);
      expect(
        changes.map((change) => change.revision),
        everyElement(same(completions.single.revision)),
      );
      final intentionId = app.raw
          .select('SELECT id, is_action_ready FROM intentions')
          .single;
      expect(intentionId['is_action_ready'], 1);
      expect(
        app.raw
            .select(
              'SELECT tag_id FROM tag_assignments WHERE intention_id = ? '
              'ORDER BY tag_id',
              [intentionId['id']],
            )
            .map((row) => row['tag_id']),
        [tagFixtureId(_homeTag), tagFixtureId(_weekendTag)],
      );
      expect(storedFavoriteMarks(app.raw), [(intentionId['id'], 1)]);

      await _closeOperationMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      await _closeOperationMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(completions, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'отказ отсутствующего тега остаётся у живой формы и после её ухода '
    'предъявляется общей поверхностью один раз без частичной записи',
    (tester) async {
      final app = await _RealStorageApp.start(tester, const Locale('ru'));
      final before = _storedGraph(app.raw);
      final accepted = app.coordinator.acceptCreation(
        IntentionCreationFormKey(),
        CreateIntention.withInitialState(
          title: 'Полное намерение',
          description: null,
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
          tagIds: [_storedTag(_homeTag), _storedTag(_missingTag)],
        ),
      ) as IntentionCommandAccepted;
      IntentionCommandCompletion? completion;
      unawaited(accepted.future.then((value) => completion = value));
      await _waitForStorage(tester, () => completion != null);

      expect(
        completion!.result,
        isA<ResultFailure<IntentionCommandSuccess>>().having(
          (result) => result.failure,
          'отказ',
          isA<IntentionCreationTagsMissingFailure>().having(
            (failure) => failure.missingTagIds,
            'отсутствующие теги',
            {_storedTag(_missingTag)},
          ),
        ),
      );
      expect(_storedGraph(app.raw), before);

      // Живая форма удерживает право на своё сообщение.
      final initiatorClaim = app.coordinator.claimInitiatorFailure(
        accepted.token,
      );
      expect(initiatorClaim, isNotNull);
      await tester.pumpAndSettle();
      expect(find.byKey(_operationMessage), findsNothing);

      app.coordinator.releaseInitiatorPresentation(accepted.token);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('Создание — «новое намерение»: Проверьте введённые данные.'),
        findsOneWidget,
      );

      // Запоздалый кадр закрытой формы не подтверждает право оболочки и не
      // повторяет сообщение.
      app.coordinator.confirmPresentation(initiatorClaim!);
      await _closeOperationMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      await _closeOperationMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(_storedGraph(app.raw), before);
      expect(tester.takeException(), isNull);
    },
  );

  group('общие сообщения и завершение отправки модальной панели', () {
    testWidgets('занятая очередь не задерживает открытие созданного намерения '
        'и предъявляет успех после прежнего сообщения ровно один раз', (
      tester,
    ) async {
      final repository = _DelayedPersonalGraphRepository();
      final runtime = await _pumpCatalog(tester, repository, const []);
      final completions = _collectCompletions(runtime);
      await _openPanel(tester);
      final router = tester.element(find.byType(IntentionEditorPage)).router;
      await tester.enterText(find.byKey(_editorTitle), 'Новое намерение');
      final firstMessage = await _failOtherIntentionDelete(
        tester,
        runtime,
        repository,
        uuid: '018f0000-0000-7000-8000-000000000011',
        title: 'Другое намерение',
      );
      await tester.pumpAndSettle();
      _expectVisibleOverPanel(tester, firstMessage);
      await tester.tap(find.byKey(_submit));
      await _pumpUntil(tester, () => repository.commands.length == 2);

      final created = _intention(title: 'Новое намерение', description: null);
      repository.completeCommand(1, _saved(created, revision: 1));
      await _pumpUntil(tester, () => repository.detailIds.contains(created.id));
      repository.emitDetail(1, created);
      await tester.pumpAndSettle();

      const successMessage = 'Create — “Новое намерение”: Intention created.';
      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        created.id,
      );
      expect(find.byType(IntentionEditorPage), findsNothing);
      expect(find.text(created.title), findsOneWidget);
      expect(_visible(firstMessage), findsOneWidget);
      expect(_anywhere(successMessage), findsNothing);
      final detailsRoute = router.stackData.last;
      await tester.pump(const Duration(milliseconds: 200));
      expect(router.stackData.last, same(detailsRoute));
      expect(_visible(firstMessage), findsOneWidget);
      expect(_anywhere(successMessage), findsNothing);

      await _closeOperationMessage(tester);
      expect(_anywhere(firstMessage), findsNothing);
      expect(_visible(successMessage), findsOneWidget);
      expect(router.stackData.last, same(detailsRoute));
      await _closeOperationMessage(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
      expect(router.stackData.map((route) => route.name), [
        AppShellRoute.name,
        IntentionDetailsRoute.name,
      ]);
      expect(repository.commands.whereType<CreateIntention>(), hasLength(1));
      expect(
        completions.where(
          (completion) => completion.kind == IntentionCommandKind.create,
        ),
        hasLength(1),
      );
      await returnToIntentionGraphAfterCreation(tester, router);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('отказ чтения созданного намерения повторяет только чтение '
        'того же идентификатора без новых команд и сообщений', (tester) async {
      final repository = _DelayedPersonalGraphRepository();
      final runtime = await _pumpCatalog(tester, repository, const []);
      final completions = _collectCompletions(runtime);
      await _openPanel(tester);
      final router = tester.element(find.byType(IntentionEditorPage)).router;
      await tester.enterText(find.byKey(_editorTitle), 'Сохранённое намерение');
      await tester.tap(find.byKey(_submit));
      await _pumpUntil(tester, () => repository.commands.length == 1);

      final created = _intention(
        title: 'Сохранённое намерение',
        description: null,
      );
      repository.completeCommand(0, _saved(created, revision: 1));
      await _pumpUntil(tester, () => repository.detailIds.contains(created.id));
      final detailsRoute = router.stackData.last;
      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        created.id,
      );
      final completion = completions.single;
      final saved = switch (completion.result) {
        ResultSuccess(value: IntentionSaved(:final intention)) => intention,
        final result => fail('Создание не подтверждено: $result'),
      };
      expect(saved.id, created.id);

      for (var attempt = 0; attempt < 2; attempt++) {
        for (final request in repository.detailRequests) {
          request.add(const ResultFailure(IntentionUnavailableFailure()));
        }
        await tester.pumpAndSettle();
        expect(
          _visible('The intention couldn’t be loaded. Try again.'),
          findsOneWidget,
        );
        expect(find.byType(IntentionEditorPage), findsNothing);
        expect(router.stackData.last, same(detailsRoute));
        if (attempt == 0) {
          expect(
            _visible('Create — “Сохранённое намерение”: Intention created.'),
            findsOneWidget,
          );
          await _closeOperationMessage(tester);
        }
        final previousReads = repository.detailRequests.length;
        await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
        await _pumpUntil(
          tester,
          () => repository.detailRequests.length == previousReads + 1,
        );
        expect(repository.detailIds.last, created.id);
        repository.emitDetail(1, created);
        await tester.pumpAndSettle();
        expect(find.text(created.title), findsOneWidget);
        expect(router.stackData.last, same(detailsRoute));
        expect(repository.commands, hasLength(1));
        expect(completions, [same(completion)]);
        expect(completion.isFailure, isFalse);
        expect(completion.confirmedChange, isNotNull);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
      }
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(repository.commands, hasLength(1));
      expect(completions, [same(completion)]);
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
      await returnToIntentionGraphAfterCreation(tester, router);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final transition in _SheetTransition.values) {
      testWidgets(
        '${transition.description} не дублирует и не перезапускает текущее '
        'сообщение, а следующий исход ждёт его закрытия',
        (tester) async {
          final repository = _DelayedPersonalGraphRepository();
          final runtime = await _pumpCatalog(tester, repository, const []);
          await transition.prepare(tester);
          final first = await _failOtherIntentionDelete(
            tester,
            runtime,
            repository,
            uuid: '018f0000-0000-7000-8000-000000000011',
            title: 'Первое',
          );
          await tester.pumpAndSettle();
          expect(_visible(first), findsOneWidget);
          final second = await _failOtherIntentionDelete(
            tester,
            runtime,
            repository,
            uuid: '018f0000-0000-7000-8000-000000000012',
            title: 'Второе',
          );
          await tester.pumpAndSettle();
          expect(_anywhere(second), findsNothing);

          await transition.cover(tester);
          expect(_anywhere(first), findsWidgets);
          expect(_visible(first).evaluate().length, lessThanOrEqualTo(1));
          expect(_anywhere(second), findsNothing);
          await transition.uncover(tester);
          expect(_visible(first), findsOneWidget);
          expect(_anywhere(second), findsNothing);

          await _closeOperationMessage(tester);
          expect(_anywhere(first), findsNothing);
          expect(_visible(second), findsOneWidget);
          await _closeOperationMessage(tester);
          expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
          await _closeOperationMessage(tester);
          expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
          expect(repository.commands, hasLength(2));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('успех при открытом подтверждении заменяет панель намерением, '
        'предъявляется один раз и не закрывает новое открытие', (tester) async {
      final repository = _DelayedPersonalGraphRepository();
      await _pumpCatalog(tester, repository, const []);
      await _openPanel(tester);
      final router = tester.element(find.byType(IntentionEditorPage)).router;
      await tester.enterText(find.byKey(_editorTitle), 'Своё намерение');
      await tester.tap(find.byKey(_submit));
      await _pumpUntil(tester, () => repository.commands.length == 1);
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.text('Close the form?'), findsOneWidget);

      final created = _intention(title: 'Своё намерение', description: null);
      repository.completeCommand(0, _saved(created, revision: 1));
      await _pumpUntil(tester, () => repository.detailIds.contains(created.id));
      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        created.id,
      );
      repository.emitDetail(1, created);
      await tester.pumpAndSettle();

      const message = 'Create — “Своё намерение”: Intention created.';
      expect(find.text('Close the form?'), findsNothing);
      expect(find.byType(IntentionEditorPage), findsNothing);
      expect(_visible(message), findsOneWidget);
      expect(find.text(created.title), findsOneWidget);
      expect(router.stackData.map((route) => route.name), [
        AppShellRoute.name,
        IntentionDetailsRoute.name,
      ]);
      await returnToIntentionGraphAfterCreation(tester, router);
      expect(find.text('Total intentions: 1'), findsOneWidget);

      await _openPanel(tester);
      await tester.enterText(find.byKey(_editorTitle), 'Новое открытие');
      // Меню и анимации нового входа уже продвинули время сообщения.
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(IntentionEditorPage), findsOneWidget);
      expect(find.text('Close the form?'), findsNothing);
      expect(_visible(message), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(IntentionEditorPage),
          matching: _visible(message),
        ),
        findsOneWidget,
      );
      await _closeOperationMessage(tester);
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
      expect(_fieldText(tester), 'Новое открытие');
      expect(repository.commands, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('отказ при открытом подтверждении остаётся у живой панели и не '
        'предъявляется общей поверхностью', (tester) async {
      final repository = _DelayedPersonalGraphRepository();
      final runtime = await _pumpCatalog(tester, repository, const []);
      final completions = _collectCompletions(runtime);
      await _openPanel(tester);
      await tester.enterText(find.byKey(_editorTitle), 'Намерение');
      await tester.tap(find.byKey(_submit));
      await _pumpUntil(tester, () => repository.commands.length == 1);
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.text('Close the form?'), findsOneWidget);

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Close the form?'), findsNothing);
      expect(find.byKey(_pinnedFailure).hitTestable(), findsOneWidget);
      expect(_fieldText(tester), 'Намерение');
      expect(
        runtime.commandCoordinator.claimInitiatorFailure(
          completions.single.token,
        ),
        isNull,
      );
      await _closeOperationMessage(tester);
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
      expect(find.byKey(_pinnedFailure).hitTestable(), findsOneWidget);
      expect(repository.commands, hasLength(1));
    });

    for (final overlay in _FormOverlay.values) {
      testWidgets('${overlay.description} удерживает право ошибки панели до '
          'возвращения и её пригодного кадра', (tester) async {
        final repository = _DelayedPersonalGraphRepository();
        final runtime = await _pumpCatalog(tester, repository, const []);
        final coordinator = runtime.commandCoordinator;
        final completions = _collectCompletions(runtime);
        await _failSubmissionWithoutFocus(tester, repository);
        final token = completions.single.token;
        final claim = coordinator.claimInitiatorFailure(token);
        expect(claim, isNotNull);

        await overlay.cover(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(coordinator.claimInitiatorFailure(token), same(claim));
        await overlay.uncoverPartly(tester);
        expect(coordinator.claimInitiatorFailure(token), same(claim));
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

        await overlay.uncover(tester);
        expect(find.byKey(_pinnedFailure).hitTestable(), findsOneWidget);
        expect(coordinator.claimInitiatorFailure(token), isNull);
        await _closeOperationMessage(tester);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
        expect(_fieldText(tester), 'Намерение');
        expect(repository.commands, hasLength(1));
      });
    }

    testWidgets(
      'удаление панели под выбором тегов без возвращения передаёт полученное '
      'ею право ошибки общей поверхности ровно один раз',
      (tester) async {
        final repository = _DelayedPersonalGraphRepository();
        final runtime = await _pumpCatalog(tester, repository, const []);
        final completions = _collectCompletions(runtime);
        await _failSubmissionWithoutFocus(tester, repository);
        expect(find.byKey(_pinnedFailure), findsOneWidget);
        await _FormOverlay.chooser.cover(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

        await _removePanelWithoutReturn(tester);

        await _expectCreationFailureOnAppSurfaceOnce(
          tester,
          runtime,
          completions.single.token,
        );
        expect(repository.commands, hasLength(1));
      },
    );

    testWidgets(
      'удаление перекрытой панели, renderer которой не получал право ошибки, '
      'передаёт его общей поверхности ровно один раз',
      (tester) async {
        final repository = _DelayedPersonalGraphRepository();
        final runtime = await _pumpCatalog(tester, repository, const []);
        final completions = _collectCompletions(runtime);
        await _openPanel(tester);
        await tester.enterText(find.byKey(_editorTitle), 'Намерение');
        await tester.tap(find.byKey(_submit));
        await _pumpUntil(tester, () => repository.commands.length == 1);
        unawaited(
          tester
              .element(find.byType(IntentionEditorPage))
              .router
              .push(TagCatalogRoute()),
        );
        await tester.pumpAndSettle();

        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(_inlineCreationFailure, skipOffstage: false),
          findsNothing,
        );
        expect(
          runtime.commandCoordinator.claimInitiatorFailure(
            completions.single.token,
          ),
          isNotNull,
        );

        await _removePanelWithoutReturn(tester);

        await _expectCreationFailureOnAppSurfaceOnce(
          tester,
          runtime,
          completions.single.token,
        );
        expect(repository.commands, hasLength(1));
      },
    );

    testWidgets(
      'отказ отправки, принятой до ухода, предъявляется над новым открытием '
      'один раз и не меняет и не закрывает его черновик',
      (tester) async {
        final repository = _DelayedPersonalGraphRepository();
        final runtime = await _pumpCatalog(tester, repository, const []);
        final completions = _collectCompletions(runtime);
        await _submitAndLeave(tester, repository, 'Первое');
        await _openPanel(tester);
        await tester.enterText(find.byKey(_editorTitle), 'Второе');
        await tester.pump();

        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        _expectVisibleOverPanel(tester, _appCreationFailure);
        expect(find.byKey(_pinnedFailure), findsNothing);
        expect(_fieldText(tester), 'Второе');
        expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
        expect(
          runtime.commandCoordinator.claimInitiatorFailure(
            completions.single.token,
          ),
          isNull,
        );
        await _closeOperationMessage(tester);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
        await _closeOperationMessage(tester);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
        expect(find.byType(IntentionEditorPage), findsOneWidget);
        expect(_fieldText(tester), 'Второе');
        expect(repository.commands, hasLength(1));
      },
    );

    testWidgets(
      'успех отправки, принятой до ухода, предъявляется над новым открытием '
      'один раз, согласует каталог и не закрывает новую панель',
      (tester) async {
        final repository = _DelayedPersonalGraphRepository();
        await _pumpCatalog(tester, repository, const []);
        await _submitAndLeave(tester, repository, 'Первое');
        await _openPanel(tester);
        await tester.enterText(find.byKey(_editorTitle), 'Второе');
        await tester.pump();

        final created = _intention(title: 'Первое', description: null);
        repository.completeCommand(0, _saved(created, revision: 1));
        await tester.pumpAndSettle();

        _expectVisibleOverPanel(
          tester,
          'Create — “Первое”: Intention created.',
        );
        expect(find.text(created.title), findsOneWidget);
        expect(find.text('Total intentions: 1'), findsOneWidget);
        expect(find.byType(IntentionEditorPage), findsOneWidget);
        expect(_fieldText(tester), 'Второе');
        await _closeOperationMessage(tester);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
        await _closeOperationMessage(tester);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
        expect(find.byType(IntentionEditorPage), findsOneWidget);
        expect(_fieldText(tester), 'Второе');
        expect(repository.commands, hasLength(1));
      },
    );
  });
}

const _editorTitle = ValueKey('intention-editor-title');
const _submit = ValueKey('intention-editor-submit');
const _close = ValueKey('intention-editor-close');
const _chooseTags = ValueKey('intention-editor-choose-tags');
const _pinnedFailure = ValueKey('intention-editor-failure');

/// Закреплённое сообщение панели о её отказе сохранения.
const _inlineCreationFailure = 'The intention couldn’t be created. Try again.';

/// Сообщение общей поверхности о том же отказе после ухода панели.
const _appCreationFailure =
    'Create — “new intention”: The intention couldn’t be created. Try again.';

/// Копии текста, доступные человеку: копия под модальным фоном или
/// непрозрачной страницей нажатий не получает.
Finder _visible(String text) => find.text(text).hitTestable();

/// Все построенные копии текста, в том числе под непрозрачной страницей.
Finder _anywhere(String text) => find.text(text, skipOffstage: false);

String? _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_editorTitle)).controller?.text;

Future<void> _openPanel(WidgetTester tester) async {
  await openQuickCreation(
    tester,
    QuickCreationMode.intention,
    openedPage: find.byType(IntentionEditorPage),
    wait: (tester, finder) =>
        _pumpUntil(tester, () => finder.evaluate().isNotEmpty),
  );
}

List<IntentionCommandCompletion> _collectCompletions(AppRuntime runtime) {
  final completions = <IntentionCommandCompletion>[];
  final subscription = runtime.commandCoordinator.intentionCompletions.listen(
    completions.add,
  );
  addTearDown(subscription.cancel);
  return completions;
}

/// Принимает удаление другого намерения без живого инициатора и завершает его
/// отказом: результат принадлежит только общей поверхности. Возвращает текст
/// её сообщения.
Future<String> _failOtherIntentionDelete(
  WidgetTester tester,
  AppRuntime runtime,
  _DelayedPersonalGraphRepository repository, {
  required String uuid,
  required String title,
}) async {
  final other = _intention(uuid: uuid, title: title, description: null);
  final index = repository.commands.length;
  final accepted = runtime.commandCoordinator.acceptExisting(
    DeleteIntention(other.id),
    presentationTitle: other.title,
  ) as IntentionCommandAccepted;
  runtime.commandCoordinator.releaseInitiatorPresentation(accepted.token);
  await _pumpUntil(tester, () => repository.commands.length == index + 1);
  repository.completeCommand(
    index,
    const ResultFailure(IntentionUnavailableFailure()),
  );
  return 'Delete — “$title”: The intention couldn’t be deleted. Try again.';
}

/// Отправляет черновик панели и получает отказ, пока приложение без фокуса:
/// renderer панели получает право ошибки, но ещё не предъявил её.
Future<void> _failSubmissionWithoutFocus(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
) async {
  await _openPanel(tester);
  await tester.enterText(find.byKey(_editorTitle), 'Намерение');
  await tester.tap(find.byKey(_submit));
  await _pumpUntil(tester, () => repository.commands.length == 1);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  repository.completeCommand(
    0,
    const ResultFailure(IntentionUnavailableFailure()),
  );
  await tester.pumpAndSettle();
  expect(find.text(_inlineCreationFailure), findsOneWidget);
}

/// Отправляет черновик и подтверждает уход во время принятой отправки.
Future<void> _submitAndLeave(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
  String title,
) async {
  await _openPanel(tester);
  await tester.enterText(find.byKey(_editorTitle), title);
  await tester.tap(find.byKey(_submit));
  await _pumpUntil(tester, () => repository.commands.length == 1);
  await tester.tap(find.byKey(_close));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('intention-editor-close-discard')),
  );
  await tester.pumpAndSettle();
  expect(find.byType(IntentionEditorPage), findsNothing);
}

/// Удаляет панель вместе со страницами над ней, не возвращаясь к ней.
Future<void> _removePanelWithoutReturn(WidgetTester tester) async {
  final router = tester
      .element(find.byType(IntentionEditorPage, skipOffstage: false))
      .router;
  router.popUntilRoot();
  await tester.pumpAndSettle();
  expect(find.byType(IntentionEditorPage, skipOffstage: false), findsNothing);
}

/// Общая поверхность предъявляет отказ создания с [token] одним сообщением,
/// а у ушедшей панели не остаётся права на него.
Future<void> _expectCreationFailureOnAppSurfaceOnce(
  WidgetTester tester,
  AppRuntime runtime,
  GraphInitiatorOperationToken token,
) async {
  expect(_visible(_appCreationFailure), findsOneWidget);
  expect(find.byType(SnackBar), findsOneWidget);
  expect(runtime.commandCoordinator.claimInitiatorFailure(token), isNull);
  await _closeOperationMessage(tester);
  expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
  await _closeOperationMessage(tester);
  expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
  expect(tester.takeException(), isNull);
}

/// Сообщение [text] видно поверх панели одной копией и не перекрывает
/// сохранение.
void _expectVisibleOverPanel(WidgetTester tester, String text) {
  expect(_visible(text), findsOneWidget);
  final visible = find.descendant(
    of: find.byType(IntentionEditorPage),
    matching: _visible(text),
  );
  expect(visible, findsOneWidget);
  final message = tester.getRect(
    find.ancestor(of: visible, matching: find.byType(SnackBar)),
  );
  expect(
    message.bottom,
    lessThanOrEqualTo(tester.getRect(find.byKey(_submit)).top),
  );
  expect(find.byKey(_submit).hitTestable(), findsOneWidget);
}

/// Переход, во время которого общая поверхность уже показывает сообщение.
enum _SheetTransition {
  panel('открытие и закрытие панели'),
  confirmation('подтверждение закрытия над панелью'),
  chooser('выбор тегов над панелью'),
  editor('редактор тега над выбором');

  const _SheetTransition(this.description);

  final String description;

  /// Состояние до сообщения: каталог или открытая панель с черновиком.
  Future<void> prepare(WidgetTester tester) async {
    switch (this) {
      case _SheetTransition.panel:
        return;
      case _SheetTransition.confirmation ||
          _SheetTransition.chooser ||
          _SheetTransition.editor:
        await _openPanel(tester);
        await tester.enterText(find.byKey(_editorTitle), 'Черновик');
        await tester.pump();
        switch (this) {
          case _SheetTransition.editor:
            await _FormOverlay.chooser.cover(tester);
          case _SheetTransition.panel ||
              _SheetTransition.confirmation ||
              _SheetTransition.chooser:
            break;
        }
    }
  }

  Future<void> cover(WidgetTester tester) async {
    switch (this) {
      case _SheetTransition.panel:
        await _openPanel(tester);
      case _SheetTransition.confirmation:
        await tester.tap(find.byKey(_close));
        await tester.pumpAndSettle();
        expect(find.text('Discard the draft?'), findsOneWidget);
      case _SheetTransition.chooser:
        // Сообщение временно перекрывает нижний край полей. Из названия
        // переходим через описание к выбору тегов клавиатурой, сохраняя
        // сообщение на экране и его место в очереди.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);
      case _SheetTransition.editor:
        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-editor-name')), findsOneWidget);
    }
  }

  Future<void> uncover(WidgetTester tester) async {
    switch (this) {
      case _SheetTransition.panel:
        await tester.tap(find.byKey(_close));
        await tester.pumpAndSettle();
        expect(find.byType(IntentionEditorPage), findsNothing);
      case _SheetTransition.confirmation:
        await tester.tap(
          find.byKey(const ValueKey('intention-editor-close-continue')),
        );
        await tester.pumpAndSettle();
        expect(_fieldText(tester), 'Черновик');
      case _SheetTransition.chooser:
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(_fieldText(tester), 'Черновик');
      case _SheetTransition.editor:
        await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-editor-name')), findsNothing);
    }
  }
}

/// Временное перекрытие живой панели.
enum _FormOverlay {
  chooser('непрозрачный выбор тегов'),
  editor('непрозрачный редактор тега над выбором'),
  dialog('диалог объяснения готовности');

  const _FormOverlay(this.description);

  final String description;

  Future<void> cover(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser:
        await tester.tap(find.byKey(_chooseTags));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);
      case _FormOverlay.editor:
        await _FormOverlay.chooser.cover(tester);
        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-editor-name')), findsOneWidget);
      case _FormOverlay.dialog:
        await tester.tap(
          find.byKey(const ValueKey('intention-editor-readiness')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('intention-editor-readiness-confirmation')),
          findsOneWidget,
        );
    }
  }

  /// Снимает верхнюю из нескольких перекрывающих страниц, оставляя панель
  /// перекрытой.
  Future<void> uncoverPartly(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser || _FormOverlay.dialog:
        return;
      case _FormOverlay.editor:
        await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);
    }
  }

  Future<void> uncover(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser || _FormOverlay.editor:
        await tester.tap(find.byType(BackButton));
      case _FormOverlay.dialog:
        await tester.tap(
          find.byKey(const ValueKey('intention-editor-readiness-cancel')),
        );
    }
    await tester.pumpAndSettle();
    expect(find.byType(IntentionEditorPage), findsOneWidget);
  }
}

const _operationMessage = ValueKey('graph-operation-message');
const _homeTag = 301;
const _weekendTag = 302;

/// Тег, которого нет в хранилище на момент создания.
const _missingTag = 303;

TagId _storedTag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

int _storedIntentionCount(sqlite.Database raw) =>
    raw.select('SELECT COUNT(*) AS count FROM intentions').single['count']
        as int;

/// Намерения, назначения, отметки избранного и теги хранилища.
Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  for (final table in [
    'intentions',
    'intention_titles_fts',
    'tags',
    'tag_assignments',
    'favorite_intentions',
  ])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

/// Приложение на настоящем адаптере in-memory хранилища с тегами «Дом» и
/// «Выходные».
final class _RealStorageApp {
  _RealStorageApp(this.raw, this.coordinator);

  final sqlite.Database raw;
  final GraphCommandCoordinator coordinator;

  static Future<_RealStorageApp> start(
    WidgetTester tester,
    Locale locale, {
    LocalDatabaseConnectionObserver? observer,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    late sqlite.Database raw;
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () {
        final connection = openInMemoryLocalDatabase(
          setup: (database) => raw = database,
        );
        return switch (observer) {
          null => connection,
          final observer => observeConfiguredLocalDatabaseConnection(
            connection,
            observer,
          ),
        };
      },
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    for (final (number, name) in [
      (_homeTag, 'Дом'),
      (_weekendTag, 'Выходные'),
    ]) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(number),
        name,
      ]);
    }
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(
      tester,
      waitFor: (tester, finder) =>
          _waitForStorage(tester, () => finder.evaluate().isNotEmpty),
    );
    // Пустая выдача каталога загружена из хранилища.
    final emptyCatalog = find.text(
      lookupAppLocalizations(locale).catalogActiveEmpty,
    );
    await _waitForStorage(tester, () => emptyCatalog.evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    return _RealStorageApp(
      raw,
      ready.container.read(graphCommandCoordinatorProvider.notifier),
    );
  }
}

/// Задерживает вставку строки намерения после [hold] до [release]: принятое
/// создание остаётся выполняющимся без подтверждённой записи.
final class _CreationWriteGate extends LocalDatabaseConnectionObserver {
  Completer<void>? _release;
  var isHolding = false;

  void hold() => _release = Completer<void>();

  void release() {
    final release = _release;
    _release = null;
    if (release != null && !release.isCompleted) {
      release.complete();
    }
  }

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    final release = _release;
    if (release == null ||
        statement.operation != LocalDatabaseSqlOperation.insert ||
        !RegExp(
          r'^\s*INSERT\s+INTO\s+"?intentions"?\s',
          caseSensitive: false,
        ).hasMatch(statement.statements.single)) {
      return;
    }
    isHolding = true;
    await release.future;
  }
}

/// Ожидание настоящего хранилища: реальное время для его операций и кадры
/// для интерфейса.
Future<void> _waitForStorage(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

Future<void> _scrollCurrentPageToTop(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  scrollable.position.jumpTo(scrollable.position.minScrollExtent);
  await tester.pump();
}

Future<AppRuntime> _pumpCatalog(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
  List<Intention> intentions,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: InMemoryDiagnosticsSink(),
    repositoryFactory: (_) => repository,
  );
  addTearDown(() async {
    await runtime.shutdown();
    await repository.close();
  });

  await tester.pumpWidget(MainApp(runtime: runtime));
  await openIntentionGraph(
    tester,
    waitFor: (tester, finder) =>
        _pumpUntil(tester, () => finder.evaluate().isNotEmpty),
  );
  await _pumpUntil(tester, () => repository.pageQueries.isNotEmpty);
  repository.completePage(
    0,
    IntentionCatalogFirstPage(
      items: intentions.map(_summary).toList(growable: false),
      totalCount: intentions.length,
      nextCursor: null,
      revision: const _Revision(0),
    ),
  );
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> _openDetails(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
  Intention intention, {
  required int requestIndex,
}) async {
  await tester.tap(find.text(intention.title));
  await _pumpUntil(
    tester,
    () => repository.detailIds.where((id) => id == intention.id).length >= 2,
  );
  repository.emitDetail(requestIndex, intention);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Условие app-level теста не выполнено.');
}

final class _DelayedPersonalGraphRepository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Наблюдение дневного выбора не используется этим тестом.',
      );

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) async => _selectedSnapshot(query);

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => Stream.value(_selectedSnapshot(query));

  SelectedRelationsReadResult _selectedSnapshot(
    SelectedRelationsQuery query,
  ) => SelectedRelationsReadSuccess(
    GraphSnapshot(
      revision: _Revision(_revisions[query.intentionId] ?? 0),
      value: SelectedRelationsSnapshot(
        query: query,
        entries: {
          for (final id in query.relationIds)
            id: relation == null || relation!.relation.id != id
                ? SelectedRelationMissing(id)
                : relation!.relation.sourceIntentionId != query.intentionId &&
                      relation!.relation.relatedIntentionId != query.intentionId
                ? SelectedRelationNoLongerBlocking(id)
                : SelectedRelationPresent(
                    LongTermRelationDetails(
                      relation: relation!.relation,
                      source: relation!.source,
                      related: relation!.related,
                      description: null,
                    ),
                  ),
        },
      ),
    ),
  );

  _DelayedPersonalGraphRepository({this.relation});

  final LongTermRelationSummary? relation;

  RelationCounts _countsFor(IntentionId id) => RelationCounts(
    activeNeedIncoming: relation?.relation.relatedIntentionId == id ? 1 : 0,
    activeNeedOutgoing: relation?.relation.sourceIntentionId == id ? 1 : 0,
    activeCanIncoming: 0,
    activeCanOutgoing: 0,
    archivedNeedIncoming: 0,
    archivedNeedOutgoing: 0,
    archivedCanIncoming: 0,
    archivedCanOutgoing: 0,
  );
  final pageQueries = <IntentionCatalogQuery>[];
  final detailIds = <IntentionId>[];
  final detailRequests =
      <StreamController<Result<GraphSnapshot<IntentionDetails?>>>>[];
  final commands = <IntentionCommand>[];
  final blockingRelationsCommands = <DeleteBlockingRelations>[];
  final _pages = <Completer<Result<IntentionCatalogPage>>>[];
  final _commands =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  final _blockingRelationsRequests =
      <Completer<DeleteBlockingRelationsResult>>[];
  final _revisions = <IntentionId, int>{};

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    pageQueries.add(query);
    final request = Completer<Result<IntentionCatalogPage>>();
    _pages.add(request);
    return request.future;
  }

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => Future.value(
    ResultSuccess(
      GraphSnapshot(
        value: _countsFor(intentionId),
        revision: _Revision(_revisions[intentionId] ?? 0),
      ),
    ),
  );

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => Future.value(
    GraphResultSuccess(
      RelationGroupFirstPage(
        items:
            relation != null &&
                query.intentionId == relation!.relation.sourceIntentionId &&
                query.group ==
                    const LongTermRelationGroup(
                      scope: RelationScope.active,
                      type: LongTermRelationType.need,
                      direction: RelationDirection.outgoing,
                    )
            ? [relation!]
            : const [],
        counts: _countsFor(query.intentionId),
        nextCursor: null,
        revision: _Revision(_revisions[query.intentionId] ?? 0),
      ),
    ),
  );

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      Stream.value(
        GraphResultSuccess(
          GraphSnapshot(
            value: relation == null || relation!.relation.id != id
                ? null
                : LongTermRelationDetails(
                    relation: relation!.relation,
                    source: relation!.source,
                    related: relation!.related,
                    description: null,
                  ),
            revision: const _Revision(0),
          ),
        ),
      );

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    final request =
        StreamController<Result<GraphSnapshot<IntentionDetails?>>>();
    detailIds.add(id);
    detailRequests.add(request);
    return request.stream;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is DeleteBlockingRelations) {
      blockingRelationsCommands.add(command as DeleteBlockingRelations);
      final request = Completer<DeleteBlockingRelationsResult>();
      _blockingRelationsRequests.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    if (command is! IntentionCommand) {
      throw UnsupportedError('Команды связей не используются в этих тестах.');
    }
    return await _executeIntention(command as IntentionCommand)
        as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) {
    commands.add(command);
    final request =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _commands.add(request);
    return request.future;
  }

  void completePage(int index, IntentionCatalogPage page) {
    _pages[index].complete(ResultSuccess(page));
  }

  void emitDetail(int index, Intention intention) {
    _revisions[intention.id] = index;
    for (
      var requestIndex = 0;
      requestIndex < detailRequests.length;
      requestIndex += 1
    ) {
      if (detailIds[requestIndex] == intention.id) {
        detailRequests[requestIndex].add(
          ResultSuccess(
            GraphSnapshot(
              value: IntentionDetails(
                intention: intention,
                relationCounts: _countsFor(intention.id),
                favoriteMark: FavoriteMark.notFavorite,
              ),
              revision: _Revision(index),
            ),
          ),
        );
      }
    }
  }

  void completeCommand(
    int index,
    Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
  ) {
    _commands[index].complete(result);
  }

  void completeBlockingRelationsCommand(
    int index,
    DeleteBlockingRelationsResult result,
  ) => _blockingRelationsRequests[index].complete(result);

  Future<void> close() async {
    for (final request in detailRequests) {
      if (!request.isClosed) await request.close();
    }
  }
}

Intention _intention({
  String uuid = '018f0000-0000-7000-8000-000000000001',
  required String title,
  required String? description,
}) {
  final id = switch (IntentionId.decode(uuid)) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный fixture ID.',
    ),
  };
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 1));
  return Intention(
    id: id,
    title: title,
    description: description,
    readiness: IntentionReadiness.notReady,
    archiveState: IntentionArchiveState.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Intention _copyIntention(
  Intention source, {
  String? title,
  String? description,
  IntentionReadiness? readiness,
  IntentionArchiveState? archiveState,
  required int updatedDay,
}) => Intention(
  id: source.id,
  title: title ?? source.title,
  description: description ?? source.description,
  readiness: readiness ?? source.readiness,
  archiveState: archiveState ?? source.archiveState,
  createdAt: source.createdAt,
  updatedAt: IntentionTimestamp(DateTime.utc(2026, 1, updatedDay)),
);

IntentionSummary _summary(Intention intention) => IntentionSummary(
  id: intention.id,
  title: intention.title,
  hasDescription: intention.description != null,
  readiness: intention.readiness,
  archiveState: intention.archiveState,
  activeRelationCount: 0,
  createdAt: intention.createdAt,
  updatedAt: intention.updatedAt,
  favoriteMark: FavoriteMark.notFavorite,
);

final _relationId = switch (LongTermRelationId.decode(
  '018f0000-0000-7000-8000-000000000003',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  InvalidLongTermRelationIdDecoding() => throw StateError(
    'Некорректный fixture связи.',
  ),
};

LongTermRelationSummary _relationSummary(Intention source, Intention related) =>
    LongTermRelationSummary(
      relation: LongTermRelation(
        id: _relationId,
        sourceIntentionId: source.id,
        relatedIntentionId: related.id,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        scope: RelationScope.active,
        creationSequence: RelationCreationSequence(1),
      ),
      source: RelationParticipantSummary(
        id: source.id,
        title: source.title,
        archiveState: source.archiveState,
        activeRelationCount: 1,
      ),
      related: RelationParticipantSummary(
        id: related.id,
        title: related.title,
        archiveState: related.archiveState,
        activeRelationCount: 1,
      ),
      hasDescription: false,
    );

Result<ConfirmedGraphResult<IntentionCommandSuccess>> _saved(
  Intention intention, {
  Intention? before,
  required int revision,
}) {
  final after = _Snapshot(intention);
  final mutation = before == null
      ? IntentionCatalogCreated(revision: _Revision(revision), entry: after)
      : IntentionCatalogUpdated(
          revision: _Revision(revision),
          before: _Snapshot(before),
          after: after,
        );
  final value = IntentionSaved(intention, catalogMutation: mutation);
  return ResultSuccess(
    ConfirmedGraphResult(revision: _Revision(revision), value: value),
  );
}

Result<ConfirmedGraphResult<IntentionCommandSuccess>> _deleted(
  Intention intention, {
  required int revision,
}) {
  final value = IntentionDeleted(
    intention.id,
    catalogMutation: IntentionCatalogDeleted(
      revision: _Revision(revision),
      entry: _Snapshot(intention),
    ),
  );
  return ResultSuccess(
    ConfirmedGraphResult(revision: _Revision(revision), value: value),
  );
}

final class _Snapshot implements IntentionCatalogEntrySnapshot {
  _Snapshot(Intention intention) : summary = _summary(intention);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

final class _Revision implements GraphRevision {
  const _Revision(this.sequence);

  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _Revision) {
      return GraphRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return GraphRevisionOrder.older;
    if (comparison > 0) return GraphRevisionOrder.newer;
    return GraphRevisionOrder.same;
  }
}
