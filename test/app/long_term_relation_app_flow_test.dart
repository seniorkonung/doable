import 'dart:async';

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
      final runtimes = <AppRuntime>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final runtime in runtimes.reversed) {
          await runtime.shutdown();
        }
        await database.dispose();
      });

      final firstRuntime = _fileRuntime(database)..also(runtimes.add);
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

      final reopenedRuntime = _fileRuntime(database)..also(runtimes.add);
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
            .hasFlag(SemanticsFlag.isLiveRegion),
        isTrue,
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

Future<_DelayedApp> _pumpDelayedRelationApp(WidgetTester tester) async {
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

AppRuntime _fileRuntime(LocalDatabaseHarness database) => AppRuntime(
  connectionFactory: () => openFileBackedLocalDatabase(database.databaseFile),
  diagnosticsSink: InMemoryDiagnosticsSink(),
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
    expect(typeSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);
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

String _textByKey(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

final class _DelayedRelationRepository implements PersonalGraphRepository {
  _DelayedRelationRepository(this._inner);

  final PersonalGraphRepository _inner;
  _PendingRelationCreation? _pendingCreation;
  var createAttempts = 0;

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
    if (command is CreateLongTermRelation) {
      if (_pendingCreation != null) {
        throw StateError('Тест уже удерживает создание связи.');
      }
      createAttempts += 1;
      final pending = _PendingRelationCreation(
        command as CreateLongTermRelation,
        Completer<LongTermRelationCommandResult>(),
      );
      _pendingCreation = pending;
      return await pending.result.future
          as GraphCommandResult<TSuccess, TFailure>;
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

  _PendingRelationCreation _takePending() {
    final pending = _pendingCreation;
    if (pending == null) {
      throw StateError('Тест не удерживает создание связи.');
    }
    _pendingCreation = null;
    return pending;
  }
}

final class _PendingRelationCreation {
  const _PendingRelationCreation(this.command, this.result);

  final CreateLongTermRelation command;
  final Completer<LongTermRelationCommandResult> result;
}

extension<T> on T {
  T also(void Function(T value) action) {
    action(this);
    return this;
  }
}
