import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlStatement,
        observeConfiguredLocalDatabaseConnection,
        openFileBackedLocalDatabase;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/favorite_storage_fixture.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';

/// «Гулять» — активное готовое избранное на месте 1 с тегом «Работа».
const _walk = 1;

const _homeTag = 301;
const _gardenTag = 302;
const _workTag = 303;

const _tagNames = {_homeTag: 'Дом', _gardenTag: 'Сад', _workTag: 'Работа'};

/// Сырое название черновика: команда создания нормализует его в [_title].
const _rawTitle = '  Рисовать  ';
const _title = 'Рисовать';
const _description = 'Акварелью, по выходным';

/// Тег, который человек создаёт настоящим редактором из общего выбора.
const _sport = 'Спорт';

/// Таблицы, в которые пишет только создание намерения.
const _creationTables = [
  'intentions',
  'intention_titles_fts',
  'tag_assignments',
  'favorite_intentions',
];

const _message = ValueKey('graph-operation-message');
final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _addToDraftAction = find.byKey(
  const ValueKey('tag-catalog-add-to-draft'),
);
final _createTagAction = find.byKey(const ValueKey('tag-catalog-create'));
final _editorName = find.byKey(const ValueKey('tag-editor-name'));
final _editorSubmit = find.byKey(const ValueKey('tag-editor-submit'));

/// Контрольная точка фазы 2: сессия черновика, общий выбор тегов через
/// существующую страницу, настоящий редактор тега, координатор команд и
/// Drift-адаптер на файловом хранилище работают вместе до отправки, при
/// успехе и при отказе.
///
/// Намерение создаёт только отправка сессии: проверка не передаёт
/// координатору заранее подготовленную команду создания. Команды и
/// наблюдения тегов видны через прозрачную обёртку настоящего адаптера,
/// граф — по строкам хранилища, ревизия — по публичному чтению каталога
/// тегов, а результат — по завершениям координатора, праву предъявления
/// сессии и общей поверхности сообщений. Управляемые отказы записи вносит
/// существующий hook соединения локального хранилища.
void main() {
  testWidgets(
    'подготовка всех пяти полей через общий выбор и настоящий редактор тега '
    'не пишет намерение, назначения и избранное, а сброс черновика '
    'сохраняет созданный редактором тег',
    (tester) async {
      final app = await _launch(tester);
      final l10n = app.l10n;
      final graphBefore = _storedGraph(app.raw);
      final events = app.diagnostics.events.length;
      final home = _tagId(_homeTag);

      final session = app.openSession();
      _prepareText(session);
      await _openChooser(tester, app, session);
      await _addToDraft(tester, home);
      expect(session.tagSet.current.tagIds, [home]);

      // Тег из настоящего редактора сохраняется сразу самостоятельной
      // меткой: в черновик он не входит и никому не назначен.
      final sport = await _createTagInEditor(tester, app, _sport);
      final tagRevision = app.completions.last.revision!;
      expect(_storedTagNames(app.raw), ['Дом', 'Сад', 'Работа', _sport]);
      expect(_assignmentsOfTag(app.raw, sport), isEmpty);
      expect(session.tagSet.current.tagIds, [home]);
      expect(
        _rowStatus(sport, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );

      // Явное включение созданного тега меняет только набор черновика.
      await _addToDraft(tester, sport);
      expect(session.tagSet.current.tagIds, [home, sport]);
      expect(_rowStatus(sport, l10n.tagCatalogInDraft), findsOneWidget);
      expect(_assignmentsOfTag(app.raw, sport), isEmpty);
      await _closeChooser(tester);

      // Закрытие выбора сохраняет все пять полей и не завершает сессию.
      final prepared = session.state;
      expect(prepared.draftAvailability, IntentionDraftAvailability.editable);
      expect(prepared.closing, isA<IntentionCreationCloseNotRequested>());
      _expectPreparedDraft(prepared.draft, tagIds: [home, sport]);
      await _waitFor(
        tester,
        () => _isProjected(session, {home: 'Дом', sport: _sport}),
        reason: () => '${session.state.selectedTags}',
      );
      // Проекцию держат собственные наблюдения сессии; выбор их освободил.
      await _settle(tester);
      expect(app.graph.observations(home), 1);
      expect(app.graph.observations(sport), 1);

      // До отправки граф получил только самостоятельный тег: ни намерения,
      // ни назначений, ни избранного, а ревизию продвинуло лишь создание
      // тега.
      _expectSameCreationTables(app.raw, graphBefore);
      expect(
        (await _revision(tester, app)).compareTo(tagRevision),
        GraphRevisionOrder.same,
      );
      expect(app.graph.commands, [isA<CreateTag>()]);
      expect(_commandEvents(app, since: events), [
        _tagEvent(TagCommandDiagnosticsType.create),
      ]);

      // Подтверждённый сброс до отправки закрывает сессию без записи.
      final confirmation = _confirmationOf(session.editor.requestClose());
      expect(
        confirmation.savingOnClose,
        IntentionCreationSavingOnClose.notStarted,
      );
      expect(
        session.editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.closed,
      );
      expect(
        session.tagSet.current.availability,
        IntentionDraftAvailability.closed,
      );
      expect(
        session.tagSet.add(_tag(_gardenTag)),
        IntentionDraftTagAddition.sessionClosed,
      );
      // Завершение сессии освобождает её наблюдения ещё до ухода владельца.
      expect(app.graph.observations(home), 0);
      expect(app.graph.observations(sport), 0);
      session.release();
      await _settle(tester);

      _expectSameCreationTables(app.raw, graphBefore);
      expect(_storedTagNames(app.raw), ['Дом', 'Сад', 'Работа', _sport]);
      expect(
        (await _revision(tester, app)).compareTo(tagRevision),
        GraphRevisionOrder.same,
      );
      expect(app.graph.commands, [isA<CreateTag>()]);
      expect(_creations(app), isEmpty);
      expect(find.byKey(_message), findsNothing);

      // Новое открытие начинается с начального черновика.
      final next = app.openSession();
      expect(next.state.draft.isChanged, isFalse);
      expect(next.tagSet.current.tagIds, isEmpty);
      _expectPrivateDataHidden(app, [
        _title,
        _description,
        ..._tagNames.values,
        _sport,
        home.toCanonicalString(),
        sport.toCanonicalString(),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('отправка черновика, подготовленного через общий выбор, после '
      'переименования выбранного тега даёт один полный результат на одной '
      'ревизии и предъявляется общей поверхностью один раз', (tester) async {
    final app = await _launch(tester);
    final l10n = app.l10n;
    final home = _tagId(_homeTag);
    final marks = storedFavoriteMarks(app.raw);

    final session = app.openSession();
    _prepareText(session);
    await _openChooser(tester, app, session);
    await _addToDraft(tester, home);
    final sport = await _createTagInEditor(tester, app, _sport);
    await _addToDraft(tester, sport);
    await _closeChooser(tester);
    await _waitFor(
      tester,
      () => _isProjected(session, {home: 'Дом', sport: _sport}),
      reason: () => '${session.state.selectedTags}',
    );

    // Подтверждённое переименование меняет только проекцию: идентичность
    // и состав набора сохраняются.
    await _runTagCommand(
      tester,
      app,
      app.coordinator.acceptTagRename(
        RenameTag(tagId: home, name: TagName.fromInput('Быт')),
      ),
      l10n.graphOperationMessage(
        l10n.graphOperationUpdate,
        l10n.graphOperationTag,
        l10n.tagRenamed,
      ),
    );
    await _waitFor(
      tester,
      () => _isProjected(session, {home: 'Быт', sport: _sport}),
      reason: () => '${session.state.selectedTags}',
    );
    _expectPreparedDraft(session.state.draft, tagIds: [home, sport]);
    final graphBefore = _storedGraph(app.raw);
    final events = app.diagnostics.events.length;
    expect(app.graph.commands, [isA<CreateTag>(), isA<RenameTag>()]);

    // Отправка фиксирует весь черновик: правки, запоздалое добавление из
    // выбора и повторная отправка до результата отвергаются.
    session.editor.submit();
    expect(
      session.state.draftAvailability,
      IntentionDraftAvailability.submitting,
    );
    session.editor
      ..changeTitle('Другое')
      ..changeDescription('')
      ..removeTag(home)
      ..unmarkFavorite()
      ..disableReadiness()
      ..submit();
    expect(
      session.tagSet.add(_tag(_gardenTag)),
      IntentionDraftTagAddition.submitting,
    );
    _expectPreparedDraft(session.state.draft, tagIds: [home, sport]);

    final completion = await _creation(tester, app);
    final created = switch (completion.result) {
      ResultSuccess(value: IntentionSaved(:final intention)) => intention.id,
      final result => fail('Создание не подтверждено: $result'),
    };

    // До хранилища дошла одна команда со всеми пятью полями черновика.
    expect(app.graph.commands, hasLength(3));
    _expectDraftCommand(app.graph.commands.last, tagIds: {home, sport});

    // Один окончательный пакет: снимок и оба назначения на одной ревизии,
    // которую подтверждает и свежее чтение графа.
    final revision = completion.revision!;
    expect(completion.confirmedChange!.changes, [
      isA<IntentionCatalogCreated>(),
      isA<TagAssignmentChangedChange>(),
      isA<TagAssignmentChangedChange>(),
    ]);
    expect(
      completion.confirmedChange!.changes.map((change) => change.revision),
      everyElement(same(revision)),
    );
    expect(
      (await _revision(tester, app)).compareTo(revision),
      GraphRevisionOrder.same,
    );

    // Хранилище содержит всё начальное состояние, а избранное встало в
    // конец единого порядка.
    _expectCreatedIntention(app.raw, created, tagIds: [home, sport]);
    expect(storedFavoriteMarks(app.raw), [
      ...marks,
      (created.toCanonicalString(), 2),
    ]);
    expect(
      _storedGraph(app.raw)['intentions'],
      hasLength(graphBefore['intentions']!.length + 1),
    );
    expect(await _assignedNames(tester, app, created), ['Быт', _sport]);

    // Успех завершает именно эту сессию и освобождает её наблюдения.
    final finished = session.state;
    expect(finished.draftAvailability, IntentionDraftAvailability.closed);
    expect(finished.event, isA<IntentionEditorCreated>());
    expect(
      session.tagSet.current.availability,
      IntentionDraftAvailability.closed,
    );
    await _settle(tester);
    expect(app.graph.observations(home), 0);
    expect(app.graph.observations(sport), 0);

    // Успех предъявляет общая поверхность ровно один раз.
    await _acceptMessage(
      tester,
      l10n.graphOperationMessage(
        l10n.graphOperationCreate,
        _title,
        l10n.editorCreated,
      ),
    );
    await _settle(tester);
    expect(find.byKey(_message), findsNothing);
    expect(_creations(app), [same(completion)]);

    // Создание — одна команда с одним исходом: самостоятельные отметка,
    // готовность и назначения не выполнялись.
    expect(_commandEvents(app, since: events), [
      _createEvent(
        IntentionCreationCommandDiagnosticsStage.resultRead,
        isA<DiagnosticsSucceeded>(),
      ),
    ]);
    _expectPrivateDataHidden(app, [
      _title,
      _description,
      ..._tagNames.values,
      'Быт',
      _sport,
      home.toCanonicalString(),
      sport.toCanonicalString(),
      created.toCanonicalString(),
    ]);
    expect(tester.takeException(), isNull);
  });

  for (final deletion in _SelectedTagDeletion.values) {
    testWidgets(
      '${deletion.description} отклоняет весь подготовленный набор, сохраняет '
      'черновик и прежний граф без продвижения ревизии, а новая проверка '
      'возможна только после явного снятия отсутствующего тега',
      (tester) async {
        final app = await _launch(tester);
        final l10n = app.l10n;
        final home = _tagId(_homeTag);
        final garden = _tagId(_gardenTag);
        final marks = storedFavoriteMarks(app.raw);

        final session = app.openSession();
        _prepareText(session);
        await _openChooser(tester, app, session);
        await _addToDraft(tester, home);
        await _addToDraft(tester, garden);
        await _closeChooser(tester);
        await _waitFor(
          tester,
          () => _isProjected(session, {home: 'Дом', garden: 'Сад'}),
          reason: () => '${session.state.selectedTags}',
        );

        // Выбранный тег удаляют самостоятельной командой; одноимённая замена
        // получает новый идентификатор.
        await _runTagCommand(
          tester,
          app,
          app.coordinator.acceptTagDelete(DeleteTag(home)),
          l10n.graphOperationMessage(
            l10n.graphOperationDelete,
            l10n.graphOperationTag,
            l10n.tagDeleted,
          ),
        );
        TagId? replacement;
        if (deletion == _SelectedTagDeletion.withSameNameReplacement) {
          final created = await _runTagCommand(
            tester,
            app,
            app.coordinator.acceptTagCreation(
              TagCreationFormKey(),
              CreateTag(TagName.fromInput('Дом')),
            ),
            l10n.graphOperationMessage(
              l10n.graphOperationCreate,
              l10n.graphOperationTag,
              l10n.tagCreated,
            ),
          );
          replacement = switch (created.result) {
            GraphResultSuccess(value: TagCreated(:final tag)) => tag.id,
            final result => fail('Замена не создана: $result'),
          };
          expect(replacement, isNot(home));
        }

        // Проекция показывает удалённый тег недоступным с последним
        // названием, но не снимает его из набора.
        await _waitFor(
          tester,
          () =>
              session.state.selectedTags[home]?.status
                  is IntentionDraftTagMissing,
          reason: () => '${session.state.selectedTags}',
        );
        expect(session.state.selectedTags[home]!.name.value, 'Дом');
        _expectPreparedDraft(session.state.draft, tagIds: [home, garden]);
        final graphBefore = _storedGraph(app.raw);
        final revisionBefore = await _revision(tester, app);
        final events = app.diagnostics.events.length;

        // Отправка проверяет набор в транзакции и отклоняет его целиком.
        session.editor.submit();
        final rejected = await _creation(tester, app);
        expect(
          rejected.result,
          isA<ResultFailure<IntentionCommandSuccess>>().having(
            (result) => result.failure,
            'отказ',
            isA<IntentionCreationTagsMissingFailure>().having(
              (failure) => failure.missingTagIds,
              'отсутствующие теги',
              {home},
            ),
          ),
        );
        expect(rejected.confirmedChange, isNull);
        _expectDraftCommand(app.graph.commands.last, tagIds: {home, garden});
        await _settle(tester);
        expect(_storedGraph(app.raw), graphBefore);
        expect(
          (await _revision(tester, app)).compareTo(revisionBefore),
          GraphRevisionOrder.same,
        );
        expect(_commandEvents(app, since: events), [
          _createEvent(
            IntentionCreationCommandDiagnosticsStage.validation,
            _failedWith(DiagnosticsFailureCode.validation),
          ),
        ]);

        // Сессия сохраняет весь черновик и право предъявить отказ, поэтому
        // общая поверхность его не показывает.
        final failed = session.state;
        _expectPreparedDraft(failed.draft, tagIds: [home, garden]);
        expect(failed.draftAvailability, IntentionDraftAvailability.editable);
        expect(failed.missingTagIds, {home});
        expect(failed.canSubmit, isFalse);
        expect(failed.failurePresentation?.completion, same(rejected));
        expect(find.byKey(_message), findsNothing);

        if (replacement != null) {
          // Одноимённая замена — другой тег: его явное добавление не снимает
          // отказ и не подменяет отсутствующий выбор.
          await _openChooser(tester, app, session);
          expect(_row(home), findsNothing);
          expect(
            _rowStatus(replacement, l10n.tagCatalogAvailableForDraft),
            findsOneWidget,
          );
          await _addToDraft(tester, replacement);
          await _closeChooser(tester);
          final replaced = session.state;
          expect(replaced.draft.tagIds, [home, garden, replacement]);
          expect(replaced.missingTagIds, {home});
          expect(replaced.canSubmit, isFalse);
          expect(replaced.failurePresentation?.completion, same(rejected));
        }

        // Явное снятие отсутствующего тега разрешает новую проверку, но сама
        // сессия её не запускает.
        final kept = [garden, ?replacement];
        session.editor.removeTag(home);
        final corrected = session.state;
        expect(corrected.canSubmit, isTrue);
        expect(corrected.missingTagIds, isEmpty);
        _expectPreparedDraft(corrected.draft, tagIds: kept);
        await _settle(tester);
        expect(app.graph.observations(home), 0);
        expect(_creations(app), [same(rejected)]);

        session.editor.submit();
        final accepted = await _creation(tester, app, count: 2);
        final created = switch (accepted.result) {
          ResultSuccess(value: IntentionSaved(:final intention)) =>
            intention.id,
          final result => fail('Создание не подтверждено: $result'),
        };
        _expectDraftCommand(app.graph.commands.last, tagIds: kept.toSet());
        _expectCreatedIntention(app.raw, created, tagIds: kept);
        expect(storedFavoriteMarks(app.raw), [
          ...marks,
          (created.toCanonicalString(), 2),
        ]);
        await _acceptMessage(
          tester,
          l10n.graphOperationMessage(
            l10n.graphOperationCreate,
            _title,
            l10n.editorCreated,
          ),
        );
        await _settle(tester);
        expect(find.byKey(_message), findsNothing);
        expect(_creations(app), hasLength(2));
        _expectPrivateDataHidden(app, [
          _title,
          _description,
          ..._tagNames.values,
          home.toCanonicalString(),
          garden.toCanonicalString(),
          ?replacement?.toCanonicalString(),
          created.toCanonicalString(),
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'отказ записи после всего начального состояния сохраняет черновик, '
    'прежний граф и ревизию, а созданный редактором тег переживает отказ; '
    'явный повтор с новым токеном даёт полный результат',
    (tester) async {
      final app = await _launch(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);
      final marks = storedFavoriteMarks(app.raw);

      final session = app.openSession();
      _prepareText(session);
      await _openChooser(tester, app, session);
      await _addToDraft(tester, home);
      final sport = await _createTagInEditor(tester, app, _sport);
      await _addToDraft(tester, sport);
      await _closeChooser(tester);
      await _waitFor(
        tester,
        () => _isProjected(session, {home: 'Дом', sport: _sport}),
        reason: () => '${session.state.selectedTags}',
      );
      final graphBefore = _storedGraph(app.raw);
      final revisionBefore = await _revision(tester, app);
      final events = app.diagnostics.events.length;

      // Хранилище отказывает внутри транзакции, когда в ней уже записаны
      // намерение, оба назначения и место избранного.
      app.faults.failAfterFavoritePlaceInsert();
      session.editor.submit();
      final failed = await _creation(tester, app);
      expect(
        failed.result,
        isA<ResultFailure<IntentionCommandSuccess>>().having(
          (result) => result.failure,
          'отказ',
          isA<IntentionUnavailableFailure>(),
        ),
      );
      expect(failed.confirmedChange, isNull);
      final fault = app.faults.faultPoint;
      expect(fault, isNotNull, reason: 'Отказ хранилища не сработал');
      expect(fault!.inTransaction, isTrue);
      expect(fault.inserts, [
        'intentions',
        'tag_assignments',
        'tag_assignments',
        'favorite_intentions',
      ]);

      // Ни части записи и ни новой ревизии; самостоятельный тег остаётся.
      await _settle(tester);
      expect(_storedGraph(app.raw), graphBefore);
      expect(_storedTagNames(app.raw), ['Дом', 'Сад', 'Работа', _sport]);
      expect(
        (await _revision(tester, app)).compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      expect(_commandEvents(app, since: events), [
        _createEvent(
          IntentionCreationCommandDiagnosticsStage.write,
          _failedWith(DiagnosticsFailureCode.unavailable),
        ),
      ]);

      // Черновик сохранён целиком, отказ принадлежит сессии и предлагает
      // только явный повтор.
      final kept = session.state;
      _expectPreparedDraft(kept.draft, tagIds: [home, sport]);
      expect(kept.draftAvailability, IntentionDraftAvailability.editable);
      expect(kept.canRetry, isTrue);
      expect(kept.canSubmit, isTrue);
      expect(kept.failurePresentation?.completion, same(failed));
      expect(find.byKey(_message), findsNothing);
      expect(_creations(app), [same(failed)]);

      session.editor.submit();
      final retried = await _creation(tester, app, count: 2);
      expect(retried.token, isNot(same(failed.token)));
      final created = switch (retried.result) {
        ResultSuccess(value: IntentionSaved(:final intention)) => intention.id,
        final result => fail('Повтор не подтверждён: $result'),
      };
      final creationCommands = app.graph.commands.whereType<CreateIntention>();
      expect(creationCommands, hasLength(2));
      for (final command in creationCommands) {
        _expectDraftCommand(command, tagIds: {home, sport});
      }
      _expectCreatedIntention(app.raw, created, tagIds: [home, sport]);
      expect(storedFavoriteMarks(app.raw), [
        ...marks,
        (created.toCanonicalString(), 2),
      ]);
      expect(
        (await _revision(tester, app)).compareTo(retried.revision!),
        GraphRevisionOrder.same,
      );
      await _acceptMessage(
        tester,
        l10n.graphOperationMessage(
          l10n.graphOperationCreate,
          _title,
          l10n.editorCreated,
        ),
      );
      await _settle(tester);
      expect(find.byKey(_message), findsNothing);
      expect(_creations(app), hasLength(2));
      _expectPrivateDataHidden(app, [
        _title,
        _description,
        ..._tagNames.values,
        _sport,
        home.toCanonicalString(),
        sport.toCanonicalString(),
        created.toCanonicalString(),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final outcome in _LateOutcome.values) {
    testWidgets('задержанная отправка сессии, закрытой подтверждённым сбросом, '
        'завершается один раз — ${outcome.description} — и предъявляется общей '
        'поверхностью, а новое открытие с собственным выбором остаётся '
        'независимым', (tester) async {
      final app = await _launch(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);
      final garden = _tagId(_gardenTag);
      final work = _tagId(_workTag);
      final marks = storedFavoriteMarks(app.raw);

      final first = app.openSession();
      _prepareText(first);
      await _openChooser(tester, app, first);
      await _addToDraft(tester, home);
      await _closeChooser(tester);
      await _waitFor(
        tester,
        () => _isProjected(first, {home: 'Дом'}),
        reason: () => '${first.state.selectedTags}',
      );
      final graphBefore = _storedGraph(app.raw);
      final revisionBefore = await _revision(tester, app);
      final events = app.diagnostics.events.length;

      // Координатор принял отправку, а хранилище её ещё не выполнило.
      app.graph.holdNextCreation();
      first.editor.submit();
      await _waitFor(tester, () => app.graph.isHoldingCreation);
      expect(
        first.state.draftAvailability,
        IntentionDraftAvailability.submitting,
      );

      // Сессия закрывается подтверждённым сбросом, сохранение продолжается,
      // а владелец освобождает сессию вместе с её наблюдениями.
      final confirmation = _confirmationOf(first.editor.requestClose());
      expect(
        confirmation.savingOnClose,
        IntentionCreationSavingOnClose.continues,
      );
      expect(
        first.editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.closed,
      );
      expect(
        first.tagSet.current.availability,
        IntentionDraftAvailability.closed,
      );
      expect(app.graph.observations(home), 0);
      first.release();
      await _settle(tester);
      expect(app.graph.isHoldingCreation, isTrue);
      expect(_creations(app), isEmpty);

      // Новое открытие начинается с начального черновика и собственного
      // открытия выбора.
      final second = app.openSession();
      expect(second.state.draft.isChanged, isFalse);
      expect(second.tagSet.current.tagIds, isEmpty);
      second.editor.changeTitle('Позвонить маме');
      await _openChooser(tester, app, second);
      expect(_searchText(tester), isEmpty);
      expect(
        _rowStatus(home, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      await _addToDraft(tester, garden);
      await tester.enterText(_search, 'раб');
      await tester.pump();
      await _tap(tester, _row(work));
      await _waitFor(tester, () => _isCandidate(tester, work));
      await _waitFor(
        tester,
        () => _isProjected(second, {garden: 'Сад'}),
        reason: () => '${second.state.selectedTags}',
      );
      await _settle(tester);
      final published = <IntentionDraftTagSetSnapshot>[];
      final changes = second.tagSet.changes.listen(published.add);
      addTearDown(changes.cancel);
      final before = second.state;

      if (outcome == _LateOutcome.storageFailure) {
        app.faults.failAfterFavoritePlaceInsert();
      }
      app.graph.releaseCreation();
      final completion = await _creation(tester, app);

      // Закрытая сессия передала результат общей поверхности: он
      // предъявляется ровно один раз поверх нового открытия выбора.
      await _acceptMessage(tester, switch (outcome) {
        _LateOutcome.success => l10n.graphOperationMessage(
          l10n.graphOperationCreate,
          _title,
          l10n.editorCreated,
        ),
        _LateOutcome.storageFailure => l10n.graphOperationMessage(
          l10n.graphOperationCreate,
          l10n.graphOperationNewIntention,
          l10n.editorCreateUnavailable,
        ),
      });
      await _settle(tester);
      expect(find.byKey(_message), findsNothing);
      expect(_creations(app), [same(completion)]);
      final creationCommands = app.graph.commands.whereType<CreateIntention>();
      expect(creationCommands, hasLength(1));
      _expectDraftCommand(creationCommands.single, tagIds: {home});

      switch (outcome) {
        case _LateOutcome.success:
          final created = switch (completion.result) {
            ResultSuccess(value: IntentionSaved(:final intention)) =>
              intention.id,
            final result => fail('Создание не подтверждено: $result'),
          };
          _expectCreatedIntention(app.raw, created, tagIds: [home]);
          expect(storedFavoriteMarks(app.raw), [
            ...marks,
            (created.toCanonicalString(), 2),
          ]);
          expect(
            (await _revision(tester, app)).compareTo(completion.revision!),
            GraphRevisionOrder.same,
          );
          expect(_commandEvents(app, since: events), [
            _createEvent(
              IntentionCreationCommandDiagnosticsStage.resultRead,
              isA<DiagnosticsSucceeded>(),
            ),
          ]);
          _expectPrivateDataHidden(app, [created.toCanonicalString()]);
        case _LateOutcome.storageFailure:
          expect(
            completion.result,
            isA<ResultFailure<IntentionCommandSuccess>>().having(
              (result) => result.failure,
              'отказ',
              isA<IntentionUnavailableFailure>(),
            ),
          );
          expect(app.faults.faultPoint?.inTransaction, isTrue);
          expect(_storedGraph(app.raw), graphBefore);
          expect(
            (await _revision(tester, app)).compareTo(revisionBefore),
            GraphRevisionOrder.same,
          );
          expect(_commandEvents(app, since: events), [
            _createEvent(
              IntentionCreationCommandDiagnosticsStage.write,
              _failedWith(DiagnosticsFailureCode.unavailable),
            ),
          ]);
      }

      // Новое открытие сессии и его выбор результат не изменил.
      expect(second.state, same(before));
      expect(published, isEmpty);
      expect(second.tagSet.current.tagIds, [garden]);
      expect(
        second.tagSet.current.availability,
        IntentionDraftAvailability.editable,
      );
      expect(app.router.current.name, TagCatalogRoute.name);
      expect(_searchText(tester), 'раб');
      expect(_isCandidate(tester, work), isTrue);
      expect(
        _rowStatus(work, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      _expectPrivateDataHidden(app, [
        _title,
        _description,
        'Позвонить маме',
        ..._tagNames.values,
        home.toCanonicalString(),
        garden.toCanonicalString(),
        work.toCanonicalString(),
      ]);
      expect(tester.takeException(), isNull);
    });
  }
}

/// Окончательный исход задержанной отправки сессии, закрытой до него.
enum _LateOutcome {
  success('успех'),
  storageFailure('отказ записи');

  const _LateOutcome(this.description);

  final String description;
}

/// Удаление тега, выбранного в черновике, до отправки.
enum _SelectedTagDeletion {
  alone('удаление выбранного тега'),
  withSameNameReplacement('удаление выбранного тега с одноимённой заменой');

  const _SelectedTagDeletion(this.description);

  final String description;
}

TagId _tagId(int number) => _decodeTagId(tagFixtureId(number));

TagId _decodeTagId(String value) =>
    (TagId.decode(value) as TagIdDecodingSuccess).id;

Tag _tag(int number) =>
    Tag(id: _tagId(number), name: TagName.fromInput(_tagNames[number]!));

/// Одно активное готовое избранное намерение с тегом «Работа» и три тега.
void _seedGraph(sqlite.Database database) {
  database.execute(
    'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 1, 0, 1, 1)',
    [tagFixtureId(_walk), 'Гулять'],
  );
  for (final MapEntry(key: number, value: name) in _tagNames.entries) {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(number),
      name,
    ]);
  }
  database.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(_workTag), tagFixtureId(_walk)],
  );
  storeFavoriteMark(database, intentionId: tagFixtureId(_walk), position: 1);
}

/// Готовит все поля черновика, кроме набора тегов: сырые название и
/// описание, избранное и явно подтверждённую готовность к действию.
void _prepareText(_Session session) => session.editor
  ..changeTitle(_rawTitle)
  ..changeDescription(_description)
  ..markFavorite()
  ..confirmReadiness();

void _expectPreparedDraft(
  IntentionCreationDraft draft, {
  required List<TagId> tagIds,
}) {
  expect(draft.title, _rawTitle);
  expect(draft.description, _description);
  expect(draft.readiness, IntentionReadiness.ready);
  expect(draft.favoriteMark, FavoriteMark.favorite);
  expect(draft.tagIds, tagIds);
}

/// Команда [command] — единственная отправка черновика, подготовленного
/// [_prepareText] и набором [tagIds], без нормализации текста.
void _expectDraftCommand(Object command, {required Set<TagId> tagIds}) {
  expect(
    command,
    isA<CreateIntention>()
        .having((command) => command.title, 'название', _rawTitle)
        .having((command) => command.description, 'описание', _description)
        .having(
          (command) => command.readiness,
          'готовность',
          IntentionReadiness.ready,
        )
        .having(
          (command) => command.favoriteMark,
          'избранное',
          FavoriteMark.favorite,
        )
        .having((command) => command.tagIds, 'теги', tagIds),
  );
}

/// Хранилище содержит намерение [id] со всем начальным состоянием
/// черновика из [_prepareText] и назначениями ровно тегов [tagIds].
void _expectCreatedIntention(
  sqlite.Database raw,
  IntentionId id, {
  required List<TagId> tagIds,
}) {
  final row = raw.select(
    'SELECT title, description, is_action_ready, is_archived, created_at, '
    'updated_at FROM intentions WHERE id = ?',
    [id.toCanonicalString()],
  ).single;
  expect(row['title'], _title);
  expect(row['description'], _description);
  expect(row['is_action_ready'], 1);
  expect(row['is_archived'], 0);
  expect(row['created_at'], row['updated_at']);
  expect([
    for (final assignment in raw.select(
      'SELECT tag_id FROM tag_assignments WHERE intention_id = ?',
      [id.toCanonicalString()],
    ))
      assignment['tag_id'],
  ], unorderedEquals([for (final tag in tagIds) tag.toCanonicalString()]));
}

/// Актуальные названия тегов намерения [id] по публичному чтению
/// назначений.
Future<List<String>> _assignedNames(
  WidgetTester tester,
  _App app,
  IntentionId id,
) async {
  final repository = app.container.read(personalGraphRepositoryProvider);
  final result = await tester.runAsync(() => repository.getTagAssignments(id));
  return switch (result) {
    GraphResultSuccess(:final value) => [
      for (final tag in value.items) tag.name.value,
    ],
    final result => fail('Чтение назначений не удалось: $result'),
  };
}

/// Проекция выбранных тегов сессии подтверждена наблюдением с названиями
/// [names].
bool _isProjected(_Session session, Map<TagId, String> names) {
  final selected = session.state.selectedTags;
  return selected.length == names.length &&
      names.entries.every(
        (expected) => switch (selected[expected.key]) {
          IntentionDraftTag(
            :final name,
            status: IntentionDraftTagAvailable(),
          ) =>
            name.value == expected.value,
          _ => false,
        },
      );
}

IntentionCreationCloseConfirmation _confirmationOf(
  IntentionCreationCloseDecision decision,
) => switch (decision) {
  IntentionCreationCloseNeedsConfirmation(:final confirmation) => confirmation,
  IntentionCreationClosedImmediately() ||
  IntentionCreationCloseAwaitingConfirmation() ||
  IntentionCreationCloseSessionEnded() => throw TestFailure(
    'Ожидалось подтверждение закрытия, получено $decision.',
  ),
};

/// Запущенное приложение на файловом хранилище с наблюдаемым адаптером.
final class _App {
  _App({
    required this.raw,
    required this.container,
    required this.graph,
    required this.faults,
    required this.diagnostics,
    required this.l10n,
    required this.completions,
  });

  final sqlite.Database raw;
  final ProviderContainer container;
  final _ObservedGraph graph;
  final _StorageFaults faults;
  final _RecordedDiagnostics diagnostics;
  final AppLocalizations l10n;

  /// Все завершения координатора в порядке публикации.
  final List<GraphCommandCompletion> completions;

  AppRouter get router => container.read(appRouterProvider);

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  _Session openSession() => _Session(container);
}

/// Сессия черновика, которую удерживает её владелец — будущая панель
/// создания под страницами выбора и редактора тега.
final class _Session {
  _Session(this._container)
    : provider = intentionEditorViewModelProvider(IntentionCreationFormKey()) {
    _owner = _container.listen(provider, (_, _) {});
    editor = _container.read(provider.notifier);
    tagSet = editor.draftTagSet;
  }

  final ProviderContainer _container;
  final IntentionEditorViewModelProvider provider;
  late final ProviderSubscription<IntentionEditorState> _owner;

  /// Остаётся доступным после ухода владельца, чтобы проверять запоздалые
  /// callbacks освобождённой сессии.
  late final IntentionEditorViewModel editor;
  late final IntentionDraftTagSet tagSet;

  /// Читается только пока владелец удерживает сессию: чтение после
  /// [release] построило бы новую.
  IntentionEditorState get state => _container.read(provider);

  /// Владелец уходит, и сессия освобождается.
  void release() => _owner.close();
}

/// Запускает приложение на новом файловом хранилище с исходным графом и
/// открывает граф намерений, над которым будут открываться выбор и редактор.
Future<_App> _launch(WidgetTester tester) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [const Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  addTearDown(harness.dispose);

  late sqlite.Database raw;
  late _ObservedGraph graph;
  final faults = _StorageFaults();
  final diagnostics = _RecordedDiagnostics();
  final runtime = AppRuntime(
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(
        harness.databaseFile,
        setup: (database) => raw = database,
      ),
      faults,
    ),
    diagnosticsSink: diagnostics,
    repositoryFactory: (database) => graph = _ObservedGraph(
      DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.now().toUtc(),
        diagnostics,
        relationIdGenerator: UuidV7LongTermRelationIdGenerator(),
      ),
    ),
  );
  addTearDown(() async {
    // Сценарий, прерванный во время задержанного создания, не должен
    // оставить остановку ждать принятую команду: освобождённое создание
    // успевает завершиться до неё.
    if (graph.releaseCreation()) await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  faults.connection = raw;
  _seedGraph(raw);

  final completions = <GraphCommandCompletion>[];
  final subscription = ready.container
      .read(graphCommandCoordinatorProvider.notifier)
      .completions
      .listen(completions.add);
  addTearDown(subscription.cancel);

  final l10n = lookupAppLocalizations(const Locale('ru'));
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(tester, () => find.text(l10n.homeLoading).evaluate().isEmpty);
  await openIntentionGraph(tester, waitFor: _until);
  await tester.pumpAndSettle();
  return _App(
    raw: raw,
    container: ready.container,
    graph: graph,
    faults: faults,
    diagnostics: diagnostics,
    l10n: l10n,
    completions: completions,
  );
}

/// Завершения создания намерения в порядке публикации.
List<IntentionCommandCompletion> _creations(_App app) =>
    app.completions.whereType<IntentionCommandCompletion>().toList();

/// Дожидается [count]-го завершения создания намерения и возвращает его.
Future<IntentionCommandCompletion> _creation(
  WidgetTester tester,
  _App app, {
  int count = 1,
}) async {
  await _waitFor(
    tester,
    () => _creations(app).length >= count,
    reason: () => 'Создание не завершилось: ${_creations(app)}',
  );
  expect(_creations(app), hasLength(count));
  return _creations(app).last;
}

/// Открывает общий выбор тегов существующим маршрутом в контексте черновика
/// сессии [session].
Future<void> _openChooser(
  WidgetTester tester,
  _App app,
  _Session session,
) async {
  unawaited(
    app.router.push<void>(
      TagCatalogRoute(selectionContext: TagDraftContext(session.tagSet)),
    ),
  );
  await _until(tester, _row(_tagId(_gardenTag)));
  await tester.pumpAndSettle();
}

Future<void> _closeChooser(WidgetTester tester) async {
  await _tap(tester, find.byType(BackButton));
  await _waitFor(tester, () => find.byType(TagCatalogPage).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

/// Выбирает строку тега [id] кандидатом и явно добавляет его в черновик,
/// дождавшись подтверждения кандидата.
Future<void> _addToDraft(WidgetTester tester, TagId id) async {
  await _tap(tester, _row(id));
  await _waitFor(
    tester,
    () => tester.widget<FilledButton>(_addToDraftAction).onPressed != null,
    reason: () => 'Добавление «$id» не стало доступным',
  );
  await _tap(tester, _addToDraftAction);
  await tester.pumpAndSettle();
}

/// Сохраняет новый тег [name] настоящим редактором, открытым «+» общего
/// выбора, и принимает сообщение общей поверхности о его создании.
Future<TagId> _createTagInEditor(
  WidgetTester tester,
  _App app,
  String name,
) async {
  await _tap(tester, _createTagAction);
  await _until(tester, _editorName);
  await tester.enterText(_editorName, name);
  await _tap(tester, _editorSubmit);
  await _waitFor(tester, () => _editorName.evaluate().isEmpty);
  await _acceptMessage(
    tester,
    app.l10n.graphOperationMessage(
      app.l10n.graphOperationCreate,
      app.l10n.graphOperationTag,
      app.l10n.tagCreated,
    ),
  );
  final created = app.raw.select('SELECT id FROM tags WHERE name = ?', [name]);
  return _decodeTagId(created.single['id'] as String);
}

/// Выполняет самостоятельную команду тега, принятую координатором как
/// [start], и принимает её сообщение [message] общей поверхности.
Future<TagCommandCompletion> _runTagCommand(
  WidgetTester tester,
  _App app,
  TagCommandStart start,
  String message,
) async {
  final accepted = start as TagCommandAccepted;
  TagCommandCompletion? completion;
  unawaited(accepted.future.then((value) => completion = value));
  await _waitFor(tester, () => completion != null);
  expect(
    completion!.result,
    isA<GraphResultSuccess<TagCommandSuccess, TagCommandFailure>>(),
  );
  await _acceptMessage(tester, message);
  return completion!;
}

Finder _row(TagId id) =>
    find.byKey(ValueKey('tag-catalog-row-${id.toCanonicalString()}'));

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(_search).controller!.text;

bool _isCandidate(WidgetTester tester, TagId id) =>
    tester.widget<Semantics>(_row(id)).properties.selected ?? false;

Finder _rowStatus(TagId id, String status) =>
    find.descendant(of: _row(id), matching: find.text(status));

/// Строки таблиц графа, включая поисковую проекцию названий.
Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  for (final table in ['tags', ..._creationTables])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

/// Таблицы, в которые пишет только создание намерения, совпадают с [before].
void _expectSameCreationTables(
  sqlite.Database raw,
  Map<String, List<List<Object?>>> before,
) {
  final stored = _storedGraph(raw);
  for (final table in _creationTables) {
    expect(stored[table], before[table], reason: table);
  }
}

List<String> _storedTagNames(sqlite.Database raw) => [
  for (final row in raw.select(
    'SELECT name FROM tags ORDER BY creation_sequence',
  ))
    row['name'] as String,
];

List<String> _assignmentsOfTag(sqlite.Database raw, TagId id) => [
  for (final row in raw.select(
    'SELECT intention_id FROM tag_assignments WHERE tag_id = ?',
    [id.toCanonicalString()],
  ))
    row['intention_id'] as String,
];

/// Ревизия графа по свежему публичному чтению каталога тегов.
Future<GraphRevision> _revision(WidgetTester tester, _App app) async {
  final repository = app.container.read(personalGraphRepositoryProvider);
  final result = await tester.runAsync(
    () => repository.getTagCatalog(const TagCatalogBrowseMode()),
  );
  return switch (result) {
    GraphResultSuccess(:final value) => value.revision,
    final result => fail('Чтение каталога тегов не удалось: $result'),
  };
}

/// Исходы самостоятельных команд намерений, тегов и порядка избранного
/// после первых [since] событий; начала команд не учитываются.
List<DiagnosticsEvent> _commandEvents(_App app, {required int since}) => [
  for (final event in app.diagnostics.events.skip(since))
    if ((event is IntentionCommandDiagnosticsEvent ||
            event is TagCommandDiagnosticsEvent ||
            event is FavoriteOrderCommandDiagnosticsEvent) &&
        event.status is! DiagnosticsStarted)
      event,
];

Matcher _tagEvent(TagCommandDiagnosticsType type) =>
    isA<TagCommandDiagnosticsEvent>()
        .having((event) => event.commandType, 'команда', type)
        .having((event) => event.status, 'исход', isA<DiagnosticsSucceeded>());

Matcher _createEvent(
  IntentionCreationCommandDiagnosticsStage stage,
  Matcher status,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having(
      (event) => event.commandType,
      'команда',
      IntentionCommandDiagnosticsType.create,
    )
    .having((event) => event.stage, 'этап', stage)
    .having((event) => event.status, 'исход', status);

Matcher _failedWith(DiagnosticsFailureCode code) =>
    isA<DiagnosticsFailed>().having((status) => status.code, 'категория', code);

/// Ни событие, ни его запись приложением не содержат значений [values].
void _expectPrivateDataHidden(_App app, Iterable<String> values) {
  expect(app.diagnostics.lines, isNotEmpty);
  final recorded = [
    ...app.diagnostics.events.map((event) => event.toString()),
    ...app.diagnostics.lines,
  ].join('\n');
  for (final value in values) {
    expect(recorded, isNot(contains(value)), reason: value);
  }
}

/// Дожидается ровно одного сообщения [text] общей поверхности и закрывает
/// его; предъявленный результат не показывается повторно.
Future<void> _acceptMessage(WidgetTester tester, String text) async {
  await _until(tester, find.byKey(_message));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.text(text), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsNothing);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Даёт хранилищу и кадрам время: запущенное чтение успело бы завершиться.
Future<void> _settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Продвигает кадры и реальное время хранилища, пока не выполнится [done].
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  String Function()? reason,
}) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: reason?.call());
}

/// Приёмник диагностики: хранит события и их запись приложением.
final class _RecordedDiagnostics implements DiagnosticsSink {
  final events = <DiagnosticsEvent>[];

  /// События в том виде, в каком их выпускает приложение.
  final lines = <String>[];

  @override
  void record(DiagnosticsEvent event) {
    events.add(event);
    DeveloperDiagnosticsSink(lines.add).record(event);
  }
}

/// По требованию прерывает ближайшую вставку места избранного сразу после её
/// выполнения устранимой недоступностью хранилища и фиксирует, что к этому
/// моменту вставлено на соединении приложения.
final class _StorageFaults extends LocalDatabaseConnectionObserver {
  static final _insertedTable = RegExp(
    r'^\s*INSERT(?:\s+OR\s+\w+)?\s+INTO\s+"?(\w+)"?',
    caseSensitive: false,
  );

  /// Соединение запущенного приложения: на нём видно, открыта ли
  /// транзакция.
  late sqlite.Database connection;

  /// Таблицы вставок после взвода отказа; `null`, пока отказ не взведён.
  List<String>? _inserts;

  /// Состояние в момент отказа; `null`, пока отказ не сработал.
  ({bool inTransaction, List<String> inserts})? faultPoint;

  void failAfterFavoritePlaceInsert() => _inserts = [];

  /// Учитывает вставки в любом виде, включая вставку с возвратом строк,
  /// которую drift выполняет через путь чтения.
  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final inserts = _inserts;
    if (inserts == null) return;
    for (final sql in statement.statements) {
      final table = _insertedTable.firstMatch(sql)?.group(1);
      if (table != null) inserts.add(table);
    }
    if (!inserts.contains('favorite_intentions')) return;
    _inserts = null;
    faultPoint = (
      inTransaction: !connection.autocommit,
      inserts: List.unmodifiable(inserts),
    );
    throw sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'Управляемый отказ после вставки места избранного',
    );
  }
}

/// Прозрачная обёртка настоящего Drift-адаптера: запоминает команды,
/// дошедшие до хранилища, считает действующие наблюдения тегов и по
/// требованию задерживает исполнение ближайшего создания намерения.
final class _ObservedGraph implements PersonalGraphRepository {
  _ObservedGraph(this._delegate);

  final PersonalGraphRepository _delegate;
  final _observations = <TagId, int>{};
  Completer<void>? _creationGate;

  /// Команды в порядке поступления в хранилище.
  final commands = <Object>[];

  /// Создание принято координатором и ждёт [releaseCreation].
  var isHoldingCreation = false;

  /// Число подписок на наблюдение тега [id], которые ещё не освобождены.
  int observations(TagId id) => _observations[id] ?? 0;

  void holdNextCreation() => _creationGate = Completer<void>();

  /// Освобождает задержанное создание; `true`, если оно ещё ждало.
  bool releaseCreation() {
    final gate = _creationGate;
    if (gate == null || gate.isCompleted) return false;
    gate.complete();
    return true;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command);
    final gate = _creationGate;
    if (command is CreateIntention && gate != null) {
      isHoldingCreation = true;
      await gate.future;
      isHoldingCreation = false;
      _creationGate = null;
    }
    return _delegate.execute(command);
  }

  /// Наблюдение считается освобождённым, как только потребитель отменил
  /// подписку: адаптер может завершить своё чтение позже.
  @override
  Stream<TagReadResult> watchTag(TagId id) {
    final source = _delegate.watchTag(id);
    StreamSubscription<TagReadResult>? subscription;
    late final StreamController<TagReadResult> observed;
    // Синхронная доставка сохраняет момент, в который потребитель видит
    // ответ адаптера и может отменить подписку.
    observed = StreamController<TagReadResult>(
      sync: true,
      onListen: () {
        _observations.update(id, (count) => count + 1, ifAbsent: () => 1);
        subscription = source.listen(
          observed.add,
          onError: observed.addError,
          onDone: observed.close,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        _observations.update(id, (count) => count - 1);
        unawaited(subscription?.cancel());
      },
    );
    return observed.stream;
  }

  @override
  Future<FavoriteIntentionsResult> getFavoriteIntentions() =>
      _delegate.getFavoriteIntentions();

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => _delegate.getCatalogPage(query);

  @override
  Future<Result<IntentionCatalogReconciliationOutcome>>
  getCatalogReconciliationPortion(IntentionCatalogReconciliationQuery query) =>
      _delegate.getCatalogReconciliationPortion(query);

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => _delegate.getDailyChoiceCatalogPage(query);

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => _delegate.watchIntention(id);

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => _delegate.getRelationCounts(intentionId);

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => _delegate.getRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _delegate.watchRelation(id);

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => _delegate.getSelectedRelations(query);

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => _delegate.watchSelectedRelations(query);

  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => _delegate.getChoicePathSuggestions(query);

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => _delegate.getChoicePathContinuations(query);

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      _delegate.getDailyChoice(id);

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      _delegate.watchDailyChoice(id);

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) =>
      _delegate.getTagCatalog(mode);

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) =>
      _delegate.getTagAssignments(intentionId);

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    IntentionId intentionId,
  ) => _delegate.getTagAssignmentStatus(tagId, intentionId);

  @override
  Future<TaggedIntentionsPageResult> getTaggedIntentionsPage(
    TaggedIntentionsQuery query,
  ) => _delegate.getTaggedIntentionsPage(query);
}
