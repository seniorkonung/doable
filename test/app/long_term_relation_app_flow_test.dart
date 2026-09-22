import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

void main() {
  testWidgets(
    'создаёт связь, согласует соседство и сохраняет поток после открытия файла',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
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
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('catalog-create-intention')),
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

      expect(find.bySemanticsLabel('Create intention'), findsOneWidget);
      final catalogRow = tester.getSemantics(
        find.ancestor(
          of: find.text('Беречь здоровье'),
          matching: find.byType(IntentionSummaryView),
        ),
      );
      expect(catalogRow.label, contains('Беречь здоровье'));
      expect(catalogRow.label, contains('Active relations: 0'));

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
      expect(participant.label, contains('Active relations: 1'));
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

      tester.binding.platformDispatcher.localesTestValue = const [
        Locale('ru', 'RU'),
      ];
      await tester.pumpAndSettle();
      expect(
        _textByKey(tester, 'relation-details-phrase'),
        'Чтобы Укреплять здоровье, нужно Много ходить',
      );
      expect(
        _textByKey(tester, 'relation-details-description'),
        '  Детали связи\n🙂  ',
      );

      tester.binding.platformDispatcher.localesTestValue = const [
        Locale('de', 'DE'),
      ];
      await tester.pumpAndSettle();
      expect(_textByKey(tester, 'relation-details-phrase'), renamedPhrase);
      expect(
        _textByKey(tester, 'relation-details-description'),
        '  Детали связи\n🙂  ',
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

  testWidgets(
    'завершает создание после ухода и предъявляет его после возврата фокуса',
    (tester) async {
      await _prepareAppSurface(tester);
      final app = await _pumpDelayedRelationApp(tester);

      await _createIntention(
        tester,
        title: 'Беречь здоровье',
        description: 'Причина',
      );
      await _dismissOperationMessage(tester);
      await _createIntention(tester, title: 'Много ходить', description: 'Шаг');

      const occupiedMessage = 'Create — “Много ходить”: Intention created.';
      await _pumpUntilFound(tester, find.text(occupiedMessage));
      expect(find.text(occupiedMessage), findsOneWidget);
      await _openIntention(tester, 'Беречь здоровье');
      await _createNeedRelation(
        tester,
        relatedTitle: 'Много ходить',
        description: 'Связь завершится после ухода',
        waitForTerminalOutcome: false,
      );
      expect(app.repository.createAttempts, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await app.repository.completePendingWithRealResult();
      await tester.pump();

      const phrase = 'To Беречь здоровье, you need Много ходить';
      const relationMessage = 'Create — “new relation”: Relation created.';
      expect(find.text(relationMessage), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text(phrase));
      expect(find.text(occupiedMessage), findsOneWidget);
      expect(find.text(relationMessage), findsNothing);

      await tester.pumpWidget(MainApp(key: UniqueKey(), runtime: app.runtime));
      await _pumpUntilFound(tester, find.text(relationMessage));
      expect(find.text(relationMessage), findsOneWidget);
      expect(find.text(phrase), findsOneWidget);
      expect(app.repository.createAttempts, 1);

      await _dismissOperationMessage(tester);
      expect(find.text(relationMessage), findsNothing);
      expect(app.repository.createAttempts, 1);
    },
  );

  testWidgets(
    'не повторяет команды жизненного цикла после ухода и повторного открытия',
    (tester) async {
      await _prepareAppSurface(tester);
      final app = await _pumpDelayedRelationApp(tester, delayCreation: false);

      await _createIntention(
        tester,
        title: 'Беречь здоровье',
        description: 'Причина',
      );
      await _dismissOperationMessage(tester);
      await _createIntention(tester, title: 'Много ходить', description: 'Шаг');
      await _dismissOperationMessage(tester);
      await _openIntention(tester, 'Беречь здоровье');
      await _createNeedRelation(
        tester,
        relatedTitle: 'Много ходить',
        description: 'Исходное описание',
      );
      await _dismissOperationMessage(tester);

      const phrase = 'To Беречь здоровье, you need Много ходить';
      await _tapWhenFound(tester, find.text(phrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-edit-relation')),
      );

      app.repository.holdNext(UpdateLongTermRelation);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-edit-relation')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-editor-description')),
      );
      const updatedDescription = 'Описание после принятого изменения';
      await tester.enterText(
        find.byKey(const ValueKey('relation-editor-description')),
        updatedDescription,
      );
      await tester.pump();
      final submit = find.byKey(const ValueKey('relation-editor-submit'));
      await _ensureVisible(tester, submit);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await _pumpUntilCommandAttempt(
        tester,
        app.repository,
        UpdateLongTermRelation,
      );
      expect(app.repository.attemptsFor(UpdateLongTermRelation), 1);

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await _tapWhenFound(tester, find.text(phrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-operation-running')),
      );
      await app.repository.completePendingWithRealResult();
      await _pumpUntilFound(tester, find.text(updatedDescription));
      expect(app.repository.attemptsFor(UpdateLongTermRelation), 1);
      await _dismissOperationMessage(tester);

      app.repository.holdNext(ArchiveLongTermRelation);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-archive-relation')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-operation-running')),
      );
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await _tapWhenFound(tester, find.text(phrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-operation-running')),
      );
      await app.repository.completePendingWithRealResult();
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-restore-relation')),
      );
      expect(app.repository.attemptsFor(ArchiveLongTermRelation), 1);
      await _dismissOperationMessage(tester);

      app.repository.holdNext(RestoreLongTermRelation);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-restore-relation')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-operation-running')),
      );
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      final archived = find.byKey(
        const ValueKey('relation-neighborhood-scope-archived'),
      );
      await _ensureVisible(tester, archived);
      await tester.tap(archived);
      await _tapWhenFound(tester, find.text(phrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-operation-running')),
      );
      await app.repository.completePendingWithRealResult();
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-archive-relation')),
      );
      expect(app.repository.attemptsFor(RestoreLongTermRelation), 1);
      await _dismissOperationMessage(tester);

      app.repository.holdNext(DeleteLongTermRelation);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-delete-relation')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-confirm-delete')),
      );
      await tester.tap(
        find.byKey(const ValueKey('relation-details-confirm-delete')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-operation-running')),
      );
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      final active = find.byKey(
        const ValueKey('relation-neighborhood-scope-active'),
      );
      await _ensureVisible(tester, active);
      await tester.tap(active);
      await _tapWhenFound(tester, find.text(phrase));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-details-operation-running')),
      );
      await app.repository.completePendingWithRealResult();
      await _pumpUntilAbsent(
        tester,
        find.byKey(const ValueKey('relation-details-delete-relation')),
      );
      expect(app.repository.attemptsFor(DeleteLongTermRelation), 1);
      await _dismissOperationMessage(tester);
      expect(find.text(phrase), findsNothing);
    },
  );

  testWidgets(
    'передаёт ошибку до кадра оболочке и не повторяет неизвестный отказ',
    (tester) async {
      await _prepareAppSurface(tester);
      final app = await _pumpDelayedRelationApp(tester);

      await _createIntention(
        tester,
        title: 'Беречь здоровье',
        description: 'Причина',
      );
      await _dismissOperationMessage(tester);
      await _createIntention(tester, title: 'Много ходить', description: 'Шаг');
      await _dismissOperationMessage(tester);
      await _openIntention(tester, 'Беречь здоровье');
      await _createNeedRelation(
        tester,
        relatedTitle: 'Много ходить',
        description: 'Несохранённый текст',
        waitForTerminalOutcome: false,
      );

      app.repository.completePendingWithUnexpectedFailure();
      await tester.pageBack();
      await tester.pumpAndSettle();

      const errorMessage =
          'Create — “new relation”: The relation couldn’t be created because of an unexpected error.';
      expect(find.text(errorMessage), findsOneWidget);
      expect(app.repository.createAttempts, 1);
      expect(
        find.text('To Беречь здоровье, you need Много ходить'),
        findsNothing,
      );
      expect(find.text('Active relations: 0'), findsWidgets);

      await _dismissOperationMessage(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(errorMessage), findsNothing);
      expect(app.repository.createAttempts, 1);
      expect(
        find.text('To Беречь здоровье, you need Много ходить'),
        findsNothing,
      );
    },
  );
}

Future<void> _prepareAppSurface(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<_DelayedApp> _pumpDelayedRelationApp(
  WidgetTester tester, {
  bool delayCreation = true,
}) async {
  final diagnostics = InMemoryDiagnosticsSink();
  late _DelayedRelationRepository repository;
  final runtime = AppRuntime(
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: diagnostics,
    repositoryFactory: (database) {
      repository = _DelayedRelationRepository(
        DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.now().toUtc(),
          diagnostics,
          relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
        ),
        delayCreation: delayCreation,
      );
      return repository;
    },
  );
  addTearDown(runtime.shutdown);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('catalog-create-intention')),
  );
  return (runtime: runtime, repository: repository);
}

typedef _DelayedApp = ({
  AppRuntime runtime,
  _DelayedRelationRepository repository,
});

AppRuntime _fileRuntime(
  LocalDatabaseHarness database, {
  required InMemoryDiagnosticsSink diagnostics,
}) => AppRuntime(
  connectionFactory: () => openFileBackedLocalDatabase(database.databaseFile),
  diagnosticsSink: diagnostics,
);

Future<void> _createIntention(
  WidgetTester tester, {
  required String title,
  required String description,
}) async {
  await tester.tap(find.byKey(const ValueKey('catalog-create-intention')));
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('intention-editor-title')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('intention-editor-title')),
    title,
  );
  await tester.enterText(
    find.byKey(const ValueKey('intention-editor-description')),
    description,
  );
  await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
  await _pumpUntilFound(tester, find.text(title));
}

Future<void> _openIntention(WidgetTester tester, String title) async {
  final intention = find.text(title).first;
  await _ensureVisible(tester, intention);
  await tester.tap(intention);
  await _pumpUntilDetailsTitle(tester, title);
}

Future<void> _pumpUntilDetailsTitle(WidgetTester tester, String title) async {
  final titleFinder = find.byKey(const ValueKey('intention-details-title'));
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    final hasExpectedTitle = titleFinder.evaluate().any((element) {
      final widget = element.widget;
      return widget is Text && widget.data == title;
    });
    if (hasExpectedTitle) {
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
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
    find.byKey(const ValueKey('participant-picker-filter-field')),
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
  final catalog = find.byKey(const ValueKey('catalog-create-intention'));
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

Future<void> _pumpUntilCommandAttempt(
  WidgetTester tester,
  _DelayedRelationRepository repository,
  Type commandType, {
  int attempts = 1000,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (repository.attemptsFor(commandType) > 0) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('App-level поток не отправил ожидаемую команду $commandType.');
}

String _textByKey(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

final class _DelayedRelationRepository implements PersonalGraphRepository {
  _DelayedRelationRepository(this._inner, {required bool delayCreation})
    : _heldCommandType = delayCreation ? CreateLongTermRelation : null;

  final PersonalGraphRepository _inner;
  final Map<Type, int> _attempts = {};
  Type? _heldCommandType;
  _PendingRelationCommand? _pendingCommand;

  int get createAttempts => attemptsFor(CreateLongTermRelation);

  int attemptsFor(Type commandType) => _attempts[commandType] ?? 0;

  void holdNext(Type commandType) {
    if (_heldCommandType != null || _pendingCommand != null) {
      throw StateError('Тест уже удерживает команду связи.');
    }
    _heldCommandType = commandType;
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => _inner.getCatalogPage(query);

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => _inner.getRelationCounts(intentionId);

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) => _inner.getRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _inner.watchRelation(id);

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => _inner.watchIntention(id);

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is LongTermRelationCommand) {
      final relationCommand = command as LongTermRelationCommand;
      _attempts.update(
        relationCommand.runtimeType,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (relationCommand.runtimeType == _heldCommandType) {
        if (_pendingCommand != null) {
          throw StateError('Тест уже удерживает команду связи.');
        }
        _heldCommandType = null;
        final pending = _PendingRelationCommand(
          relationCommand,
          Completer<LongTermRelationCommandResult>(),
        );
        _pendingCommand = pending;
        return await pending.result.future
            as GraphCommandResult<TSuccess, TFailure>;
      }
    }
    return _inner.execute(command);
  }

  Future<void> completePendingWithRealResult() async {
    final pending = _takePending();
    pending.result.complete(await _inner.execute(pending.command));
  }

  void completePendingWithUnexpectedFailure() {
    final pending = _takePending();
    pending.result.complete(
      const GraphResultFailure(LongTermRelationUnexpectedFailure()),
    );
  }

  _PendingRelationCommand _takePending() {
    final pending = _pendingCommand;
    if (pending == null) {
      throw StateError('Тест не удерживает команду связи.');
    }
    _pendingCommand = null;
    return pending;
  }
}

final class _PendingRelationCommand {
  const _PendingRelationCommand(this.command, this.result);

  final LongTermRelationCommand command;
  final Completer<LongTermRelationCommandResult> result;
}

extension<T> on T {
  T also(void Function(T value) action) {
    action(this);
    return this;
  }
}
