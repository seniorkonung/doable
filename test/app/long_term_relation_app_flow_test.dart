import 'dart:ui' show CheckedState, Tristate;

import 'package:auto_route/auto_route.dart';

import 'package:doable/main.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as catalog_page;
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import '../support/app_root_pages.dart';
import '../support/graph_seed.dart';
import '../support/quick_creation.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

void main() {
  testWidgets(
    'отдельно подтверждает удаление освобождённого архивного намерения',
    (tester) async {
      await _prepareAppSurface(tester);
      tester.binding.platformDispatcher.localesTestValue = [
        const Locale('ru', 'RU'),
      ];

      final semantics = tester.ensureSemantics();
      final database = (await tester.runAsync(
        LocalDatabaseHarness.fileBacked,
      ))!;
      await _seedBlockingFlow(database);
      final runtimes = <AppRuntime>[];
      final runtime = _fileRuntime(
        database,
        diagnostics: InMemoryDiagnosticsSink(),
      )..also(runtimes.add);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final activeRuntime in runtimes.reversed) {
          await activeRuntime.shutdown();
        }
        await database.dispose();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _pumpUntilFound);
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('catalog-scope-control')),
      );
      final loc = AppLocalizations.of(
        tester.element(find.byKey(const ValueKey('catalog-scope-control'))),
      );
      await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(loc.catalogScopeArchived).last);
      await _pumpUntilFound(tester, find.text(_blockingOwnerTitle));
      await _openIntention(tester, _blockingOwnerTitle);
      expect(find.text(loc.relationNeighborhoodArchivedTotal(2)), findsWidgets);

      await _deleteCurrentIntention(tester);
      final showBlocking = find.byKey(
        const ValueKey('intention-details-show-blocking-relations'),
      );
      await _pumpUntilFound(tester, showBlocking);
      await _ensureVisible(tester, showBlocking);
      await tester.tap(showBlocking);
      await _selectBlockingRelation(tester, 100);
      await _scrollDetailsToTop(tester);
      expect(
        find.text(loc.relationNeighborhoodSelectedCount(1)),
        findsOneWidget,
      );
      await _reviewBlockingSelection(tester);
      expect(
        find.text(loc.blockingRelationsConfirmationCount(1)),
        findsOneWidget,
      );
      final confirm = find.byKey(
        const ValueKey('blocking-relations-confirm-delete'),
      );
      await tester.scrollUntilVisible(
        confirm,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.getSemantics(confirm).label, isNotEmpty);
      await tester.tap(confirm);
      await _pumpUntilFound(
        tester,
        find.textContaining(loc.blockingRelationsDeleted),
      );
      expect(
        find.byKey(const ValueKey('intention-details-title')),
        findsOneWidget,
      );
      await _dismissOperationMessage(tester);
      await _scrollDetailsToTop(tester);
      expect(
        find.text(loc.relationNeighborhoodSelectedCount(0)),
        findsOneWidget,
      );
      expect(find.text(loc.relationNeighborhoodArchivedTotal(1)), findsWidgets);
      final can = find.byKey(const ValueKey('relation-neighborhood-type-can'));
      await _ensureVisible(tester, can);
      await tester.tap(can);
      final incoming = find.byKey(
        const ValueKey('relation-neighborhood-direction-incoming'),
      );
      await _ensureVisible(tester, incoming);
      await tester.tap(incoming);
      await _selectBlockingRelation(tester, 200);
      final secondSelect = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${_blockingRelationId(200).toCanonicalString()}',
        ),
      );
      expect(
        tester.getSemantics(secondSelect).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      await _scrollDetailsToTop(tester);
      expect(
        find.text(loc.relationNeighborhoodSelectedCount(1)),
        findsOneWidget,
      );
      await _reviewBlockingSelection(tester);
      expect(
        find.text(loc.blockingRelationsConfirmationCount(1)),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        confirm,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(confirm);
      await _pumpUntilFound(
        tester,
        find.textContaining(loc.blockingRelationsDeleted),
      );
      await _dismissOperationMessage(tester);
      await _scrollDetailsToTop(tester);
      expect(
        find.text(loc.relationNeighborhoodSelectedCount(0)),
        findsOneWidget,
      );

      final delete = find.byKey(const ValueKey('intention-details-delete'));
      await _ensureVisible(tester, delete);
      await tester.tap(delete);
      final confirmIntention = find.byKey(
        const ValueKey('intention-details-confirm-delete'),
      );
      await _pumpUntilFound(tester, confirmIntention);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(loc.detailsCancelEditAction),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('intention-details-title')),
        findsOneWidget,
      );
      await _deleteCurrentIntention(tester);
      await _pumpUntilFound(
        tester,
        find.byType(catalog_page.IntentionCatalogPage),
      );
      expect(find.text(_blockingOwnerTitle), findsNothing);
      semantics.dispose();

      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      runtimes.remove(runtime);
      final persisted = await database.openReadyDatabase();
      final intentions = (await persisted.select(persisted.intentions).get())
          .map((row) => row.id)
          .toSet();
      expect(
        intentions,
        isNot(contains(_blockingIntentionId(1).toCanonicalString())),
      );
      expect(
        intentions,
        contains(_blockingIntentionId(100).toCanonicalString()),
      );
      expect(
        intentions,
        contains(_blockingIntentionId(200).toCanonicalString()),
      );
      expect(
        await persisted.select(persisted.longTermRelations).get(),
        isEmpty,
      );
      await database.closePersistenceObjectGraph();
    },
  );

  testWidgets(
    'создаёт связь, согласует соседство и сохраняет поток после открытия файла',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final database = (await tester.runAsync(
        LocalDatabaseHarness.fileBacked,
      ))!;
      final diagnostics = InMemoryDiagnosticsSink();
      final runtimes = <AppRuntime>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final runtime in runtimes.reversed) {
          await runtime.shutdown();
        }
        await database.dispose();
      });

      final firstRuntime = _fileRuntime(database, diagnostics: diagnostics)
        ..also(runtimes.add);
      await tester.pumpWidget(MainApp(runtime: firstRuntime));
      await openIntentionGraph(tester, waitFor: _pumpUntilFound);
      await _pumpUntilFound(
        tester,
        find.byType(catalog_page.IntentionCatalogPage),
      );

      await _createIntention(
        tester,
        title: 'Беречь здоровье',
        description: '  Исходное описание\n',
      );
      await _dismissOperationMessage(tester);
      await _createIntention(
        tester,
        title: 'Много ходить',
        description: 'Описание участника',
      );
      await _dismissOperationMessage(tester);
      const sameTitle = 'Одинаковое намерение';
      await _createIntention(
        tester,
        title: sameTitle,
        description: 'Первый одноимённый участник',
      );
      await _dismissOperationMessage(tester);
      await _createIntention(
        tester,
        title: sameTitle,
        description: 'Второй одноимённый участник',
      );
      await _dismissOperationMessage(tester);

      expect(
        tester.getSemantics(quickCreationAction()),
        isSemantics(
          label: 'Quick create, New intention',
          hint: 'Touch and hold to change mode',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
          onLongPressHint: 'Change mode',
          customActions: [CustomSemanticsAction(label: 'Change mode')],
        ),
      );
      final catalogRow = tester.getSemantics(
        find.ancestor(
          of: find.text('Беречь здоровье'),
          matching: find.byType(IntentionSummaryView),
        ),
      );
      expect(catalogRow.label, contains('Беречь здоровье'));

      await _openIntention(tester, 'Беречь здоровье');
      await _createNeedRelation(
        tester,
        relatedTitle: 'Много ходить',
        description: '  Детали связи\n🙂  ',
        verifyFormSemantics: true,
      );
      await _dismissOperationMessage(tester);

      const initialPhrase = 'To Беречь здоровье, you need Много ходить';
      await _pumpUntilFound(tester, find.text(initialPhrase));
      expect(find.text('Active relations: 1'), findsWidgets);
      final groupControl = tester.getSemantics(
        find.byKey(
          const ValueKey('relation-neighborhood-group-active-need-outgoing'),
        ),
      );
      expect(groupControl.label, contains('Outgoing: 1'));
      expect(
        groupControl.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.text(initialPhrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-description')),
      );
      expect(find.text('  Детали связи\n🙂  '), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
      final participant = tester.getSemantics(
        find.byKey(const ValueKey('relation-details-related-participant')),
      );
      expect(participant.label, contains('Много ходить'));
      expect(
        participant.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey('relation-details-related-participant')),
      );
      await _pumpUntilDetailsTitle(tester, 'Много ходить');
      await _ensureVisible(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-direction-incoming')),
      );
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-direction-incoming')),
      );
      await _pumpUntilFound(tester, find.text(initialPhrase));

      await tester.tap(find.text(initialPhrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-source-participant')),
      );
      await tester.tap(
        find.byKey(const ValueKey('relation-details-source-participant')),
      );
      await _pumpUntilDetailsTitle(tester, 'Беречь здоровье');

      await _renameCurrentIntention(tester, 'Укреплять здоровье');
      const renamedPhrase = 'To Укреплять здоровье, you need Много ходить';
      await _pumpUntilFound(tester, find.text(renamedPhrase));

      await _ensureVisible(
        tester,
        find.byKey(const ValueKey('intention-details-archive')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-archive')));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('intention-details-restore')),
      );
      await _dismissOperationMessage(tester);

      await _ensureVisible(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-scope-archived')),
      );
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-scope-archived')),
      );
      await _pumpUntilFound(tester, find.text(renamedPhrase));

      await _ensureVisible(
        tester,
        find.byKey(const ValueKey('intention-details-restore')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-restore')));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('intention-details-archive')),
      );
      await _dismissOperationMessage(tester);
      expect(find.text(renamedPhrase), findsOneWidget);
      expect(find.text('Archived relations: 1'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await firstRuntime.shutdown();
      runtimes.remove(firstRuntime);

      final reopenedRuntime = _fileRuntime(database, diagnostics: diagnostics)
        ..also(runtimes.add);
      await tester.pumpWidget(MainApp(runtime: reopenedRuntime));
      await openIntentionGraph(tester, waitFor: _pumpUntilFound);
      await _pumpUntilFound(tester, find.text('Укреплять здоровье'));
      expect(find.text('Много ходить'), findsOneWidget);

      await _openIntention(tester, 'Укреплять здоровье');
      await _ensureVisible(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-scope-archived')),
      );
      await tester.tap(
        find.byKey(const ValueKey('relation-neighborhood-scope-archived')),
      );
      await _pumpUntilFound(tester, find.text(renamedPhrase));
      await tester.tap(find.text(renamedPhrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-description')),
      );
      expect(find.text('  Детали связи\n🙂  '), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('relation-details-scope')))
            .data,
        'Archived relation',
      );

      await tester.tap(
        find.byKey(const ValueKey('relation-details-source-participant')),
      );
      await _pumpUntilDetailsTitle(tester, 'Укреплять здоровье');
      await _createNeedRelation(
        tester,
        relatedTitle: 'Много ходить',
        description: 'Этот текст не должен заменять сохранённый',
        expectPairConflict: true,
      );
      expect(
        find.text(
          'A relation with this direction already exists between the selected intentions.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      expect(
        find.byKey(const ValueKey('relation-editor-open-existing')),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('relation-editor-failure')))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );

      const conflictingDraft = 'Этот текст не должен заменять сохранённый';
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('relation-editor-description')),
            )
            .controller
            ?.text,
        conflictingDraft,
      );

      await tester.tap(
        find.byKey(const ValueKey('relation-editor-open-existing')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-edit-relation')),
      );

      const lifecycleDescription = '  Литеральный текст\n🧭  ';
      const lifecyclePhrase =
          'To Одинаковое намерение, you can Одинаковое намерение';
      await _editRelation(
        tester,
        sourceTitle: sameTitle,
        relatedTitle: sameTitle,
        description: lifecycleDescription,
      );
      await _dismissOperationMessage(tester);
      expect(_textByKey(tester, 'relation-details-phrase'), lifecyclePhrase);
      expect(_textByKey(tester, 'relation-details-type'), 'Can');
      expect(_textByKey(tester, 'relation-details-priority'), 'P4');
      expect(
        _textByKey(tester, 'relation-details-description'),
        lifecycleDescription,
      );
      expect(_textByKey(tester, 'relation-details-scope'), 'Archived relation');

      await _restoreCurrentRelation(tester);
      await _dismissOperationMessage(tester);
      await _archiveCurrentRelation(tester);
      await _dismissOperationMessage(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await reopenedRuntime.shutdown();
      runtimes.remove(reopenedRuntime);

      final lifecycleRuntime = _fileRuntime(database, diagnostics: diagnostics)
        ..also(runtimes.add);
      await tester.pumpWidget(MainApp(runtime: lifecycleRuntime));
      await openIntentionGraph(tester, waitFor: _pumpUntilFound);
      await _pumpUntilFound(tester, find.text(sameTitle));
      await _openArchivedCanRelation(
        tester,
        participantTitle: sameTitle,
        phrase: lifecyclePhrase,
      );
      expect(
        _textByKey(tester, 'relation-details-description'),
        lifecycleDescription,
      );
      expect(_textByKey(tester, 'relation-details-priority'), 'P4');

      await _restoreCurrentRelation(tester);
      await _dismissOperationMessage(tester);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-source-participant')),
      );
      await _pumpUntilDetailsTitle(tester, sameTitle);

      await _deleteCurrentIntention(tester);
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('intention-details-state-change-failure')),
      );
      expect(
        find.textContaining('relations still block deletion'),
        findsOneWidget,
      );
      final showBlocking = find.byKey(
        const ValueKey('intention-details-show-blocking-relations'),
      );
      await _ensureVisible(tester, showBlocking);
      await tester.tap(showBlocking);
      await _tapWhenFound(tester, find.text(lifecyclePhrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-delete-relation')),
      );

      await _deleteCurrentRelation(tester);
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await _dismissOperationMessage(tester);
      expect(find.text(lifecyclePhrase), findsNothing);

      await _deleteCurrentIntention(tester);
      await _pumpUntilAbsent(
        tester,
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await _dismissOperationMessage(tester);
      await _returnToCatalog(tester);
      await _pumpUntilFound(tester, find.text(sameTitle));
      expect(
        find.ancestor(
          of: find.text(sameTitle),
          matching: find.byType(IntentionSummaryView),
        ),
        findsOneWidget,
      );

      final successfulRelationCommands = diagnostics.events
          .whereType<LongTermRelationCommandDiagnosticsEvent>()
          .where((event) => event.status is DiagnosticsSucceeded)
          .map((event) => event.commandType)
          .toSet();
      expect(
        successfulRelationCommands,
        containsAll(const {
          LongTermRelationCommandDiagnosticsType.create,
          LongTermRelationCommandDiagnosticsType.update,
          LongTermRelationCommandDiagnosticsType.archive,
          LongTermRelationCommandDiagnosticsType.restore,
          LongTermRelationCommandDiagnosticsType.delete,
        }),
      );
      semantics.dispose();
    },
  );
}

const _blockingOwnerTitle = 'Освободить намерение';

Future<void> _seedBlockingFlow(LocalDatabaseHarness harness) async {
  final database = await harness.openReadyDatabase();
  final owner = _blockingIntentionId(1).toCanonicalString();
  await seedGraph(
    database,
    () => database.batch((batch) {
      batch.insert(
        database.intentions,
        IntentionsCompanion.insert(
          id: owner,
          title: _blockingOwnerTitle,
          createdAt: 3000000,
          updatedAt: 3000000,
          isArchived: const Value(true),
        ),
      );
      final neighbor = _blockingIntentionId(100).toCanonicalString();
      batch.insert(
        database.intentions,
        IntentionsCompanion.insert(
          id: neighbor,
          title: 'Сосед 100',
          createdAt: 1000100,
          updatedAt: 1000100,
        ),
      );
      batch.insert(
        database.longTermRelations,
        LongTermRelationsCompanion.insert(
          id: _blockingRelationId(100).toCanonicalString(),
          sourceIntentionId: owner,
          relatedIntentionId: neighbor,
          type: 'need',
          priority: 2,
          isArchived: const Value(true),
        ),
      );
      final incoming = _blockingIntentionId(200).toCanonicalString();
      batch.insert(
        database.intentions,
        IntentionsCompanion.insert(
          id: incoming,
          title: 'Встречный сосед',
          createdAt: 1000200,
          updatedAt: 1000200,
        ),
      );
      batch.insert(
        database.longTermRelations,
        LongTermRelationsCompanion.insert(
          id: _blockingRelationId(200).toCanonicalString(),
          sourceIntentionId: incoming,
          relatedIntentionId: owner,
          type: 'can',
          priority: 2,
          isArchived: const Value(true),
        ),
      );
    }),
  );
  await harness.closePersistenceObjectGraph();
}

IntentionId _blockingIntentionId(int number) =>
    switch (IntentionId.decode(_blockingUuid(number))) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw StateError('Недопустимый ID.'),
    };

LongTermRelationId _blockingRelationId(int number) =>
    switch (LongTermRelationId.decode(_blockingUuid(1000 + number))) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Недопустимый ID.',
      ),
    };

String _blockingUuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toString().padLeft(12, '0')}';

Future<void> _selectBlockingRelation(WidgetTester tester, int number) async {
  final select = find.byKey(
    ValueKey(
      'relation-neighborhood-select-${_blockingRelationId(number).toCanonicalString()}',
    ),
  );
  for (var attempt = 0; attempt < 100 && select.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
  }
  await _pumpUntilFound(tester, select);
  await _ensureVisible(tester, select);
  await tester.tap(select);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Future<void> _reviewBlockingSelection(WidgetTester tester) async {
  final review = find.byKey(const ValueKey('blocking-relations-review'));
  await _ensureVisible(tester, review);
  await tester.tap(review);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('blocking-relations-confirm-list')),
  );
}

Future<void> _scrollDetailsToTop(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, 20000));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Future<void> _prepareAppSurface(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

AppRuntime _fileRuntime(
  LocalDatabaseHarness database, {
  required InMemoryDiagnosticsSink diagnostics,
}) => AppRuntime(
  quickCreationModeStore: InMemoryQuickCreationModeStore(),
  connectionFactory: () => openFileBackedLocalDatabase(database.databaseFile),
  diagnosticsSink: diagnostics,
);

Future<void> _createIntention(
  WidgetTester tester, {
  required String title,
  required String description,
}) async {
  await openQuickCreation(
    tester,
    QuickCreationMode.intention,
    openedPage: find.byKey(const ValueKey('intention-creation-sheet')),
    wait: _pumpUntilFound,
  );
  await tester.enterText(
    find.byKey(const ValueKey('intention-editor-title')),
    title,
  );
  await tester.enterText(
    find.byKey(const ValueKey('intention-editor-description')),
    description,
  );
  // Панель въезжает снизу: отправку можно нажать, когда она на экране.
  final submit = find.byKey(const ValueKey('intention-editor-submit'));
  await _pumpUntilFound(tester, submit.hitTestable());
  final router = tester.element(submit).router;
  await tester.tap(submit);
  await _pumpUntilDetailsTitle(tester, title);
  await returnToIntentionGraphAfterCreation(
    tester,
    router,
    waitFor: _pumpUntilFound,
  );
}

Future<void> _openIntention(
  WidgetTester tester,
  String title, {
  bool settle = true,
}) async {
  final intention = find.text(title).first;
  await tester.ensureVisible(intention);
  if (settle) {
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
  } else {
    await tester.pump();
  }
  await tester.tap(intention);
  await _pumpUntilDetailsTitle(tester, title, settle: settle);
}

Future<void> _pumpUntilDetailsTitle(
  WidgetTester tester,
  String title, {
  bool settle = true,
}) async {
  final titleFinder = find.byKey(const ValueKey('intention-details-title'));
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    final hasExpectedTitle = titleFinder.evaluate().any((element) {
      final widget = element.widget;
      return widget is Text && widget.data == title;
    });
    if (hasExpectedTitle) {
      if (settle) {
        await tester.pumpAndSettle(const Duration(milliseconds: 1));
      } else {
        await tester.pump();
      }
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Подробный просмотр не показал намерение «$title».');
}

Future<void> _createNeedRelation(
  WidgetTester tester, {
  required String relatedTitle,
  required String description,
  bool expectPairConflict = false,
  bool waitForTerminalOutcome = true,
  bool verifyFormSemantics = false,
}) async {
  final create = find.byKey(
    const ValueKey('relation-neighborhood-create-relation'),
  );
  await _ensureVisible(tester, create);
  await tester.tap(create);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-editor-select-related')),
  );

  await tester.tap(
    find.byKey(const ValueKey('relation-editor-select-related')),
  );
  await _pumpUntilFound(tester, find.text(relatedTitle));
  final related = find.text(relatedTitle);
  await _ensureVisible(tester, related);
  await tester.tap(related);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-editor-type-need')),
  );

  final type = find.byKey(const ValueKey('relation-editor-type-need'));
  await _ensureVisible(tester, type);
  await tester.tap(type);
  await tester.pump();
  if (verifyFormSemantics) {
    final typeSemantics = tester.getSemantics(type);
    expect(typeSemantics.label, contains('Need'));
    expect(typeSemantics.flagsCollection.isSelected, Tristate.isTrue);
  }
  final priority = find.byKey(const ValueKey('relation-editor-priority-p2'));
  await _ensureVisible(tester, priority);
  await tester.tap(priority);
  await tester.enterText(
    find.byKey(const ValueKey('relation-editor-description')),
    description,
  );
  final submit = find.byKey(const ValueKey('relation-editor-submit'));
  await _ensureVisible(tester, submit);
  await tester.tap(submit);
  if (!waitForTerminalOutcome) {
    await tester.pump();
    return;
  }
  if (expectPairConflict) {
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('relation-editor-failure')),
    );
    return;
  }
  await _pumpUntilAbsent(tester, submit);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-details-edit-relation')),
  );
  expect(find.text(description), findsOneWidget);
  // Созданная связь заменяет форму; возврат ведёт к исходному намерению.
  await tester.pageBack();
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-neighborhood-summary')),
  );
}

Future<void> _editRelation(
  WidgetTester tester, {
  required String sourceTitle,
  required String relatedTitle,
  required String description,
}) async {
  final edit = find.byKey(const ValueKey('relation-details-edit-relation'));
  await _ensureVisible(tester, edit);
  await tester.tap(edit);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-editor-change-source')),
  );

  await _selectParticipant(
    tester,
    actionKey: 'relation-editor-change-source',
    title: sourceTitle,
  );
  await _selectParticipant(
    tester,
    actionKey: 'relation-editor-change-related',
    title: relatedTitle,
  );

  final type = find.byKey(const ValueKey('relation-editor-type-can'));
  await _ensureVisible(tester, type);
  await tester.tap(type);
  final priority = find.byKey(const ValueKey('relation-editor-priority-p4'));
  await _ensureVisible(tester, priority);
  await tester.tap(priority);
  await tester.enterText(
    find.byKey(const ValueKey('relation-editor-description')),
    description,
  );

  final submit = find.byKey(const ValueKey('relation-editor-submit'));
  await _ensureVisible(tester, submit);
  await tester.tap(submit);
  await _pumpUntilAbsent(tester, submit);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-details-phrase')),
  );
}

Future<void> _selectParticipant(
  WidgetTester tester, {
  required String actionKey,
  required String title,
}) async {
  final action = find.byKey(ValueKey(actionKey));
  await _ensureVisible(tester, action);
  await tester.tap(action);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('participant-picker-filter')),
  );

  final matchingTitles = find.text(title);
  await _pumpUntilFound(tester, matchingTitles);
  final selected = matchingTitles.first;
  await _ensureVisible(tester, selected);
  await tester.tap(selected);
  await _pumpUntilFound(tester, find.byKey(ValueKey(actionKey)));
}

Future<void> _archiveCurrentRelation(WidgetTester tester) async {
  final archive = find.byKey(
    const ValueKey('relation-details-archive-relation'),
  );
  await _ensureVisible(tester, archive);
  await tester.tap(archive);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-details-restore-relation')),
  );
}

Future<void> _restoreCurrentRelation(WidgetTester tester) async {
  final restore = find.byKey(
    const ValueKey('relation-details-restore-relation'),
  );
  await _ensureVisible(tester, restore);
  await tester.tap(restore);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-details-archive-relation')),
  );
}

Future<void> _openArchivedCanRelation(
  WidgetTester tester, {
  required String participantTitle,
  required String phrase,
}) async {
  await _openIntention(tester, participantTitle);
  final archived = find.byKey(
    const ValueKey('relation-neighborhood-scope-archived'),
  );
  await _ensureVisible(tester, archived);
  await tester.tap(archived);
  final can = find.byKey(const ValueKey('relation-neighborhood-type-can'));
  await _ensureVisible(tester, can);
  await tester.tap(can);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));

  final outgoing = find.byKey(
    const ValueKey('relation-neighborhood-direction-outgoing'),
  );
  await _ensureVisible(tester, outgoing);
  final outgoingLabel = tester.getSemantics(outgoing).label;
  if (!outgoingLabel.contains('Outgoing: 1')) {
    final incoming = find.byKey(
      const ValueKey('relation-neighborhood-direction-incoming'),
    );
    await _ensureVisible(tester, incoming);
    await tester.tap(incoming);
  }

  await _tapWhenFound(tester, find.text(phrase));
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-details-description')),
  );
}

Future<void> _deleteCurrentRelation(WidgetTester tester) async {
  final delete = find.byKey(const ValueKey('relation-details-delete-relation'));
  await _ensureVisible(tester, delete);
  await tester.tap(delete);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('relation-details-confirm-delete')),
  );
  await tester.tap(
    find.byKey(const ValueKey('relation-details-confirm-delete')),
  );
  await _pumpUntilAbsent(tester, delete);
}

Future<void> _deleteCurrentIntention(WidgetTester tester) async {
  final delete = find.byKey(const ValueKey('intention-details-delete'));
  await _ensureVisible(tester, delete);
  await tester.tap(delete);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('intention-details-confirm-delete')),
  );
  await tester.tap(
    find.byKey(const ValueKey('intention-details-confirm-delete')),
  );
}

Future<void> _returnToCatalog(WidgetTester tester) async {
  final catalog = find.byType(catalog_page.IntentionCatalogPage);
  for (var attempt = 0; attempt < 4; attempt += 1) {
    if (catalog.evaluate().isNotEmpty) {
      return;
    }
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
  }
  fail('App-level поток не вернулся в каталог после удаления намерения.');
}

Future<void> _renameCurrentIntention(WidgetTester tester, String title) async {
  final edit = find.byKey(const ValueKey('intention-details-edit'));
  await _ensureVisible(tester, edit);
  await tester.tap(edit);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('intention-details-edit-title')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('intention-details-edit-title')),
    title,
  );
  final submit = find.byKey(const ValueKey('intention-details-edit-submit'));
  await _ensureVisible(tester, submit);
  await tester.tap(submit);
  await _pumpUntilDetailsTitle(tester, title);
  await _dismissOperationMessage(tester);
}

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Future<void> _dismissOperationMessage(WidgetTester tester) async {
  await tester.pumpAndSettle();
  if (find
      .byKey(const ValueKey('graph-operation-message'))
      .evaluate()
      .isEmpty) {
    return;
  }
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 1000,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('App-level поток не показал ожидаемый элемент: $finder');
}

Future<void> _pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  int attempts = 1000,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (finder.evaluate().isEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('App-level поток не закрыл ожидаемый элемент: $finder');
}

Future<void> _tapWhenFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 1000,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('App-level поток не позволил выбрать ожидаемый элемент: $finder');
}

String _textByKey(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

extension<T> on T {
  T also(void Function(T value) action) {
    action(this);
    return this;
  }
}
