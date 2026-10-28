import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/app_root_pages.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/intention_options.dart';
import '../../support/tag_positions.dart';

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
  _registerFilterPanelScenarios();
}

void _registerAssignmentScenarios() {
  for (final (locale, number) in [
    (const Locale('ru'), 1),
    (const Locale('en'), 2),
  ]) {
    testWidgets(
      'полный сценарий назначений доступен: ${locale.languageCode}, намерение $number',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.platformDispatcher.localesTestValue = [locale];

        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();

        late sqlite.Database raw;
        final runtime = AppRuntime(
          quickCreationModeStore: InMemoryQuickCreationModeStore(),
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
        seedRawGraph(raw, () {
          // Удаление получателя доступно в параметрах только без связей и
          // дневных выборов.
          raw
            ..execute('DELETE FROM daily_choice_path_steps')
            ..execute('DELETE FROM daily_choices')
            ..execute('DELETE FROM long_term_relations');
          for (var index = 0; index < 50; index++) {
            final id = tagFixtureId(10000 + index);
            raw.execute(
              'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
              [
                id,
                'Дополнение ${index.toString().padLeft(3, '0')}',
                tagPositionKey(10000 + index),
              ],
            );
            raw.execute(
              'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
              [id, tagFixtureId(number)],
            );
          }
        });
        final l10n = await AppLocalizations.delegate.load(locale);
        final router = ready.container.read(appRouterProvider);
        await tester.pumpWidget(MainApp(runtime: runtime));
        await openIntentionGraph(tester, waitFor: _until);
        await _until(
          tester,
          find.byKey(const ValueKey('intention-tag-conditions-add')),
        );
        final id = (IntentionId.decode(
          tagFixtureId(number),
        ) as IntentionIdDecodingSuccess).id;
        unawaited(router.push(IntentionDetailsRoute(intentionId: id)));
        final archived = number == 2;
        final kind = l10n.tagAssignmentsIntention;
        final archiveState = archived
            ? l10n.tagAssignmentsArchived
            : l10n.tagAssignmentsActive;
        final detailsMarker = find.byKey(
          const ValueKey('intention-details-title'),
        );
        await _until(tester, detailsMarker);
        final detailsScroll = find
            .descendant(
              of: find.byType(IntentionDetailsPage),
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
        // «Добавить» перечисляет назначенные теги в их ручном порядке.
        final assignedNames = [
          for (final row in raw.select(
            'SELECT tags.name FROM tags '
            'JOIN tag_assignments ON tag_assignments.tag_id = tags.id '
            'WHERE tag_assignments.intention_id = ? ORDER BY tags.position',
            [tagFixtureId(number)],
          ))
            row['name'] as String,
        ];
        final addLabel = l10n.tagAssignmentsAddLabel(assignedNames.join(', '));
        expect(tester.getSemantics(choose).label, addLabel);
        _expectAction(tester.getSemantics(choose));
        final removeHome = find.byKey(
          ValueKey('tag-assignment-remove-${tagFixtureId(firstTagNumber)}'),
        );
        await tester.ensureVisible(removeHome);
        expect(
          tester.getSemantics(removeHome).label,
          l10n.tagAssignmentsRemoveNamed('Дом'),
        );
        _expectAction(tester.getSemantics(removeHome));
        expect(
          _traversalIndex(tester, addLabel),
          lessThan(
            _traversalIndex(tester, l10n.tagAssignmentsRemoveNamed('Дом')),
          ),
        );

        await _tap(tester, choose);
        final assignedRow = find.byKey(
          ValueKey('tags-panel-row-${tagFixtureId(firstTagNumber)}'),
        );
        final availableRow = find.byKey(
          ValueKey('tags-panel-row-${tagFixtureId(lastTagNumber)}'),
        );
        await _until(tester, assignedRow);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(assignedRow),
          isSemantics(
            label: 'Дом',
            hasCheckedState: true,
            isChecked: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(availableRow),
          isSemantics(
            label: 'Работа',
            hasCheckedState: true,
            isChecked: false,
            hasTapAction: true,
          ),
        );

        final newName = 'Straße 🏠é ${'Длинное название ' * 7}'.trimRight();
        await tester.enterText(
          find.descendant(
            of: find.byType(Sheet),
            matching: find.byType(TextField),
          ),
          newName,
        );
        await tester.pump();
        final createRow = find.bySemanticsLabel(
          l10n.tagsPanelCreateTag(newName),
        );
        _expectAction(tester.getSemantics(createRow));
        await _tap(tester, createRow);
        final name = find.bySemanticsLabel(RegExp(l10n.tagEditorNameLabel));
        await _until(tester, name);
        await tester.pumpAndSettle();
        expect(
          _traversalIndex(tester, l10n.tagEditorNameLabel),
          lessThan(_traversalIndex(tester, l10n.tagEditorCreateAction)),
        );
        await _tap(
          tester,
          find.widgetWithText(FilledButton, l10n.tagEditorCreateAction),
        );
        await _untilCondition(
          tester,
          () => raw.select('SELECT id FROM tags WHERE name = ?', [
            newName,
          ]).isNotEmpty,
        );
        final newId =
            raw.select('SELECT id FROM tags WHERE name = ?', [
                  newName,
                ]).single['id']
                as String;
        // Созданный в панели тег сразу назначен и объявлен отмеченным.
        final newRow = find.byKey(ValueKey('tags-panel-row-$newId'));
        await _untilCondition(
          tester,
          () =>
              raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
                newId,
              ]).isNotEmpty &&
              find.bySemanticsLabel(newName).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(newRow),
          isSemantics(
            label: newName,
            hasCheckedState: true,
            isChecked: true,
            hasTapAction: true,
          ),
        );
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [newId]),
          hasLength(1),
        );
        // Отметка назначает тег нажатием, а удаление самого тега — отдельное
        // действие строки с доступным подтверждением.
        final rowNode = tester.getSemantics(newRow);
        expect(
          rowNode,
          isSemantics(
            label: newName,
            hint: l10n.tagsPanelTagHoldHint,
            hasCheckedState: true,
            isChecked: true,
            hasTapAction: true,
            hasLongPressAction: true,
            customActions: [
              CustomSemanticsAction(label: l10n.tagsPanelEditTag),
              CustomSemanticsAction(label: l10n.tagsPanelDuplicateTag),
              CustomSemanticsAction(label: l10n.tagsPanelDeleteTag),
            ],
          ),
        );
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          rowNode.id,
          SemanticsAction.customAction,
          CustomSemanticsAction.getIdentifier(
            CustomSemanticsAction(label: l10n.tagsPanelDeleteTag),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(l10n.tagsPanelDeleteTitle), findsWidgets);
        expect(
          tester
              .getSemantics(
                find.textContaining(l10n.tagsPanelDeleteTextAfter.trim()),
              )
              .label,
          allOf(
            contains(newName),
            contains(l10n.tagsPanelDeleteTextAfter.trim()),
          ),
        );
        final cancelDeletion = find.text(l10n.tagsPanelDeleteCancel);
        final confirmDeletion = find.text(l10n.tagsPanelDeleteConfirm);
        _expectAction(tester.getSemantics(cancelDeletion));
        _expectAction(tester.getSemantics(confirmDeletion));
        await tester.tap(cancelDeletion);
        await tester.pumpAndSettle();
        expect(
          raw.select('SELECT id FROM tags WHERE id = ?', [newId]),
          hasLength(1),
        );
        await _tap(tester, find.text(l10n.tagsPanelDone));
        await _until(tester, find.byType(IntentionDetailsPage));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('tag-assignments-load-more')),
          findsNothing,
        );
        final removeNew = find.byKey(ValueKey('tag-assignment-remove-$newId'));
        await _until(tester, removeNew);
        await tester.scrollUntilVisible(
          removeNew,
          500,
          scrollable: detailsScroll,
        );
        await tester.ensureVisible(removeNew);
        expect(
          tester.getSemantics(removeNew).label,
          l10n.tagAssignmentsRemoveNamed(newName),
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

        await _tap(tester, intentionOptionsButton);
        await _tap(tester, intentionOption(IntentionOption.delete));
        await tester.pumpAndSettle();
        final message =
            '${l10n.detailsDeleteDialogTextBefore}Намерение $number'
            '${l10n.detailsDeleteDialogTextAfter}';
        expect(
          tester.getSemantics(find.textContaining(message)).label,
          contains(message),
        );
        _expectAction(tester.getSemantics(intentionDeletionCancel));
        _expectAction(tester.getSemantics(intentionDeletionConfirm));
        expect(
          _traversalIndexOf(tester, intentionDeletionCancel),
          lessThan(_traversalIndexOf(tester, intentionDeletionConfirm)),
        );
        await tester.tap(intentionDeletionCancel);
        await tester.pumpAndSettle();
        expect(
          raw.select('SELECT id FROM tags WHERE id = ?', [newId]),
          hasLength(1),
        );

        expect(tester.takeException(), isNull);

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

void _registerFilterPanelScenarios() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    testWidgets('${locale.languageCode}: в панели фильтра диктор объявляет '
        'надобность один раз и сбрасывает условия без назначений', (
      tester,
    ) async {
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
      seedRawGraph(raw, () {
        for (final (number, name) in [
          (firstTagNumber, 'Дом'),
          (lastTagNumber, 'Работа'),
        ]) {
          raw.execute(
            'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
            [tagFixtureId(number), name, tagPositionKey(number)],
          );
        }
      });
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final conditionsProvider = intentionTagConditionsViewModelProvider(
        const BrowseIntentionCatalog(),
      );
      final conditionsSubscription = container.listen(
        conditionsProvider,
        (_, _) {},
      );
      addTearDown(conditionsSubscription.close);
      final conditions = container.read(conditionsProvider.notifier);
      final l10n = await AppLocalizations.delegate.load(locale);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: doableTheme(Brightness.light),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => GraphOperationPresenter(
              child: child ?? const SizedBox.shrink(),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showTagsPanel(
                      context,
                      TagsPanelFilterContext(conditions),
                    ),
                    child: const Text('Открыть'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.tap(find.text('Открыть'));
      final home = find.byKey(
        ValueKey('tags-panel-row-${tagFixtureId(firstTagNumber)}'),
      );
      await _until(tester, home);
      await tester.pumpAndSettle();
      expect(find.text(l10n.tagsPanelFilterTitle), findsOne);
      expect(find.text(l10n.tagsPanelFilterHint), findsOne);

      // Без условия строка называет только тег, а надобность у строки не
      // объявляется ни состоянием отметки, ни повтором в названии.
      for (final (label, requirement) in [
        ('Дом', null),
        (
          l10n.tagsPanelFilterPresentLabel('Дом'),
          IntentionTagRequirement.mustBePresent,
        ),
        (
          l10n.tagsPanelFilterAbsentLabel('Дом'),
          IntentionTagRequirement.mustBeAbsent,
        ),
      ]) {
        if (requirement != null) {
          _performSemanticsTap(tester, tester.getSemantics(home));
          await tester.pump();
        }
        final node = tester.getSemantics(home);
        expect(node.label, label);
        expect(
          node.flagsCollection.isChecked,
          CheckedState.none,
          reason: 'надобность объявляется только названием строки',
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
        expect(
          [
            for (final condition in conditions.current.conditions)
              condition.requirement,
          ],
          [?requirement],
        );
      }

      final reset = find.bySemanticsLabel(l10n.tagsPanelResetConditionsLabel);
      expect(tester.getSemantics(reset).flagsCollection.isButton, isTrue);
      _performSemanticsTap(tester, tester.getSemantics(reset));
      await tester.pump();

      expect(conditions.current.conditions, isEmpty);
      expect(reset, findsNothing);
      expect(tester.getSemantics(home).label, 'Дом');
      expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

void _performSemanticsTap(WidgetTester tester, SemanticsNode node) {
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
}

void _expectAction(SemanticsNode node) {
  expect(node.flagsCollection.isButton, isTrue);
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
}

int _traversalIndex(WidgetTester tester, String label) {
  final index = _traversal(tester)
      .indexWhere((node) => node.label.contains(label));
  expect(
    index,
    isNonNegative,
    reason: 'Нет в порядке семантического обхода: $label',
  );
  return index;
}

/// Место узла [finder] в порядке обхода: подпись кнопки может повторяться в
/// заголовке, поэтому узел сравнивается по идентификатору.
int _traversalIndexOf(WidgetTester tester, Finder finder) {
  final id = tester.getSemantics(finder).id;
  final index = _traversal(tester).indexWhere((node) => node.id == id);
  expect(
    index,
    isNonNegative,
    reason: 'Нет в порядке семантического обхода: $finder',
  );
  return index;
}

List<SemanticsNode> _traversal(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    nodes.add(node);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      walk(child);
    }
  }

  walk(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return nodes;
}
