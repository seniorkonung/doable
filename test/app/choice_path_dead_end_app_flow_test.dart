import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_view_model.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/components/relation_row.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_row.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_root_pages.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';
import '../support/intention_edit_screen.dart';
import '../support/intention_choices_tab.dart';
import '../support/quick_creation.dart';
import '../support/graph_seed.dart';

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 500; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail(
    'Не появился элемент: $finder; тексты: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.tap(finder);
  await tester.pump();
}

Future<AppRuntime> _start(
  WidgetTester tester,
  ChoicePathDraftDirection direction, {
  ChoicePathPurpose purpose = ChoicePathPurpose.create,
  Locale locale = const Locale('ru'),
  int? startingNumber,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  final db = await storage.openReadyDatabase();
  await seedDurabilityGraph(db);
  await seedGraph(
    db,
    () => db.customStatement(
      'UPDATE intentions SET is_action_ready = 1 WHERE id = ?',
      [durabilityUuid(5)],
    ),
  );
  await storage.closePersistenceObjectGraph();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openFileBackedLocalDatabase(storage.databaseFile),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
    await storage.dispose();
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
  await openIntentionGraph(tester, waitFor: _until);
  await _until(tester, find.text('Намерение 1'));
  await _tap(tester, find.text('Намерение 1').first);
  await _until(tester, find.byType(IntentionDetailsPage));
  final context = tester.element(find.byType(IntentionDetailsPage));
  final startingId = durabilityIntention(
    startingNumber ?? (direction == ChoicePathDraftDirection.bottomUp ? 4 : 1),
  );
  if (purpose == ChoicePathPurpose.create) {
    unawaited(
      context.router.push(
        ChoicePathRoute(sourceIntentionId: startingId, direction: direction),
      ),
    );
  } else {
    final page = purpose == ChoicePathPurpose.refreshCreation
        ? ChoicePathPage.forCreationRefresh(
            startingIntentionId: startingId,
            direction: direction,
            pathInstance: ChoicePathPageInstance(),
          )
        : ChoicePathPage.forReplacement(
            startingIntentionId: startingId,
            direction: direction,
          );
    unawaited(
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page)),
    );
  }
  await tester.pump();
  return runtime;
}

Finder _continuation(int number) =>
    find.byKey(ValueKey('choice-path-continue-${durabilityUuid(number)}'));

Finder _pickerTitle(String title) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is IntentionPickerRow && widget.summary.title == title,
  ),
  matching: find.text(title),
);

Finder _relationRow(String phrase) => find.byWidgetPredicate(
  (widget) =>
      widget is RelationRow && widget.semanticLabel.startsWith('$phrase. '),
);

Future<void> _add(WidgetTester tester, String title) async {
  await _tap(tester, find.byKey(const ValueKey('intention-relations-add')));
  await _tap(tester, _pickerTitle(title));
  await _tap(
    tester,
    find.text(lookupAppLocalizations(const Locale('ru')).batchAddCount(1)),
  );
  for (
    var i = 0;
    i < 500 && find.byType(RelationBatchPickerPage).evaluate().isNotEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(find.byType(RelationBatchPickerPage), findsNothing);
}

Future<void> _priority(WidgetTester tester, String phrase) async {
  await _tap(tester, _relationRow(phrase));
  final picker = find.byType(PriorityPicker);
  await _until(tester, picker);
  await _tap(
    tester,
    find.descendant(of: find.byType(Sheet), matching: find.text('P1')),
  );
  for (var i = 0; i < 500; i++) {
    if (tester.widget<PriorityPicker>(picker).value == DoablePriority.p1) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Приоритет не изменился');
}

void main() {
  for (final fromQuickButton in [false, true]) {
    testWidgets(
      'второй выбор через ${fromQuickButton ? 'быструю кнопку' : 'вкладку'} не меняет первый путь',
      (tester) async {
        await _start(
          tester,
          ChoicePathDraftDirection.topDown,
          startingNumber: 3,
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('choice-path-open-relations')),
        );
        await _add(tester, 'Намерение 4');

        if (fromQuickButton) {
          await openDailyChoiceQuickCreation(
            tester,
            ChoicePathDraftDirection.topDown,
            openedPage: find.byType(DailyChoiceSourcePickerPage),
            wait: _until,
          );
          await _tap(tester, _pickerTitle('Намерение 3'));
        } else {
          await startDailyChoiceFromIntentionChoices(
            tester,
            waitFor: _until,
            tap: _tap,
          );
        }
        await _until(tester, find.textContaining('Намерение 4'));
        final semantics = tester.ensureSemantics();
        await tester.pump();
        expect(find.bySemanticsLabel(RegExp('Шаг 1:')), findsNothing);
        await _tap(tester, find.textContaining('Намерение 4').last);
        await _until(tester, find.byKey(const ValueKey('choice-path-empty')));
        expect(find.bySemanticsLabel(RegExp('Шаг 1:')), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await _until(tester, find.textContaining('Намерение 4'));
        expect(find.byKey(const ValueKey('choice-path-empty')), findsNothing);
        expect(find.textContaining('Намерение 3'), findsWidgets);
        expect(find.bySemanticsLabel(RegExp('Шаг 1:')), findsNothing);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'добавленная из тупика связь становится продолжением прежнего пути',
    (tester) async {
      await _start(tester, ChoicePathDraftDirection.topDown);
      await _tap(tester, _continuation(101));
      await _tap(tester, _continuation(102));
      await _tap(
        tester,
        find.byKey(const ValueKey('choice-path-open-relations')),
      );
      await _until(
        tester,
        find.byKey(const ValueKey('intention-relations-add')),
      );
      expect(find.text('Намерение 3'), findsWidgets);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      await _add(tester, 'Намерение 4');
      await _priority(
        tester,
        l10n.relationNeighborhoodNeedPhrase('Намерение 3', 'Намерение 4'),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _add(tester, 'Намерение 5');

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      await _tap(tester, intentionHeadTitle);
      await _until(tester, intentionEditTitleField);
      await tester.enterText(intentionEditTitleField, 'Новое название');
      await _tap(tester, intentionEditSave);
      await _until(tester, find.text('Новое название'));
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-relations-group-canBeUsedFor')),
      );
      await _priority(
        tester,
        l10n.relationNeighborhoodCanPhrase('Намерение 2', 'Новое название'),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle(const Duration(milliseconds: 1));
      await _until(tester, find.textContaining('Намерение 4'));
      await _until(tester, find.textContaining('Намерение 5'));
      expect(find.textContaining('Намерение 1'), findsWidgets);
      expect(find.textContaining('Намерение 2'), findsWidgets);
      expect(find.textContaining('Новое название'), findsWidgets);
      expect(find.byKey(const ValueKey('choice-path-conflict')), findsNothing);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp('Шаг 2: .*Новое название.*Приоритет P1')),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('choice-path-select-action')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('choice-path-open-confirmation')),
      );
      expect(
        find.bySemanticsLabel(RegExp('Шаг 2: .*Новое название.*Приоритет P1')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('связь с неготовым намерением не становится продолжением', (
    tester,
  ) async {
    await _start(tester, ChoicePathDraftDirection.topDown);
    await _tap(tester, _continuation(101));
    await _tap(tester, _continuation(102));
    await _tap(
      tester,
      find.byKey(const ValueKey('choice-path-open-relations')),
    );
    await _tap(tester, find.byKey(const ValueKey('intention-relations-add')));
    await _until(
      tester,
      find.byKey(const ValueKey('participant-picker-filter')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('participant-picker-filter')),
      'Гулять по вечерам',
    );
    await _tap(tester, find.text('Создать «Гулять по вечерам»'));
    await _tap(tester, find.byKey(const ValueKey('intention-editor-submit')));
    await _tap(
      tester,
      find.text(lookupAppLocalizations(const Locale('ru')).batchAddCount(1)),
    );
    await _until(
      tester,
      _relationRow('Чтобы Намерение 3, нужно Гулять по вечерам'),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _until(tester, find.byKey(const ValueKey('choice-path-empty')));
    expect(find.textContaining('Намерение 1'), findsWidgets);
    expect(find.textContaining('Намерение 2'), findsWidgets);
    expect(find.textContaining('Намерение 3'), findsWidgets);
    expect(find.byKey(const ValueKey('choice-path-conflict')), findsNothing);
    expect(
      find.textContaining(
        'Продолжениями становятся только связи, ведущие к готовому действию.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Отметьте намерение готовым или свяжите его с действием.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('тупик снизу вверх открывает группу «Нужно для»', (tester) async {
    await _start(tester, ChoicePathDraftDirection.bottomUp);
    await _tap(tester, _continuation(103));
    await _tap(
      tester,
      find.byKey(const ValueKey('choice-path-open-relations')),
    );
    final l10n = lookupAppLocalizations(const Locale('ru'));
    await _until(tester, find.text(l10n.detailsRelationsNeededForHint));
    expect(find.text(l10n.detailsRelationsNeededForHint), findsOneWidget);
    expect(find.text('Намерение 1'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('choice-path-empty')), findsOneWidget);
  });

  for (final purpose in [
    ChoicePathPurpose.refreshCreation,
    ChoicePathPurpose.replace,
  ]) {
    testWidgets(
      'построение для ${purpose.name} возвращается из связей к прежнему пути',
      (tester) async {
        await _start(
          tester,
          ChoicePathDraftDirection.topDown,
          purpose: purpose,
          locale: const Locale('en'),
        );
        await _tap(tester, _continuation(101));
        await _tap(tester, _continuation(102));
        await _tap(tester, find.text('Open relations'));
        final l10n = lookupAppLocalizations(const Locale('en'));
        await _until(tester, find.text(l10n.detailsRelationsNeedsHint));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.textContaining('Намерение 2'), findsWidgets);
        expect(find.textContaining('Намерение 3'), findsWidgets);
        expect(find.text('Open relations'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'удаление добавленной в тупике связи возвращает прежний путь без продолжений',
    (tester) async {
      await _start(tester, ChoicePathDraftDirection.topDown);
      await _tap(tester, _continuation(101));
      await _tap(tester, _continuation(102));
      await _tap(
        tester,
        find.byKey(const ValueKey('choice-path-open-relations')),
      );
      await _add(tester, 'Намерение 4');
      final l10n = lookupAppLocalizations(const Locale('ru'));
      await _tap(
        tester,
        _relationRow(
          l10n.relationNeighborhoodNeedPhrase('Намерение 3', 'Намерение 4'),
        ),
      );
      await _tap(tester, find.bySemanticsLabel(l10n.relationSheetOptionsLabel));
      await _tap(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is OptionRow &&
              widget.name == l10n.relationSheetOptionDelete,
        ),
      );
      await _tap(tester, find.text(l10n.relationSheetDeleteDialogConfirm));
      for (
        var i = 0;
        i < 500 && find.byType(Sheet).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byType(Sheet), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _until(tester, find.byKey(const ValueKey('choice-path-empty')));
      expect(find.textContaining('Намерение 2'), findsWidgets);
      expect(find.textContaining('Намерение 3'), findsWidgets);
      expect(find.byKey(const ValueKey('choice-path-conflict')), findsNothing);
    },
  );

  for (final isEmpty in [true, false]) {
    testWidgets(
      'изменение пути при ${isEmpty ? 'тупике' : 'показе продолжений'} вызывает конфликт',
      (tester) async {
        final runtime = await _start(tester, ChoicePathDraftDirection.topDown);
        await _tap(tester, _continuation(101));
        if (isEmpty) {
          await _tap(tester, _continuation(102));
          await _until(tester, find.byKey(const ValueKey('choice-path-empty')));
        } else {
          await _until(tester, _continuation(102));
        }
        final ready = await runtime.bootstrap() as AppRuntimeReady;
        final coordinator = ready.container.read(
          graphCommandCoordinatorProvider.notifier,
        );
        final accepted = coordinator.acceptRelationArchive(
          ArchiveLongTermRelation(durabilityRelation(isEmpty ? 102 : 101)),
        ) as LongTermRelationCommandAccepted;
        final result = await tester.runAsync(() => accepted.future);
        expect(result!.confirmedResult, isA<GraphCommandSucceeded>());
        await _until(
          tester,
          find.byKey(const ValueKey('choice-path-conflict')),
        );
        expect(
          find.byKey(const ValueKey('choice-path-refresh')),
          findsOneWidget,
        );
      },
    );
  }
}
