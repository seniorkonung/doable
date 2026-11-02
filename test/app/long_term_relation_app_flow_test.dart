import 'dart:ui' show Tristate;

import 'package:auto_route/auto_route.dart';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as catalog_page;
import 'package:doable/src/design_system/components/archived_fold.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/design_system/components/relation_row.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_row.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter/material.dart';
import 'package:drift/native.dart' show DatabaseSetup;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/daily_choice_details_controls.dart';

import '../support/app_root_pages.dart';
import '../support/daily_choice_catalog_controls.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/daily_choice_local_date.dart';
import '../support/graph_seed.dart';
import '../support/intention_catalog_controls.dart';
import '../support/quick_creation.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/intention_edit_screen.dart';
import '../support/intention_options.dart';

void main() {
  testWidgets(
    'создаёт связь, согласует соседство и сохраняет поток после открытия файла',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final l10n = lookupAppLocalizations(const Locale('en'));

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
        find.descendant(
          of: intentionCatalogRow('Беречь здоровье'),
          matching: find.text('Беречь здоровье'),
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
      await _pumpUntilFound(tester, _relationRow(initialPhrase));
      expect(
        find.bySemanticsLabel('Relations: 1 active, 0 archived'),
        findsOneWidget,
      );
      final groupControl = tester.getSemantics(
        find.byKey(const ValueKey('intention-relations-group-needs')),
      );
      expect(groupControl.label, contains('Needs: 1 active'));
      expect(
        groupControl.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(_relationRow(initialPhrase));
      await _pumpUntilRelationSheet(tester, initialPhrase);
      expect(find.text('  Детали связи\n🙂  '), findsOneWidget);
      expect(_priorityPicker(tester).value, DoablePriority.p2);
      // Панель закрывает навигацию и страницу под собой от нажатий.
      expect(appNavigationDestinations().hitTestable(), findsNothing);
      expect(_relationRow(initialPhrase).hitTestable(), findsNothing);
      final participant = tester.getSemantics(
        find.bySemanticsLabel(
          l10n.relationSheetOpenParticipant('Много ходить'),
        ),
      );
      expect(
        participant.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(
        find.bySemanticsLabel(
          l10n.relationSheetOpenParticipant('Много ходить'),
        ),
      );
      await _pumpUntilDetailsTitle(tester, 'Много ходить');
      await _chooseDetailsTab(tester, 'Relations');
      final neededFor = find.byKey(
        const ValueKey('intention-relations-group-neededFor'),
      );
      await _ensureVisible(tester, neededFor);
      await tester.tap(neededFor);
      await _pumpUntilFound(tester, _relationRow(initialPhrase));

      await tester.tap(_relationRow(initialPhrase));
      await _pumpUntilRelationSheet(tester, initialPhrase);
      await tester.tap(
        find.bySemanticsLabel(
          l10n.relationSheetOpenParticipant('Беречь здоровье'),
        ),
      );
      await _pumpUntilDetailsTitle(tester, 'Беречь здоровье');

      await _renameCurrentIntention(tester, 'Укреплять здоровье');
      await _chooseDetailsTab(tester, 'Relations');
      const renamedPhrase = 'To Укреплять здоровье, you need Много ходить';
      await _pumpUntilFound(tester, _relationRow(renamedPhrase));

      await _chooseIntentionOption(tester, IntentionOption.archive);
      await _pumpUntilFound(tester, intentionHeadRestore);
      await _dismissOperationMessage(tester);

      await _chooseDetailsTab(tester, 'Relations');
      await _expandArchive(tester);
      await _pumpUntilFound(tester, _relationRow(renamedPhrase));

      await _chooseIntentionOption(tester, IntentionOption.restore);
      await _pumpUntilAbsent(tester, intentionHeadRestore);
      await _dismissOperationMessage(tester);
      expect(_relationRow(renamedPhrase), findsOneWidget);
      expect(
        find.bySemanticsLabel('Relations: 0 active, 1 archived'),
        findsOneWidget,
      );

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
      await _chooseDetailsTab(tester, 'Relations');
      await _expandArchive(tester);
      await _pumpUntilFound(tester, _relationRow(renamedPhrase));
      await tester.tap(_relationRow(renamedPhrase));
      final archivedRenamed = l10n.relationSheetArchivedLabel(renamedPhrase);
      await _pumpUntilRelationSheet(tester, archivedRenamed);
      expect(find.text('  Детали связи\n🙂  '), findsOneWidget);
      // Переименованное намерение называется в шапке и в названии панели.
      expect(_relationHead(tester).source.name, 'Укреплять здоровье');
      expect(_relationHead(tester).status, isA<RelationHeadArchived>());

      // Архивированная связь меняет приоритет и описание, а тип сохраняет.
      const lifecycleDescription = '  Литеральный текст\n🧭  ';
      const lifecyclePhrase = 'To Укреплять здоровье, you can Много ходить';
      await _choosePriority(tester, DoablePriority.p4);
      await _saveRelationDescription(
        tester,
        l10n,
        current: '  Детали связи\n🙂  ',
        text: lifecycleDescription,
      );
      expect(find.bySemanticsLabel(archivedRenamed), findsOneWidget);
      expect(_relationHead(tester).kind, RelationHeadKind.need);
      expect(_relationHead(tester).status, isA<RelationHeadArchived>());
      expect(find.text(lifecycleDescription), findsOneWidget);

      // Активная связь меняет тип и переходит в другую группу того же
      // направления.
      await _chooseRelationOption(
        tester,
        l10n,
        l10n.relationSheetOptionRestore,
      );
      await _pumpUntilRelationHead<RelationHeadActive>(tester);
      await _chooseRelationKind(tester, l10n, RelationHeadKind.can);
      expect(find.bySemanticsLabel(lifecyclePhrase), findsOneWidget);
      expect(_priorityPicker(tester).value, DoablePriority.p4);
      expect(find.text(lifecycleDescription), findsOneWidget);
      await _chooseRelationOption(
        tester,
        l10n,
        l10n.relationSheetOptionArchive,
      );
      await _pumpUntilRelationHead<RelationHeadArchived>(tester);
      await _closeRelationSheet(tester);

      await _pumpUntilAbsent(tester, _relationRow(renamedPhrase));
      expect(_relationRow(lifecyclePhrase), findsNothing);
      final canUseGroup = find.byKey(
        const ValueKey('intention-relations-group-canUse'),
      );
      await _ensureVisible(tester, canUseGroup);
      await tester.tap(canUseGroup);
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await _expandArchive(tester);
      await _pumpUntilFound(tester, _relationRow(lifecyclePhrase));

      await tester.pumpWidget(const SizedBox.shrink());
      await reopenedRuntime.shutdown();
      runtimes.remove(reopenedRuntime);

      final lifecycleRuntime = _fileRuntime(database, diagnostics: diagnostics)
        ..also(runtimes.add);
      await tester.pumpWidget(MainApp(runtime: lifecycleRuntime));
      await openIntentionGraph(tester, waitFor: _pumpUntilFound);
      await _pumpUntilFound(tester, find.text('Укреплять здоровье'));
      await _openArchivedCanRelation(
        tester,
        participantTitle: 'Укреплять здоровье',
        phrase: lifecyclePhrase,
        sheetLabel: l10n.relationSheetArchivedLabel(lifecyclePhrase),
      );
      expect(find.text(lifecycleDescription), findsOneWidget);
      expect(_priorityPicker(tester).value, DoablePriority.p4);

      await _chooseRelationOption(
        tester,
        l10n,
        l10n.relationSheetOptionRestore,
      );
      await _pumpUntilRelationHead<RelationHeadActive>(tester);
      await tester.tap(
        find.bySemanticsLabel(
          l10n.relationSheetOpenParticipant('Укреплять здоровье'),
        ),
      );
      await _pumpUntilDetailsTitle(tester, 'Укреплять здоровье');
      // Возврат со страницы над панелью показывает ту же панель.
      await tester.binding.handlePopRoute();
      await _pumpUntilRelationSheet(tester, lifecyclePhrase);
      await _closeRelationSheet(tester);

      await _openIntentionOptions(tester);
      final blockedDeletion = tester.widget<OptionRow>(
        intentionOption(IntentionOption.delete),
      );
      expect(blockedDeletion.onPressed, isNull);
      expect(blockedDeletion.hint, 'Delete its relations first');
      await tester.binding.handlePopRoute();
      await _pumpUntilAbsent(tester, find.byType(Sheet));
      await _chooseDetailsTab(tester, 'Relations');
      final canGroup = find.byKey(
        const ValueKey('intention-relations-group-canUse'),
      );
      await _ensureVisible(tester, canGroup);
      await tester.tap(canGroup);
      await _tapWhenFound(tester, _relationRow(lifecyclePhrase));
      await _pumpUntilRelationSheet(tester, lifecyclePhrase);

      await _deleteCurrentRelation(tester, l10n);
      await _pumpUntilFound(tester, intentionOptionsButton);
      await _dismissOperationMessage(tester);
      expect(_relationRow(lifecyclePhrase), findsNothing);

      await _deleteCurrentIntention(tester);
      await _pumpUntilAbsent(tester, find.byType(IntentionDetailsPage));
      await _dismissOperationMessage(tester);
      await _returnToCatalog(tester);
      await _pumpUntilFound(tester, find.text('Много ходить'));
      expect(intentionCatalogRow('Укреплять здоровье'), findsNothing);
      expect(intentionCatalogRow('Много ходить'), findsOneWidget);

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
    'поиск связанного отмечает занятые пары и снимает отметку после удаления связи на странице из поиска',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final l10n = lookupAppLocalizations(const Locale('ru'));

      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      addTearDown(storage.dispose);
      await tester.runAsync(() async {
        await _seedOccupiedPairs(await storage.openReadyDatabase());
        await storage.closePersistenceObjectGraph();
      });
      final diagnostics = InMemoryDiagnosticsSink();
      final runtime = _fileRuntime(storage, diagnostics: diagnostics);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _pumpUntilFound);
      await _pumpUntilFound(tester, find.text(_healthy));

      await _openIntention(tester, _healthy);
      await _chooseDetailsTab(tester, l10n.detailsRelationsTab);
      final create = find.byKey(const ValueKey('intention-relations-add'));
      await _ensureVisible(tester, create);
      await tester.tap(create);
      final selectRelated = find.byKey(
        const ValueKey('relation-editor-select-related'),
      );
      await _pumpUntilFound(tester, selectRelated);
      await tester.tap(selectRelated);
      await _pumpUntilFound(tester, _pickerRow(_walk));
      await tester.pumpAndSettle(const Duration(milliseconds: 1));

      // Занятые пары отмечены, свободная строка обычная, а число не меняется.
      final order = _pickerRowTitles(tester);
      expect(order, unorderedEquals([_walk, _swim, _sleep]));
      expect(_pickerMarks(tester, l10n, _walk), [
        l10n.intentionPickerPairLinked,
      ]);
      expect(_pickerMarks(tester, l10n, _swim), [
        l10n.intentionPickerPairArchived,
      ]);
      expect(_pickerMarks(tester, l10n, _sleep), isEmpty);
      final header = tester.widget<CatalogHeader>(find.byType(CatalogHeader));
      expect(header.title, l10n.intentionPickerAllHeader);
      expect(header.count, 3);

      // Страница из поиска позволяет удалить занимающую связь.
      await tester.tap(
        find.descendant(
          of: _pickerRow(_walk),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DoableIcon &&
                widget.icon == DoableIconData.arrowUpRight,
            description: 'стрелка строки',
          ),
        ),
      );
      await _pumpUntilDetailsTitle(tester, _walk);
      await _chooseDetailsTab(tester, l10n.detailsRelationsTab);
      final neededFor = find.byKey(
        const ValueKey('intention-relations-group-neededFor'),
      );
      await _ensureVisible(tester, neededFor);
      await tester.tap(neededFor);
      final phrase = l10n.relationNeighborhoodNeedPhrase(_healthy, _walk);
      await _tapWhenFound(tester, _relationRow(phrase));
      await _pumpUntilRelationSheet(tester, phrase);
      await _deleteCurrentRelation(tester, l10n);
      await _pumpUntilFound(tester, intentionOptionsButton);
      await _dismissOperationMessage(tester);

      // Возврат в поиск показывает строку на прежнем месте без отметки.
      await tester.binding.handlePopRoute();
      await _pumpUntilFound(tester, _pickerRow(_walk));
      await _pumpUntilAbsent(tester, find.text(l10n.intentionPickerPairLinked));
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      expect(_pickerRowTitles(tester), order);
      expect(_pickerMarks(tester, l10n, _walk), isEmpty);
      expect(_pickerMarks(tester, l10n, _swim), [
        l10n.intentionPickerPairArchived,
      ]);
      expect(tester.widget<CatalogHeader>(find.byType(CatalogHeader)).count, 3);

      // Освобождённая строка выбирается как обычно.
      await tester.tap(
        find.descendant(of: _pickerRow(_walk), matching: find.text(_walk)),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('relation-editor-change-related')),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      expect(_pickerRow(_walk), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'восстановление из поиска при создании связи открывает связь с её собственными данными, а «назад» возвращает страницу начала создания',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final l10n = lookupAppLocalizations(const Locale('ru'));

      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      addTearDown(storage.dispose);
      await tester.runAsync(() async {
        await _seedArchivedSwimRelation(await storage.openReadyDatabase());
        await storage.closePersistenceObjectGraph();
      });
      final diagnostics = InMemoryDiagnosticsSink();
      late sqlite.Database raw;
      final runtime = _fileRuntime(
        storage,
        diagnostics: diagnostics,
        setup: (database) => raw = database,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _pumpUntilFound);
      await _pumpUntilFound(tester, find.text(_healthy));

      // Создание начато на странице «Быть здоровым»: в форме вид «можно»,
      // приоритет P4 и описание, которых нет у архивированной связи.
      await _openIntention(tester, _healthy);
      await _chooseDetailsTab(tester, l10n.detailsRelationsTab);
      final create = find.byKey(const ValueKey('intention-relations-add'));
      await _ensureVisible(tester, create);
      await tester.tap(create);
      final selectRelated = find.byKey(
        const ValueKey('relation-editor-select-related'),
      );
      await _pumpUntilFound(tester, selectRelated);
      for (final key in [
        'relation-editor-type-can',
        'relation-editor-priority-p4',
      ]) {
        final choice = find.byKey(ValueKey(key));
        await _ensureVisible(tester, choice);
        await tester.tap(choice);
        await tester.pump();
      }
      await tester.enterText(
        find.byKey(const ValueKey('relation-editor-description')),
        'Описание из формы',
      );
      await _ensureVisible(tester, selectRelated);
      await tester.tap(selectRelated);
      await _pumpUntilFound(tester, _pickerRow(_swim));
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      expect(_pickerMarks(tester, l10n, _swim), [
        l10n.intentionPickerPairArchived,
      ]);

      // Подтверждение предупреждает о том, что из формы не сохранится.
      await tester.tap(
        find.descendant(of: _pickerRow(_swim), matching: find.text(_swim)),
      );
      await _pumpUntilFound(
        tester,
        find.text(l10n.participantPickerRestoreTitle),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      expect(
        find.text(
          l10n.participantPickerRestoreWarning(
            [
              l10n.participantPickerRestoreWarningCanType,
              l10n.participantPickerRestoreWarningPriority,
              l10n.participantPickerRestoreWarningDescription,
            ].join(', '),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.participantPickerRestoreConfirm));

      // Вместо формы открыта панель той же связи с собственными данными.
      await _pumpUntilRelationSheet(
        tester,
        l10n.relationNeighborhoodNeedPhrase(_healthy, _swim),
      );
      expect(_relationHead(tester).kind, RelationHeadKind.need);
      expect(_relationHead(tester).status, isA<RelationHeadActive>());
      expect(_priorityPicker(tester).value, DoablePriority.p2);
      expect(_inRelationSheet(find.text(_swimDescription)), findsOneWidget);
      expect(
        raw.select(
          'SELECT id, source_intention_id, related_intention_id, type, '
          'priority, description, is_archived FROM long_term_relations',
        ),
        [
          {
            'id': _id(_swimRelationNumber),
            'source_intention_id': _id(1),
            'related_intention_id': _id(2),
            'type': 'need',
            'priority': 2,
            'description': _swimDescription,
            'is_archived': 0,
          },
        ],
      );
      expect(find.byType(RelationParticipantPickerPage), findsNothing);
      expect(find.byType(RelationEditorPage), findsNothing);

      // Успех предъявлен один раз и не повторяется после закрытия сообщения.
      final restored = find.text(
        l10n.graphOperationMessage(
          l10n.graphOperationRestore,
          l10n.graphOperationRelation,
          l10n.relationRestored,
        ),
      );
      await _pumpUntilFound(tester, restored.hitTestable());
      expect(restored.hitTestable(), findsOneWidget);
      await _dismissOperationMessage(tester);
      expect(restored, findsNothing);
      expect(
        diagnostics.events
            .whereType<LongTermRelationCommandDiagnosticsEvent>()
            .where((event) => event.status is DiagnosticsSucceeded)
            .map((event) => event.commandType),
        [LongTermRelationCommandDiagnosticsType.restore],
      );

      // «Назад» закрывает панель над страницей начала создания, а поиска и формы
      // нет в истории: следующее «назад» уходит в каталог.
      await _closeRelationSheet(tester);
      await _pumpUntilDetailsTitle(tester, _healthy);
      expect(
        find.byType(RelationParticipantPickerPage, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(RelationEditorPage, skipOffstage: false),
        findsNothing,
      );
      await _chooseDetailsTab(tester, l10n.detailsRelationsTab);
      await _pumpUntilFound(
        tester,
        _relationRow(l10n.relationNeighborhoodNeedPhrase(_healthy, _swim)),
      );
      expect(
        find.bySemanticsLabel(l10n.detailsRelationsTabSemantic(1, 0)),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await _pumpUntilFound(
        tester,
        find.byType(catalog_page.IntentionCatalogPage),
      );
      expect(
        find.byType(RelationEditorPage, skipOffstage: false),
        findsNothing,
      );
      semantics.dispose();
    },
  );
  testWidgets(
    'панель переводит связь из пути сохранённого выбора в другую группу, а подробный просмотр выбора показывает новый тип с прежним составом пути',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final l10n = lookupAppLocalizations(const Locale('ru'));

      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
      addTearDown(storage.dispose);
      await tester.runAsync(() async {
        final database = await storage.openReadyDatabase();
        await seedDurabilityGraph(database);
        expect(
          await durabilityRepository(database).execute(durabilityCreate()),
          isA<GraphCommandSucceeded>(),
        );
        await storage.closePersistenceObjectGraph();
      });
      final localDate = ControlledDailyChoiceLocalDate(durabilityChoiceDate);
      late sqlite.Database raw;
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () => openFileBackedLocalDatabase(
          storage.databaseFile,
          setup: (database) => raw = database,
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
        dailyChoiceLocalDateSource: localDate.read,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _pumpUntilFound);
      final repository = (await runtime.bootstrap() as AppRuntimeReady)
          .container
          .read(personalGraphRepositoryProvider);
      final choiceId = durabilityChoice(201);
      final before = await _readDailyChoice(repository, choiceId);
      expect(before.path.map((step) => step.relation.type), [
        LongTermRelationType.need,
        LongTermRelationType.can,
      ]);

      // Связь «нужно» из пути переводится панелью в группу «можно».
      await _pumpUntilFound(tester, find.text('Намерение 1'));
      await _openIntention(tester, 'Намерение 1');
      await _chooseDetailsTab(tester, l10n.detailsRelationsTab);
      final needPhrase = l10n.relationNeighborhoodNeedPhrase(
        'Намерение 1',
        'Намерение 2',
      );
      await _tapWhenFound(tester, _relationRow(needPhrase));
      await _pumpUntilRelationSheet(tester, needPhrase);
      await _chooseRelationKind(tester, l10n, RelationHeadKind.can);
      expect(_relationHead(tester).kind, RelationHeadKind.can);
      expect(
        find.bySemanticsLabel(
          l10n.relationNeighborhoodCanPhrase('Намерение 1', 'Намерение 2'),
        ),
        findsOneWidget,
      );
      expect(
        raw.select(
          'SELECT source_intention_id, related_intention_id, type '
          'FROM long_term_relations WHERE id = ?',
          [durabilityUuid(101)],
        ),
        [
          {
            'source_intention_id': durabilityUuid(1),
            'related_intention_id': durabilityUuid(2),
            'type': 'can',
          },
        ],
      );

      // Подробный просмотр выбора показывает новый тип связи.
      await _closeRelationSheet(tester);
      await _pumpUntilAbsent(tester, _relationRow(needPhrase));
      await tester.binding.handlePopRoute();
      await _pumpUntilFound(
        tester,
        find.byType(catalog_page.IntentionCatalogPage),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await openDailyChoices(tester, tap: _tapWhenFound);
      await _pumpUntilFound(
        tester,
        find.byKey(
          const ValueKey('daily-choice-section-true'),
          skipOffstage: false,
        ),
      );
      await showDailyChoiceCatalogSection(tester, true);
      await _tapWhenFound(
        tester,
        find.byKey(const ValueKey('daily-choice-row-1')),
      );
      await _pumpUntilFound(tester, dailyChoiceDetails);
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await showDailyChoicePath(tester, tap: _tapWhenFound);
      expect(
        find.descendant(
          of: dailyChoiceDetailsRelation(1),
          matching: find.text(l10n.relationNeighborhoodTypeCan),
        ),
        findsOneWidget,
      );

      // Состав пути, дата и выполнение прежние, меняется только тип.
      final after = await _readDailyChoice(repository, choiceId);
      expect(after.choice.date, before.choice.date);
      expect(after.choice.isCompleted, before.choice.isCompleted);
      expect(
        after.path.map((step) => (step.step.id, step.relation.id)),
        before.path.map((step) => (step.step.id, step.relation.id)),
      );
      expect(after.path.map((step) => step.relation.type), [
        LongTermRelationType.can,
        LongTermRelationType.can,
      ]);
      semantics.dispose();
    },
  );
}

Future<DailyChoiceDetails> _readDailyChoice(
  PersonalGraphRepository repository,
  DailyChoiceId id,
) async {
  final result = await repository.getDailyChoice(id);
  expect(result, isA<DailyChoiceReadSuccess>());
  return (result as DailyChoiceReadSuccess).value.value!;
}

const _healthy = 'Быть здоровым';
const _walk = 'Много ходить';
const _swim = 'Плавать';
const _sleep = 'Высыпаться';

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

/// Активные намерения «Быть здоровым», «Много ходить», «Плавать» и
/// «Высыпаться»; от первого идут активная связь к «Много ходить» и
/// архивированная к «Плаванью», а «Высыпаться» связано с ним обратной
/// связью, которая пару не занимает.
Future<void> _seedOccupiedPairs(AppDatabase database) =>
    seedGraph(database, () async {
      for (final (number, title) in [
        (1, _healthy),
        (2, _walk),
        (3, _swim),
        (4, _sleep),
      ]) {
        await database.customStatement(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, 0, ?, ?)',
          [_id(number), title, number, number],
        );
      }
      for (final (number, source, related, archived) in [
        (101, 1, 2, 0),
        (102, 1, 3, 1),
        (103, 4, 1, 0),
      ]) {
        await database.customStatement(
          'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 0, 0)',
          [_id(number), _id(source), _id(related), 'need', 2, archived],
        );
      }
    });

const _swimRelationNumber = 101;
const _swimDescription = '  Утреннее плавание\n🏊  ';

/// Активные намерения «Быть здоровым» и «Плавать» и архивированная связь
/// «Чтобы быть здоровым, нужно плавать» с приоритетом P2 и описанием.
Future<void> _seedArchivedSwimRelation(AppDatabase database) =>
    seedGraph(database, () async {
      for (final (number, title) in [(1, _healthy), (2, _swim)]) {
        await database.customStatement(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, 0, ?, ?)',
          [_id(number), title, number, number],
        );
      }
      await database.customStatement(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, description, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0)',
        [
          _id(_swimRelationNumber),
          _id(1),
          _id(2),
          'need',
          2,
          _swimDescription,
          1,
        ],
      );
    });

Finder _pickerRow(String title) => find.byWidgetPredicate(
  (widget) => widget is IntentionPickerRow && widget.summary.title == title,
  description: 'строка поиска участника «$title»',
);

/// Названия строк поиска участника в порядке показа.
List<String> _pickerRowTitles(WidgetTester tester) => tester
    .widgetList<IntentionPickerRow>(find.byType(IntentionPickerRow))
    .map((row) => row.summary.title)
    .toList();

/// Слова-отметки занятой пары в строке [title]: «Уже связано» или «Связь в
/// архиве».
List<String> _pickerMarks(
  WidgetTester tester,
  AppLocalizations l10n,
  String title,
) {
  final marks = {
    l10n.intentionPickerPairLinked,
    l10n.intentionPickerPairArchived,
  };
  return [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: _pickerRow(title), matching: find.byType(Text)),
    ))
      if (marks.contains(text.data)) text.data!,
  ];
}

AppRuntime _fileRuntime(
  LocalDatabaseHarness database, {
  required InMemoryDiagnosticsSink diagnostics,
  DatabaseSetup? setup,
}) => AppRuntime(
  quickCreationModeStore: InMemoryQuickCreationModeStore(),
  connectionFactory: () =>
      openFileBackedLocalDatabase(database.databaseFile, setup: setup),
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
  final titleFinder = find.descendant(
    of: find.byType(IntentionDetailsPage),
    matching: find.text(title),
  );
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    if (titleFinder.hitTestable().evaluate().isNotEmpty) {
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
  bool waitForTerminalOutcome = true,
  bool verifyFormSemantics = false,
}) async {
  await _chooseDetailsTab(tester, 'Relations');
  final create = find.byKey(const ValueKey('intention-relations-add'));
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
  await _pumpUntilAbsent(tester, submit);
  await _pumpUntilFound(tester, _inRelationSheet(find.text(description)));
  // Панель созданной связи стоит над исходным намерением, формы под ней нет.
  await _closeRelationSheet(tester);
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('intention-relations-add')),
  );
}

/// Панель связи, открытая над страницей. Параметры связи — тоже лист, поэтому
/// пока они открыты, листов два.
final _relationSheet = find.byType(Sheet);

/// Часть панели связи, которая лежит внутри листа.
Finder _inRelationSheet(Finder matching) =>
    find.descendant(of: _relationSheet, matching: matching);

RelationHead _relationHead(WidgetTester tester) =>
    tester.widget<RelationHead>(find.byType(RelationHead));

PriorityPicker _priorityPicker(WidgetTester tester) =>
    tester.widget<PriorityPicker>(find.byType(PriorityPicker));

/// Ждёт панель с прочитанной связью, названную [label], и конца её анимации.
Future<void> _pumpUntilRelationSheet(WidgetTester tester, String label) async {
  await _pumpUntilFound(tester, find.bySemanticsLabel(label));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Ждёт, пока шапка панели покажет состояние [S]: активную или архивированную
/// связь.
Future<void> _pumpUntilRelationHead<S extends RelationHeadStatus>(
  WidgetTester tester,
) async {
  await _pumpUntilFound(
    tester,
    find.byWidgetPredicate(
      (widget) => widget is RelationHead && widget.status is S,
      description: 'шапка связи в состоянии $S',
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Future<void> _choosePriority(
  WidgetTester tester,
  DoablePriority priority,
) async {
  await tester.tap(_inRelationSheet(find.text('P${priority.index + 1}')));
  await _pumpUntilFound(
    tester,
    find.byWidgetPredicate(
      (widget) => widget is PriorityPicker && widget.value == priority,
      description: 'приоритет $priority',
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Future<void> _chooseRelationKind(
  WidgetTester tester,
  AppLocalizations l10n,
  RelationHeadKind kind,
) async {
  final name = switch (kind) {
    RelationHeadKind.need => l10n.relationNeighborhoodTypeNeed,
    RelationHeadKind.can => l10n.relationNeighborhoodTypeCan,
  };
  await tester.tap(_inRelationSheet(find.text(name)));
  await _pumpUntilFound(
    tester,
    find.byWidgetPredicate(
      (widget) => widget is RelationHead && widget.kind == kind,
      description: 'шапка связи вида $kind',
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Меняет описание в полном размере панели и ждёт возврата к её обычному виду.
Future<void> _saveRelationDescription(
  WidgetTester tester,
  AppLocalizations l10n, {
  required String current,
  required String text,
}) async {
  await tester.tap(_inRelationSheet(find.text(current)));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.enterText(_inRelationSheet(find.byType(TextField)), text);
  await tester.pump();
  final save = find.text(l10n.relationSheetDescriptionSave);
  await tester.tap(save);
  await _pumpUntilAbsent(tester, save);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Открывает параметры связи и выбирает пункт [name]. Лист параметров
/// закрывается до начала действия.
Future<void> _chooseRelationOption(
  WidgetTester tester,
  AppLocalizations l10n,
  String name,
) async {
  final option = find.byWidgetPredicate(
    (widget) => widget is OptionRow && widget.name == name,
    description: 'пункт «$name»',
  );
  await _tapWhenFound(
    tester,
    find.bySemanticsLabel(l10n.relationSheetOptionsLabel),
  );
  await _pumpUntilFound(tester, option);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.tap(option);
  await _pumpUntilAbsent(tester, find.byType(OptionRow));
}

Future<void> _closeRelationSheet(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _pumpUntilAbsent(tester, _relationSheet);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Future<void> _openArchivedCanRelation(
  WidgetTester tester, {
  required String participantTitle,
  required String phrase,
  required String sheetLabel,
}) async {
  await _openIntention(tester, participantTitle);
  await _chooseDetailsTab(tester, 'Relations');
  final canUse = find.byKey(const ValueKey('intention-relations-group-canUse'));
  await _pumpUntilFound(tester, canUse);
  await _ensureVisible(tester, canUse);
  await tester.tap(canUse);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await _expandArchive(tester);

  await _tapWhenFound(tester, _relationRow(phrase));
  await _pumpUntilRelationSheet(tester, sheetLabel);
}

/// Удаляет связь на открытой панели; удаление закрывает панель.
Future<void> _deleteCurrentRelation(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await _chooseRelationOption(tester, l10n, l10n.relationSheetOptionDelete);
  await _pumpUntilFound(tester, find.text(l10n.relationSheetDeleteDialogTitle));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.tap(find.text(l10n.relationSheetDeleteDialogConfirm));
  await _pumpUntilAbsent(tester, _relationSheet);
}

/// Удаление становится доступным, когда сводка страницы подтвердит
/// отсутствие связей; открытый лист следит за ней.
Future<void> _deleteCurrentIntention(WidgetTester tester) async {
  await _openIntentionOptions(tester);
  final delete = intentionOption(IntentionOption.delete);
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    if (tester.widget<OptionRow>(delete).onPressed != null) break;
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(tester.widget<OptionRow>(delete).hint, 'Its tags stay');
  await tester.tap(delete);
  await _tapWhenFound(tester, intentionDeletionConfirm);
}

Future<void> _openIntentionOptions(WidgetTester tester) async {
  await _tapWhenFound(tester, intentionOptionsButton);
  await _pumpUntilFound(tester, find.byType(Sheet));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Выбор закрывает лист и сразу начинает действие на странице.
Future<void> _chooseIntentionOption(
  WidgetTester tester,
  IntentionOption option,
) async {
  await _openIntentionOptions(tester);
  await tester.tap(intentionOption(option));
  await _pumpUntilAbsent(tester, find.byType(Sheet));
}

Future<void> _returnToCatalog(WidgetTester tester) async {
  final catalog = find.byType(catalog_page.IntentionCatalogPage);
  for (var attempt = 0; attempt < 4; attempt += 1) {
    if (catalog.evaluate().isNotEmpty) {
      return;
    }
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
  }
  fail('App-level поток не вернулся в каталог после удаления намерения.');
}

Future<void> _renameCurrentIntention(WidgetTester tester, String title) async {
  await _ensureVisible(tester, intentionHeadTitle);
  await tester.tap(intentionHeadTitle);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.enterText(intentionEditTitleField, title);
  await tester.pump();
  await tester.tap(intentionEditSave);
  await _pumpUntilAbsent(tester, find.byType(IntentionEditPage));
  await _pumpUntilDetailsTitle(tester, title);
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

/// Строка вкладки «Связи», доступное имя которой начинается с формулировки
/// связи [phrase].
Finder _relationRow(String phrase) => find.byWidgetPredicate(
  (widget) =>
      widget is RelationRow && widget.semanticLabel.startsWith('$phrase. '),
);

/// Раскрывает свёрнутый архив выбранной группы, когда его строка появится.
Future<void> _expandArchive(WidgetTester tester) async {
  final fold = find.descendant(
    of: find.byType(ArchivedFold),
    matching: find.byType(TextButton),
  );
  await _pumpUntilFound(tester, fold);
  await _ensureVisible(tester, fold);
  await tester.tap(fold);
  await tester.pump();
}

extension<T> on T {
  T also(void Function(T value) action) {
    action(this);
    return this;
  }
}

Future<void> _chooseDetailsTab(WidgetTester tester, String label) async {
  final tab = find.text(label).first;
  await _pumpUntilFound(tester, tab);
  await _ensureVisible(tester, tab);
  await tester.tap(tab);
  await tester.pump();
}
