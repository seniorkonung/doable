import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Не появился элемент: $finder');
}

Future<void> _untilCondition(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

Future<void> _dismissPresentedMessages(WidgetTester tester) async {
  final messenger = ScaffoldMessenger.of(
    tester.element(find.byKey(const ValueKey('tag-catalog-create'))),
  );
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.pumpAndSettle();
    if (find
        .byKey(const ValueKey('graph-operation-message'))
        .evaluate()
        .isEmpty) {
      return;
    }
    messenger.removeCurrentSnackBar();
    await tester.pumpAndSettle();
  }
  expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  _registerAssignmentScenarios();
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'диктор и увеличенный текст сохраняют ввод, действия и подтверждение — ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        late sqlite.Database raw;
        final database = AppDatabase(
          openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        );
        await database.open();
        addTearDown(database.close);
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 25),
          InMemoryDiagnosticsSink(),
        );
        final router = AppRouter();
        addTearDown(router.dispose);
        final l10n = await AppLocalizations.delegate.load(locale);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              personalGraphRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp.router(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2.5)),
                child: child!,
              ),
              routerConfig: router.config(),
            ),
          ),
        );
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
        final create = find.byKey(const ValueKey('tag-catalog-create'));
        await _until(tester, create);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(create).tooltip, l10n.tagCatalogCreate);
        await _tap(tester, create);
        final nameField = find.byKey(const ValueKey('tag-editor-name'));
        await _until(tester, nameField);
        expect(
          find.bySemanticsLabel(RegExp(l10n.tagEditorNameLabel)),
          findsWidgets,
        );

        final invalid = '🙂' * 256;
        await tester.enterText(nameField, invalid);
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        final failure = find.byKey(const ValueKey('tag-editor-field-failure'));
        await _until(tester, failure);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(failure).label, isNotEmpty);
        expect(tester.widget<TextField>(nameField).controller!.text, invalid);
        expect(raw.select('SELECT * FROM tags'), isEmpty);

        final corrected =
            'Straße 🏠é ${('Длинное название ' * 8).trimRight()}';
        await tester.enterText(nameField, corrected);
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        await _until(tester, find.text(corrected));
        final id = raw.select('SELECT id FROM tags').single['id'] as String;
        final delete = find.byKey(ValueKey('tag-catalog-delete-$id'));
        await _until(tester, delete);
        await tester.pumpAndSettle();
        await tester.ensureVisible(delete);
        expect(tester.getSemantics(delete).tooltip, l10n.tagCatalogDelete);
        await _tap(tester, delete);
        final scope = find.byKey(const ValueKey('tag-delete-scope'));
        await _until(tester, scope);
        await tester.pumpAndSettle();
        expect(find.textContaining(corrected), findsWidgets);
        expect(
          tester.getSemantics(scope).label,
          contains(l10n.tagDeleteConfirmationScope),
        );
        final cancel = find.byKey(const ValueKey('tag-delete-cancel'));
        final confirm = find.byKey(const ValueKey('tag-delete-confirm'));
        await tester.ensureVisible(cancel);
        expect(tester.getSemantics(cancel).label, l10n.tagDeleteCancel);
        await tester.ensureVisible(confirm);
        expect(tester.getSemantics(confirm).label, l10n.tagDeleteConfirm);
        expect(tester.takeException(), isNull);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(raw.select('SELECT id FROM tags'), hasLength(1));
        semantics.dispose();
      },
    );
  }
}

void _registerAssignmentScenarios() {
  for (final (locale, isIntention, number) in [
    (const Locale('ru'), true, 1),
    (const Locale('en'), true, 2),
    (const Locale('ru'), false, 101),
    (const Locale('en'), false, 102),
  ]) {
    testWidgets(
      'полный сценарий назначений доступен: ${locale.languageCode}, ${isIntention ? 'намерение' : 'связь'} $number',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.platformDispatcher.localesTestValue = [locale];
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();

        late sqlite.Database raw;
        final runtime = AppRuntime(
          connectionFactory: () =>
              openInMemoryLocalDatabase(setup: (database) => raw = database),
          diagnosticsSink: InMemoryDiagnosticsSink(),
        );
        addTearDown(() async {
          await runtime.shutdown();
        });
        final ready =
            (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
        seedTagStorageFixture(raw);
        for (var index = 0; index < 50; index++) {
          final id = tagFixtureId(10000 + index);
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            id,
            'Дополнение ${index.toString().padLeft(3, '0')}',
          ]);
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, ${isIntention ? 'intention_id' : 'long_term_relation_id'}) VALUES (?, ?)',
            [id, tagFixtureId(number)],
          );
        }
        final l10n = await AppLocalizations.delegate.load(locale);
        final router = ready.container.read(appRouterProvider);
        await tester.pumpWidget(MainApp(runtime: runtime));
        await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));
        if (isIntention) {
          final id = (IntentionId.decode(
            tagFixtureId(number),
          ) as IntentionIdDecodingSuccess).id;
          unawaited(router.push(IntentionDetailsRoute(intentionId: id)));
        } else {
          final id = (LongTermRelationId.decode(
            tagFixtureId(number),
          ) as LongTermRelationIdDecodingSuccess).id;
          unawaited(router.push(RelationDetailsRoute(relationId: id)));
        }
        final archived = number == 2 || number == 102;
        final kind = isIntention
            ? l10n.tagAssignmentsIntention
            : l10n.tagAssignmentsRelation;
        final archiveState = archived
            ? l10n.tagAssignmentsArchived
            : l10n.tagAssignmentsActive;
        final detailsMarker = find.byKey(
          ValueKey(
            isIntention ? 'intention-details-title' : 'relation-details-phrase',
          ),
        );
        await _until(tester, detailsMarker);
        final detailsScroll = find
            .descendant(
              of: isIntention
                  ? find.byType(IntentionDetailsPage)
                  : find.byType(RelationDetailsPage),
              matching: find.byType(Scrollable),
            )
            .first;
        final choose = find.byKey(const ValueKey('tag-assignments-choose'));
        await tester.scrollUntilVisible(choose, 250, scrollable: detailsScroll);
        await _until(tester, find.byType(TagAssignmentsSection));
        await tester.ensureVisible(choose);
        await tester.pump();
        expect(
          tester.getSemantics(find.byType(TagAssignmentsSection)).label,
          contains(l10n.tagAssignmentsContext(kind, archiveState)),
        );
        expect(
          find.byTooltip(l10n.tagAssignmentsChooseSemantic(kind, archiveState)),
          findsOneWidget,
        );
        expect(
          _semanticTooltips(tester),
          contains(l10n.tagAssignmentsChooseSemantic(kind, archiveState)),
        );
        _expectAction(tester.getSemantics(choose));
        final removeHome = find.byKey(
          ValueKey('tag-assignment-remove-${tagFixtureId(firstTagNumber)}'),
        );
        await tester.ensureVisible(removeHome);
        expect(
          find.byTooltip(l10n.tagAssignmentsRemoveNamed('Дом')),
          findsOneWidget,
        );
        expect(
          _semanticTooltips(tester),
          contains(l10n.tagAssignmentsRemoveNamed('Дом')),
        );
        _expectAction(tester.getSemantics(removeHome));
        expect(
          _traversalIndex(tester, l10n.tagAssignmentsChoose),
          lessThan(_traversalIndex(tester, l10n.tagAssignmentsRemove)),
        );

        await _tap(tester, choose);
        final assignedRow = find.byKey(
          ValueKey('tag-catalog-row-${tagFixtureId(firstTagNumber)}'),
        );
        await _until(tester, assignedRow);
        await tester.pumpAndSettle();
        final assignedStatus = find.descendant(
          of: assignedRow,
          matching: find.text(l10n.tagCatalogAssigned),
        );
        expect(assignedStatus, findsOneWidget);
        expect(
          tester.getSemantics(assignedStatus).label,
          contains(l10n.tagCatalogAssigned),
        );
        expect(
          tester
              .getSemantics(assignedStatus)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(find.text(l10n.tagCatalogAvailable), findsWidgets);
        await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
        final name = find.byKey(const ValueKey('tag-editor-name'));
        await _until(tester, name);
        await tester.enterText(name, 'Дом');
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        final fieldFailure = find.byKey(
          const ValueKey('tag-editor-field-failure'),
        );
        await _until(tester, fieldFailure);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(fieldFailure).label,
          contains(l10n.tagNameOccupied),
        );
        expect(tester.widget<TextField>(name).controller!.text, 'Дом');
        _expectAction(
          tester.getSemantics(find.byKey(const ValueKey('tag-editor-cancel'))),
        );
        expect(
          _traversalIndex(tester, l10n.tagEditorNameLabel),
          lessThan(_traversalIndex(tester, l10n.tagEditorCreateAction)),
        );
        expect(
          _traversalIndex(tester, l10n.tagEditorCreateAction),
          lessThan(_traversalIndex(tester, l10n.tagEditorCancel)),
        );

        final newName = 'Straße 🏠é ${'Длинное название ' * 7}'.trimRight();
        await tester.enterText(name, newName);
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        await _until(tester, find.byKey(const ValueKey('tag-catalog-assign')));
        final newId =
            raw.select('SELECT id FROM tags WHERE name = ?', [
                  newName,
                ]).single['id']
                as String;
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [newId]),
          isEmpty,
        );
        final assign = find.byKey(const ValueKey('tag-catalog-assign'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(l10n.tagCatalogAssignNamed(newName)),
          findsOneWidget,
        );
        _expectAction(tester.getSemantics(assign));
        await _tap(tester, assign);
        await _untilCondition(
          tester,
          () => raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            newId,
          ]).isNotEmpty,
        );
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [newId]),
          hasLength(1),
        );
        router.pop();
        await _until(
          tester,
          isIntention
              ? find.byType(IntentionDetailsPage)
              : find.byType(RelationDetailsPage),
        );
        await tester.pumpAndSettle();
        final more = find.byKey(const ValueKey('tag-assignments-load-more'));
        await tester.scrollUntilVisible(more, 500, scrollable: detailsScroll);
        await _tap(tester, more);
        final removeNew = find.byKey(ValueKey('tag-assignment-remove-$newId'));
        await _until(tester, removeNew);
        await tester.ensureVisible(removeNew);
        expect(
          find.byTooltip(l10n.tagAssignmentsRemoveNamed(newName)),
          findsOneWidget,
        );
        await _tap(tester, removeNew);
        await _untilCondition(
          tester,
          () => raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            newId,
          ]).isEmpty,
        );
        expect(
          raw.select('SELECT id FROM tags WHERE id = ?', [newId]),
          hasLength(1),
        );

        if (isIntention || number == 102) {
          final recipientDelete = find.byKey(
            ValueKey(
              isIntention
                  ? 'intention-details-delete'
                  : 'relation-details-delete-relation',
            ),
          );
          await tester.scrollUntilVisible(
            recipientDelete,
            -300,
            scrollable: detailsScroll,
          );
          await _tap(tester, recipientDelete);
          await tester.pumpAndSettle();
          final message = isIntention
              ? l10n.detailsDeleteConfirmationMessage
              : l10n
                    .relationDetailsDeleteConfirmationMessage('', '', '', '')
                    .split('\n\n')
                    .last;
          expect(
            tester.getSemantics(find.textContaining(message)).label,
            contains(message),
          );
          final cancelRecipient = find.text(l10n.detailsCancelEditAction).last;
          final confirmRecipient = find.byKey(
            ValueKey(
              isIntention
                  ? 'intention-details-confirm-delete'
                  : 'relation-details-confirm-delete',
            ),
          );
          _expectAction(tester.getSemantics(cancelRecipient));
          _expectAction(tester.getSemantics(confirmRecipient));
          expect(
            _traversalIndex(tester, l10n.detailsCancelEditAction),
            lessThan(
              _traversalIndex(
                tester,
                isIntention
                    ? l10n.detailsConfirmDeleteAction
                    : l10n.relationDetailsConfirmDeleteAction,
              ),
            ),
          );
          await tester.tap(cancelRecipient);
          await tester.pumpAndSettle();
          expect(
            raw.select('SELECT id FROM tags WHERE id = ?', [newId]),
            hasLength(1),
          );
        }

        expect(tester.takeException(), isNull);

        router.pop();
        await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
        await _until(tester, find.byKey(const ValueKey('tag-catalog-create')));
        await _dismissPresentedMessages(tester);
        await _tap(tester, find.byKey(const ValueKey('tag-catalog-load-more')));
        final delete = find.byKey(ValueKey('tag-catalog-delete-$newId'));
        await tester.scrollUntilVisible(
          delete,
          300,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('tag-catalog-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await _tap(tester, delete);
        final scope = find.byKey(const ValueKey('tag-delete-scope'));
        await _until(tester, scope);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(scope).label,
          contains(l10n.tagDeleteConfirmationScope),
        );
        final cancel = find.byKey(const ValueKey('tag-delete-cancel'));
        final confirm = find.byKey(const ValueKey('tag-delete-confirm'));
        await tester.ensureVisible(cancel);
        await tester.ensureVisible(confirm);
        expect(tester.getSemantics(cancel).label, l10n.tagDeleteCancel);
        expect(tester.getSemantics(confirm).label, l10n.tagDeleteConfirm);
        _expectAction(tester.getSemantics(cancel));
        _expectAction(tester.getSemantics(confirm));
        expect(
          _traversalIndex(tester, l10n.tagDeleteCancel),
          lessThan(_traversalIndex(tester, l10n.tagDeleteConfirm)),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(
          raw.select('SELECT id FROM tags WHERE id = ?', [newId]),
          hasLength(1),
        );
        await _tap(tester, delete);
        await _tap(tester, confirm);
        await _untilCondition(
          tester,
          () => raw.select('SELECT id FROM tags WHERE id = ?', [newId]).isEmpty,
        );
        final tagId = (TagId.decode(newId) as TagIdDecodingSuccess).id;
        await _untilCondition(
          tester,
          () => !ready.container
              .read(graphCommandCoordinatorProvider.notifier)
              .isTagRunning(tagId),
        );
        expect(
          raw.select('SELECT id FROM tags WHERE id = ?', [newId]),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        for (var attempt = 0; attempt < 4; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump(const Duration(milliseconds: 1));
        }
        semantics.dispose();
      },
    );
  }
}

void _expectAction(SemanticsNode node) {
  expect(node.flagsCollection.isButton, isTrue);
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
}

int _traversalIndex(WidgetTester tester, String label) {
  final labels = <String>[];
  void walk(SemanticsNode node) {
    labels.add(node.label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      walk(child);
    }
  }

  walk(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  final index = labels.indexWhere((value) => value.contains(label));
  expect(
    index,
    isNonNegative,
    reason: 'Нет в порядке семантического обхода: $label',
  );
  return index;
}

List<String> _semanticTooltips(WidgetTester tester) {
  final tooltips = <String>[];
  void walk(SemanticsNode node) {
    if (node.tooltip.isNotEmpty) tooltips.add(node.tooltip);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      walk(child);
    }
  }

  walk(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return tooltips;
}
