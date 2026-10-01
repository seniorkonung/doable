import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_status_views.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/tag_storage_fixture.dart';

const _health = 301;
const _sport = 302;
const _rest = 303;

/// Связь сохранённого дневного пути: её участники защищены от замены.
const _pathRelation = 101;
const _archivedRelation = 102;
const _activeRelation = 103;
const _dailyChoice = 201;

/// Строка результата: название и строка тегов так, как они показаны.
typedef _Row = (String title, String tags);

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets(
      'каталог совместно применяет название, обязательные и исключённые теги на $code',
      (tester) async {
        final app = await _App.pump(tester, locale);
        final l10n = app.l10n;
        const page = IntentionCatalogPage;
        final before = _storedGraph(app.raw);
        final changesBefore = _connectionChanges(app.raw);
        final health = l10n.intentionSummaryTags('Здоровье');
        final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
        final all = l10n.intentionSummaryTags('Здоровье, Спорт, Отдых');

        // Теги видны и без условий; одноимённые намерения остаются отдельными.
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Гулять без тегов', l10n.intentionSummaryNoTags),
          ('Читать в тишине', healthRest),
          ('Ходить в зал', all),
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(6)), findsOneWidget);
        expect(_conditions(tester, page), isEmpty);

        // Поиск только по обязательным тегам.
        await _addCondition(tester, _health, present: true);
        await _addCondition(tester, _rest, present: true);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Читать в тишине', healthRest),
          ('Ходить в зал', all),
          ('Ходить в парк', healthRest),
        ]);
        await _addCondition(tester, _sport, present: false);
        final combined = [
          'Здоровье',
          'Отдых',
          l10n.intentionTagConditionAbsent('Спорт'),
        ];
        expect(_conditions(tester, page), combined);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Читать в тишине', healthRest),
          ('Ходить в парк', healthRest),
        ]);

        // Название, обязательные и исключённые теги действуют одновременно.
        await tester.enterText(
          find.byKey(const ValueKey('catalog-filter-field')),
          'ходить',
        );
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(2)), findsOneWidget);

        // Смена охвата сохраняет совместный фильтр.
        await _selectScope(tester, l10n.catalogScopeArchived);
        await _expectResults(tester, page, [('Ходить в парк', healthRest)]);
        expect(find.text(l10n.catalogTotalCount(1)), findsOneWidget);
        expect(_conditions(tester, page), combined);
        await _selectScope(tester, l10n.catalogScopeActive);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Ходить в парк', healthRest),
        ]);

        // Уже выбранный тег отмечен; закрытие без выбора сохраняет условия.
        await _tap(
          tester,
          find.byKey(const ValueKey('intention-tag-conditions-add')),
        );
        final sportRow = find.byKey(
          ValueKey('tag-condition-picker-row-${tagFixtureId(_sport)}'),
        );
        await _until(tester, sportRow);
        expect(
          find.descendant(
            of: sportRow,
            matching: find.text(l10n.tagConditionPickerSelectedAbsent),
          ),
          findsOneWidget,
        );
        await _closeTop(tester, TagConditionPickerPage);
        expect(_conditions(tester, page), combined);

        // Повторный выбор тега меняет надобность, а не добавляет условие.
        await _addCondition(tester, _sport, present: true);
        expect(_conditions(tester, page), ['Здоровье', 'Отдых', 'Спорт']);
        await _expectResults(tester, page, [('Ходить в зал', all)]);
        await _tap(
          tester,
          find.byKey(
            ValueKey('intention-tag-condition-toggle-${tagFixtureId(_sport)}'),
          ),
        );
        expect(_conditions(tester, page), combined);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Ходить в парк', healthRest),
        ]);

        // Поиск только с исключением допускает намерение без тегов.
        await tester.enterText(
          find.byKey(const ValueKey('catalog-filter-field')),
          '',
        );
        await _removeCondition(tester, _health);
        await _removeCondition(tester, _rest);
        expect(_conditions(tester, page), [
          l10n.intentionTagConditionAbsent('Спорт'),
        ]);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Гулять без тегов', l10n.intentionSummaryNoTags),
          ('Читать в тишине', healthRest),
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);

        // Пустая выдача по условиям отличается от пустого охвата.
        await _tap(
          tester,
          find.byKey(
            ValueKey('intention-tag-condition-toggle-${tagFixtureId(_sport)}'),
          ),
        );
        await _addCondition(tester, _health, present: false);
        await _until(tester, find.text(l10n.catalogTagConditionsEmpty));
        expect(find.text(l10n.catalogActiveEmpty), findsNothing);
        expect(_results(tester, page), isEmpty);

        // Поиск не выполняет команд тегов и не меняет граф.
        expect(_storedGraph(app.raw), before);
        expect(_connectionChanges(app.raw), changesBefore);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'поиски действия и исходного намерения сохраняют ограничения и независимость условий на $code',
      (tester) async {
        final app = await _App.pump(tester, locale);
        final l10n = app.l10n;
        final before = _storedGraph(app.raw);
        final health = l10n.intentionSummaryTags('Здоровье');
        final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
        final all = l10n.intentionSummaryTags('Здоровье, Спорт, Отдых');
        const catalog = BrowseIntentionCatalog();
        const action = DailyChoiceActionPickerPage;
        const source = DailyChoiceSourcePickerPage;

        await _addCondition(tester, _rest, present: true);
        await _expectResults(tester, IntentionCatalogPage, [
          ('Ходить в парк', healthRest),
          ('Читать в тишине', healthRest),
          ('Ходить в зал', all),
          ('Ходить в парк', healthRest),
        ]);

        // Создание выбора: только активные готовые намерения, теги видны
        // без условий, условия каталога в поиск действия не переносятся.
        await _tap(
          tester,
          find.byKey(const ValueKey('catalog-open-daily-choices')),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-create-from-action')),
        );
        await _until(tester, find.byType(action));
        await _expectResults(tester, action, [
          ('Ходить в зал', all),
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);
        expect(_conditions(tester, action), isEmpty);
        await _addCondition(tester, _health, present: true);
        await _addCondition(tester, _sport, present: false);
        final actionConditions = [
          'Здоровье',
          l10n.intentionTagConditionAbsent('Спорт'),
        ];
        expect(_conditions(tester, action), actionConditions);
        await _expectResults(tester, action, [
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.actionPickerTotalCount(2)), findsOneWidget);

        // Изменение условий каталога не меняет открытый поиск действия.
        app.container
            .read(intentionTagConditionsViewModelProvider(catalog).notifier)
            .toggleRequirement(_tag(_rest));
        await tester.pumpAndSettle();
        expect(
          app.container
              .read(intentionTagConditionsViewModelProvider(catalog))
              .tagFilter
              .excludedTagIds,
          {_tag(_rest)},
        );
        expect(_conditions(tester, action), actionConditions);
        await _expectResults(tester, action, [
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);

        // Явный выбор действия по идентификатору открывает путь выбора.
        await _tap(
          tester,
          find.descendant(
            of: find.byKey(ValueKey('daily-choice-action-${tagFixtureId(1)}')),
            matching: find.byType(IntentionSummaryView),
          ),
        );
        await _until(tester, find.byType(ChoicePathPage));
        await _waitFor(tester, () => find.byType(action).evaluate().isEmpty);
        await _closeTop(tester, ChoicePathPage);

        // Дневной путь тегами и условиями не дополняется.
        unawaited(
          app.router.push(
            DailyChoiceDetailsRoute(
              choiceId: (DailyChoiceId.decode(
                tagFixtureId(_dailyChoice),
              ) as DailyChoiceIdDecodingSuccess).id,
            ),
          ),
        );
        final replace = find.byKey(const ValueKey('daily-choice-replace-open'));
        await _until(tester, replace);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(DailyChoiceDetailsPage),
            matching: find.byType(IntentionTagConditionsSection),
          ),
          findsNothing,
        );
        expect(find.text(healthRest), findsNothing);
        expect(find.text(health), findsNothing);
        expect(find.text(l10n.intentionSummaryNoTags), findsNothing);

        // Замена пути использует тот же поиск действия; условия закрытого
        // поиска не сохраняются.
        await _tap(tester, replace);
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-bottom-up')),
        );
        await _until(tester, find.byType(action));
        await tester.pumpAndSettle();
        expect(_conditions(tester, action), isEmpty);
        await _addCondition(tester, _health, present: true);
        await _addCondition(tester, _sport, present: false);
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-action-filter')),
          'ходить',
        );
        await _expectResults(tester, action, [
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-action-cancel')),
        );
        await _waitFor(tester, () => find.byType(action).evaluate().isEmpty);

        // Исходное намерение: любые активные независимо от готовности.
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-replace-top-down')),
        );
        await _until(tester, find.byType(source));
        await tester.pumpAndSettle();
        expect(_conditions(tester, source), isEmpty);
        await _addCondition(tester, _health, present: true);
        await _addCondition(tester, _sport, present: false);
        await _expectResults(tester, source, [
          ('Ходить в парк', healthRest),
          ('Читать в тишине', healthRest),
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.sourcePickerTotalCount(4)), findsOneWidget);

        // Отмена поиска сохраняет прежний дневной выбор и весь граф.
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-choice-source-cancel')),
        );
        await _waitFor(tester, () => find.byType(source).evaluate().isEmpty);
        await tester.pumpAndSettle();
        expect(_storedGraph(app.raw), before);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'поиск участника связи сохраняет охват и исключает второго участника на $code',
      (tester) async {
        final app = await _App.pump(tester, locale);
        final l10n = app.l10n;
        final before = _storedGraph(app.raw);
        final health = l10n.intentionSummaryTags('Здоровье');
        final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
        final all = l10n.intentionSummaryTags('Здоровье, Спорт, Отдых');
        const picker = RelationParticipantPickerPage;
        const filter = ValueKey('participant-picker-filter-field');

        // Активная связь: только активные намерения, готовность не важна,
        // второй участник «Ходить в парк» исключён по идентификатору.
        await app.openParticipantPicker(tester, _activeRelation);
        await _expectResults(tester, picker, [
          ('Ходить в парк', healthRest),
          ('Гулять без тегов', l10n.intentionSummaryNoTags),
          ('Читать в тишине', healthRest),
          ('Ходить в зал', all),
          ('Ходить до магазина', health),
        ]);
        await _addCondition(tester, _health, present: true);
        await _addCondition(tester, _sport, present: false);
        await _expectResults(tester, picker, [
          ('Ходить в парк', healthRest),
          ('Читать в тишине', healthRest),
          ('Ходить до магазина', health),
        ]);
        await tester.enterText(find.byKey(filter), 'ходить в парк');
        await _expectResults(tester, picker, [('Ходить в парк', healthRest)]);
        expect(
          find.descendant(
            of: find.byType(picker),
            matching: find.text(l10n.detailsArchived),
          ),
          findsNothing,
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('participant-picker-cancel')),
        );
        await _waitFor(tester, () => find.byType(picker).evaluate().isEmpty);
        await tester.pumpAndSettle();
        expect(_storedGraph(app.raw), before);
        while (app.router.canPop()) {
          unawaited(app.router.maybePop());
          await tester.pumpAndSettle();
        }

        // Архивированная связь: активное и архивированное одноимённые
        // намерения доступны отдельно с различимым архивным состоянием.
        await app.openParticipantPicker(tester, _archivedRelation);
        expect(_conditions(tester, picker), isEmpty);
        await _addCondition(tester, _health, present: true);
        await _addCondition(tester, _sport, present: false);
        await tester.enterText(find.byKey(filter), 'ходить в парк');
        await _expectResults(tester, picker, [
          ('Ходить в парк', healthRest),
          ('Ходить в парк', healthRest),
        ]);
        final options = find.descendant(
          of: find.byType(picker),
          matching: find.byType(IntentionSummaryView),
        );
        expect(
          find.descendant(
            of: options.first,
            matching: find.text(l10n.detailsActive),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: options.last,
            matching: find.text(l10n.detailsArchived),
          ),
          findsOneWidget,
        );

        // Явный выбор закрывает поиск и не меняет сохранённую связь.
        await _tap(tester, options.first);
        await _waitFor(tester, () => find.byType(picker).evaluate().isEmpty);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const ValueKey('relation-editor-participant-title-related'),
                ),
              )
              .data,
          'Ходить в парк',
        );
        expect(_storedGraph(app.raw), before);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'открытый поиск согласует подтверждённые изменения тегов и отказ обновления на $code',
      (tester) async {
        final app = await _App.pump(tester, locale);
        final l10n = app.l10n;
        const page = IntentionCatalogPage;
        const purpose = BrowseIntentionCatalog();
        final health = l10n.intentionSummaryTags('Здоровье');
        final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
        final wellRest = l10n.intentionSummaryTags('Самочувствие, Отдых');
        final well = l10n.intentionSummaryTags('Самочувствие');
        final absentSport = l10n.intentionTagConditionAbsent('Спорт');

        await _addCondition(tester, _health, present: true);
        await _addCondition(tester, _sport, present: false);
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Читать в тишине', healthRest),
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(4)), findsOneWidget);

        // Назначение создаёт совпадение на своей позиции порядка.
        await app.completeTag(
          tester,
          (coordinator) => coordinator.acceptTagAssign(
            AssignTag(tagId: _tag(_health), intentionId: _intention(6)),
          ),
        );
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Гулять без тегов', health),
          ('Читать в тишине', healthRest),
          ('Ходить до магазина', health),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(5)), findsOneWidget);

        // Снятие обязательного тега исключает намерение.
        await app.completeTag(
          tester,
          (coordinator) => coordinator.acceptTagRemoveAssignment(
            RemoveTagAssignment(
              tagId: _tag(_health),
              intentionId: _intention(2),
            ),
          ),
        );
        await _expectResults(tester, page, [
          ('Ходить в парк', healthRest),
          ('Гулять без тегов', health),
          ('Читать в тишине', healthRest),
          ('Ходить в парк', healthRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(4)), findsOneWidget);

        // Переименование обновляет строки и чип, сохраняя совпадения.
        await app.completeTag(
          tester,
          (coordinator) => coordinator.acceptTagRename(
            RenameTag(
              tagId: _tag(_health),
              name: TagName.fromInput('Самочувствие'),
            ),
          ),
        );
        await _expectResults(tester, page, [
          ('Ходить в парк', wellRest),
          ('Гулять без тегов', well),
          ('Читать в тишине', wellRest),
          ('Ходить в парк', wellRest),
        ]);
        expect(_conditions(tester, page), ['Самочувствие', absentSport]);
        expect(find.text(l10n.catalogTotalCount(4)), findsOneWidget);

        // Управляемый отказ SQLite при обновлении после удаления исключённого
        // тега: сохранённая выдача показана как не обновлённая.
        app.fault.failure = sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
          message: 'занято',
        );
        await app.completeTag(
          tester,
          (coordinator) => coordinator.acceptTagDelete(DeleteTag(_tag(_sport))),
        );
        await _until(tester, find.text(l10n.catalogRefreshUnavailable));
        expect(app.fault.failedReads, greaterThan(0));
        final deletedSport = l10n.intentionTagConditionDeleted(absentSport);
        expect(_conditions(tester, page), ['Самочувствие', deletedSport]);
        expect(_results(tester, page), [
          ('Ходить в парк', wellRest),
          ('Гулять без тегов', well),
          ('Читать в тишине', wellRest),
          ('Ходить в парк', wellRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(4)), findsOneWidget);

        // Повтор после восстановления согласует выдачу с прежними условиями.
        app.fault.failure = null;
        await _tap(
          tester,
          find.descendant(
            of: find.byType(IntentionCatalogRefreshStatusView),
            matching: find.widgetWithText(FilledButton, l10n.commonRetry),
          ),
        );
        await _expectResults(tester, page, [
          ('Ходить в парк', wellRest),
          ('Гулять без тегов', well),
          ('Читать в тишине', wellRest),
          ('Ходить в зал', wellRest),
          ('Ходить в парк', wellRest),
        ]);
        expect(find.text(l10n.catalogTotalCount(5)), findsOneWidget);
        expect(find.text(l10n.catalogRefreshUnavailable), findsNothing);
        expect(_conditions(tester, page), ['Самочувствие', deletedSport]);

        // Список прокручен ниже начала до того, как удаление обязательного
        // тега снимет его с экрана.
        tester.view.physicalSize = const Size(1200, 700);
        await tester.pumpAndSettle();
        await tester.drag(_catalogList, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(_catalogListPosition(tester).pixels, greaterThan(0));

        // Удалённый обязательный тег: успешная пустая выдача с количеством
        // ноль и сохранённым условием.
        await app.completeTag(
          tester,
          (coordinator) =>
              coordinator.acceptTagDelete(DeleteTag(_tag(_health))),
        );
        await _until(tester, find.text(l10n.catalogTagConditionsEmpty));
        final deletedConditions = [
          l10n.intentionTagConditionDeleted('Самочувствие'),
          deletedSport,
        ];
        expect(_conditions(tester, page), deletedConditions);
        expect(_results(tester, page), isEmpty);
        expect(
          app.container.read(intentionCatalogViewModelProvider(purpose)).value,
          isA<IntentionCatalogEmpty>()
              .having((state) => state.totalCount, 'количество', 0)
              .having(
                (state) => state.refresh,
                'обновление',
                isA<IntentionCatalogRefreshIdle>(),
              ),
        );

        // Одноимённый новый тег не восстанавливает выдачу.
        await app.completeTag(
          tester,
          (coordinator) => coordinator.acceptTagCreation(
            TagCreationFormKey(),
            CreateTag(TagName.fromInput('Самочувствие')),
          ),
        );
        final recreated = (TagId.decode(
          app.raw.select('SELECT id FROM tags WHERE name = ?', [
                'Самочувствие',
              ]).single['id']
              as String,
        ) as TagIdDecodingSuccess).id;
        await app.completeTag(
          tester,
          (coordinator) => coordinator.acceptTagAssign(
            AssignTag(tagId: recreated, intentionId: _intention(1)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.catalogTagConditionsEmpty), findsOneWidget);
        expect(_results(tester, page), isEmpty);
        expect(_conditions(tester, page), deletedConditions);

        // Явное снятие условия возобновляет выдачу.
        await _removeCondition(tester, _health);
        expect(_conditions(tester, page), [deletedSport]);
        final rest = l10n.intentionSummaryTags('Отдых');
        // Возобновлённая выдача открывается с верхней позиции, а не с
        // сохранённого смещения снятого с экрана списка.
        await _until(tester, _catalogList);
        await tester.pumpAndSettle();
        expect(_catalogListPosition(tester).pixels, 0);
        expect(_results(tester, page).first, ('Ходить в парк', rest));
        tester.view.physicalSize = const Size(1200, 2400);
        await tester.pumpAndSettle();
        await _expectResults(tester, page, [
          ('Ходить в парк', rest),
          ('Гулять без тегов', l10n.intentionSummaryNoTags),
          ('Читать в тишине', rest),
          ('Ходить в зал', rest),
          ('Ходить до магазина', l10n.intentionSummaryNoTags),
          ('Ходить в парк', l10n.intentionSummaryTags('Отдых, Самочувствие')),
        ]);
        expect(find.text(l10n.catalogTotalCount(6)), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _App {
  _App(this.raw, this.container, this.router, this.fault, this.l10n);

  final sqlite.Database raw;
  final ProviderContainer container;
  final AppRouter router;
  final _RefreshFault fault;
  final AppLocalizations l10n;

  static Future<_App> pump(WidgetTester tester, Locale locale) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late sqlite.Database raw;
    final fault = _RefreshFault();
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (database) => raw = database),
        fault,
      ),
      diagnosticsSink: fault,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    _seed(raw);
    await tester.pumpWidget(MainApp(runtime: runtime));
    await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));
    await _until(tester, find.byType(IntentionSummaryView));
    await tester.pumpAndSettle();
    return _App(
      raw,
      ready.container,
      ready.container.read(appRouterProvider),
      fault,
      lookupAppLocalizations(locale),
    );
  }

  /// Проводит команду тега настоящим адаптером через coordinator приложения.
  Future<void> completeTag(
    WidgetTester tester,
    TagCommandStart Function(GraphCommandCoordinator coordinator) accept,
  ) async {
    final start = accept(
      container.read(graphCommandCoordinatorProvider.notifier),
    );
    TagCommandCompletion? completion;
    unawaited(
      (start as TagCommandAccepted).future.then((value) => completion = value),
    );
    await _waitFor(tester, () => completion != null);
    expect(completion!.isFailure, isFalse);
  }

  /// Открывает поиск связанного участника из редактора сохранённой связи.
  Future<void> openParticipantPicker(WidgetTester tester, int relation) async {
    unawaited(
      router.push(
        RelationDetailsRoute(
          relationId: (LongTermRelationId.decode(
            tagFixtureId(relation),
          ) as LongTermRelationIdDecodingSuccess).id,
        ),
      ),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('relation-details-edit-relation')),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('relation-editor-change-related')),
    );
    await _until(tester, find.byType(RelationParticipantPickerPage));
    await tester.pumpAndSettle();
  }
}

/// Управляемый отказ SQLite только для чтения согласования выдачи.
///
/// Диагностика репозитория отмечает границы этого чтения, поэтому команды
/// тегов и обычные порции каталога выполняются без отказа.
final class _RefreshFault extends LocalDatabaseConnectionObserver
    implements DiagnosticsSink {
  Object? failure;
  var failedReads = 0;
  var _reconciling = false;

  @override
  void record(DiagnosticsEvent event) {
    if (event is CatalogReconciliationReadDiagnosticsEvent) {
      _reconciling = event.status is DiagnosticsStarted;
    }
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final failure = this.failure;
    if (failure == null ||
        !_reconciling ||
        statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.any((sql) => sql.contains('json_each('))) {
      return;
    }
    failedReads += 1;
    throw failure;
  }
}

/// Намерения с тегами «Здоровье», «Спорт» и «Отдых», связи первого
/// намерения и его дневной выбор с путём по одной из активных связей.
void _seed(sqlite.Database database) {
  for (final (number, name) in [
    (_health, 'Здоровье'),
    (_sport, 'Спорт'),
    (_rest, 'Отдых'),
  ]) {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(number),
      name,
    ]);
  }
  for (final (number, title, ready, archived, tags) in [
    (1, 'Ходить в парк', 1, 0, [_health, _rest]),
    (2, 'Ходить до магазина', 1, 0, [_health]),
    (3, 'Ходить в зал', 1, 0, [_health, _sport, _rest]),
    (4, 'Читать в тишине', 0, 0, [_health, _rest]),
    (5, 'Ходить в парк', 1, 1, [_health, _rest]),
    (6, 'Гулять без тегов', 0, 0, <int>[]),
    (7, 'Ходить в парк', 0, 0, [_health, _rest]),
  ]) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, ready, archived, number, number],
    );
    for (final tag in tags) {
      database.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(tag), tagFixtureId(number)],
      );
    }
  }
  for (final (number, related, archived) in [
    (_pathRelation, 2, 0),
    (_archivedRelation, 5, 1),
    (_activeRelation, 4, 0),
  ]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(1),
        tagFixtureId(related),
        'need',
        2,
        archived,
      ],
    );
  }
  database.execute(
    'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
    [
      tagFixtureId(_dailyChoice),
      tagFixtureId(1),
      tagFixtureId(2),
      '2026-09-25',
      0,
    ],
  );
  database.execute(
    'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
    [
      tagFixtureId(202),
      tagFixtureId(_dailyChoice),
      tagFixtureId(_pathRelation),
    ],
  );
}

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  ...retainedTagFixtureGraph(raw),
  for (final table in ['tags', 'tag_assignments'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

Object? _connectionChanges(sqlite.Database raw) =>
    raw.select('SELECT total_changes() AS count').single['count'];

final _catalogList = find.byKey(
  const PageStorageKey<String>('intention-catalog-list'),
);

ScrollPosition _catalogListPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _catalogList, matching: find.byType(Scrollable)),
    )
    .position;

/// Видимые результаты поиска страницы в порядке выдачи.
List<_Row> _results(WidgetTester tester, Type page) => [
  for (final view
      in find
          .descendant(
            of: find.byType(page),
            matching: find.byType(IntentionSummaryView),
          )
          .evaluate())
    switch (find
        .descendant(
          of: find.byElementPredicate((element) => element == view),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((element) => (element.widget as Text).data!)
        .toList()) {
      [final title, final tags, ...] => (title, tags),
      final texts => fail('Строка результата без названия и тегов: $texts'),
    },
];

/// Подписи чипов выбранных условий страницы в порядке добавления.
List<String> _conditions(WidgetTester tester, Type page) => [
  for (final label
      in find
          .descendant(
            of: find.byType(page),
            matching: find.byKey(
              const ValueKey('intention-tag-condition-label'),
            ),
          )
          .evaluate())
    (label.widget as Text).data!,
];

Future<void> _expectResults(
  WidgetTester tester,
  Type page,
  List<_Row> expected,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final actual = _results(tester, page);
    if (actual.length == expected.length &&
        [
          for (var index = 0; index < actual.length; index++)
            actual[index] == expected[index],
        ].every((same) => same)) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(_results(tester, page), expected);
}

/// Добавляет условие через экран поиска тега действием «Есть» или «Нет».
Future<void> _addCondition(
  WidgetTester tester,
  int tag, {
  required bool present,
}) async {
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-tag-conditions-add')),
  );
  final requirement = present ? 'mustBePresent' : 'mustBeAbsent';
  await _tap(
    tester,
    find.byKey(
      ValueKey('tag-condition-picker-$requirement-${tagFixtureId(tag)}'),
    ),
  );
  await _waitFor(
    tester,
    () => find.byType(TagConditionPickerPage).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

Future<void> _removeCondition(WidgetTester tester, int tag) async {
  await _tap(
    tester,
    find.byKey(ValueKey('intention-tag-condition-remove-${tagFixtureId(tag)}')),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Закрывает верхнюю страницу системным действием «назад».
Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
