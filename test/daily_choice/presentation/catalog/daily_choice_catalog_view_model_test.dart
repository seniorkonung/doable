import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_local_date.dart';
import '../../../support/favorite_read_contract_test_fallback.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/catalog_reconciliation_test_fallback.dart';

void main() {
  test('первое чтение ограничено локальным сегодня со всеми состояниями выполнения', () {
    final harness = _Harness();
    addTearDown(harness.dispose);

    final initial = harness.state;
    expect(initial, isA<DailyChoiceCatalogInitialLoad>());
    expect(initial.selection.date, _today);
    expect(initial.selection.isCompleted, isNull);
    final query = harness.repository.queries.single;
    expect(query.date, _today);
    expect(query.isCompleted, isNull);
    expect(query.cursor, isNull);
    expect(harness.localDate.readCount, 1);
  });

  test('перестроение модели не перечитывает часы и сохраняет выбор', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    harness.model.selectCompletion(false);
    harness.repository.first(1, [_item(1)], total: 1);
    await pumpEventQueue();

    harness.localDate.today = CalendarDate.fromParts(2026, 9, 25);
    harness.container.invalidate(dailyChoiceCatalogViewModelProvider);
    final rebuilt = harness.state;

    expect(rebuilt, isA<DailyChoiceCatalogInitialLoad>());
    expect(rebuilt.selection.date, _today);
    expect(rebuilt.selection.isCompleted, false);
    expect(harness.repository.queries, hasLength(3));
    expect(harness.repository.queries.last.date, _today);
    expect(harness.repository.queries.last.isCompleted, false);
    expect(harness.localDate.readCount, 1);
  });

  test(
    'новый день сохраняет охват и сразу начинает выдачу без прежних строк',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.model.selectCompletion(false);
      harness.repository.first(1, [_item(1)], total: 2, cursor: _Cursor());
      await pumpEventQueue();
      harness.repository.first(0, [], total: 0);
      await pumpEventQueue();
      expect((harness.state as DailyChoiceCatalogLoaded).items, isNotEmpty);

      final nextDay = CalendarDate.fromParts(2026, 9, 25);
      harness.model.selectDate(nextDay);

      final restarted = harness.state;
      expect(restarted, isA<DailyChoiceCatalogInitialLoad>());
      expect(restarted.selection.date, nextDay);
      expect(restarted.selection.isCompleted, false);
      final query = harness.repository.queries.last;
      expect(harness.repository.queries, hasLength(3));
      expect(query.date, nextDay);
      expect(query.isCompleted, false);
      expect(query.cursor, isNull);
    },
  );

  test('повторный выбор того же дня не читает хранилище', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    final loaded = harness.state;

    harness.model.selectDate(CalendarDate.fromParts(2026, 9, 24));

    expect(harness.state, same(loaded));
    expect(harness.repository.queries, hasLength(1));
  });

  test('сброс возвращает все состояния за тот же день и не читает при полном '
      'охвате', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final pastDay = CalendarDate.fromParts(2026, 9, 20);
    harness.model.selectDate(pastDay);
    harness.repository.first(1, [], total: 0);
    await pumpEventQueue();
    harness.model.selectCompletion(true);
    harness.repository.first(2, [], total: 0);
    await pumpEventQueue();

    harness.model.clearFilters();

    final reset = harness.state;
    expect(reset, isA<DailyChoiceCatalogInitialLoad>());
    expect(reset.selection.date, pastDay);
    expect(reset.selection.isCompleted, isNull);
    expect(harness.repository.queries, hasLength(4));
    expect(harness.repository.queries.last.date, pastDay);
    expect(harness.repository.queries.last.isCompleted, isNull);

    harness.repository.first(3, [_item(1, date: pastDay)], total: 1);
    await pumpEventQueue();
    final loaded = harness.state;
    harness.model.clearFilters();
    expect(harness.state, same(loaded));
    expect(harness.repository.queries, hasLength(4));
  });

  test('каждый запрос модели ограничен выбранным днём: первые порции, '
      'продолжения, пересборка и повторы', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    const unavailable = DailyChoiceCatalogUnavailableFailure();

    // Первая порция и её явный повтор.
    harness.repository.fail(0, unavailable);
    await pumpEventQueue();
    final retryFirst = harness.model.retryFirstPage();
    harness.repository.first(1, [_item(1)], total: 4, cursor: _Cursor());
    await retryFirst;

    // Продолжение и его явный повтор.
    final load = harness.model.loadMore();
    harness.repository.fail(2, unavailable);
    await load;
    final retryMore = harness.model.retryLoadMore();
    harness.repository.more(3, [_item(2)], cursor: _Cursor());
    await retryMore;

    // Пересборка после подтверждённой команды и её явный повтор.
    final creation = harness.createChoice(5, revision: 2);
    harness.repository.succeedCreation(0, 5, revision: 2);
    await creation.future;
    await pumpEventQueue();
    harness.repository.fail(4, unavailable);
    await pumpEventQueue();
    expect(
      (harness.state as DailyChoiceCatalogLoaded).freshness,
      DailyChoiceCatalogFreshness.stale,
    );
    final retryRefresh = harness.model.retryRefresh();
    harness.repository.first(
      5,
      [_item(5)],
      total: 5,
      cursor: _Cursor(),
      revision: 2,
    );
    await pumpEventQueue();
    harness.repository.more(6, [_item(1)], cursor: _Cursor(), revision: 2);
    await retryRefresh;

    // Перестроение модели.
    harness.container.invalidate(dailyChoiceCatalogViewModelProvider);
    expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());

    final queries = harness.repository.queries;
    expect(queries, hasLength(8));
    expect(
      [
        for (final (index, query) in queries.indexed)
          if (query.cursor != null) index,
      ],
      [2, 3, 6],
    );
    expect(queries.map((query) => query.date), everyElement(_today));
  });

  test('фильтр меняет поколение и отклоняет позднюю первую порцию', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final date = CalendarDate.fromParts(2026, 9, 25);
    harness.model.selectDate(date);
    expect(harness.repository.queries[1].date, date);
    harness.repository.first(1, [_item(2, date: date)], total: 1);
    await pumpEventQueue();
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    expect(
      (harness.state as DailyChoiceCatalogLoaded).items.single.id,
      _choiceId(2),
    );
    expect(harness.state.selection.date, date);
  });

  test(
    'изменение выбора пересобирает загруженную часть и количество вместе',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final cursor = _Cursor();
      harness.repository.first(
        0,
        [_item(1), _item(2)],
        total: 3,
        cursor: cursor,
      );
      await pumpEventQueue();
      final load = harness.model.loadMore();
      expect(harness.repository.queries[1].cursor, same(cursor));
      harness.repository.more(1, [_item(3)]);
      await load;

      final completion = harness.createChoice(4, revision: 2);
      harness.repository.succeedCreation(0, 4, revision: 2);
      await completion.future;
      await pumpEventQueue();
      expect(harness.state, isA<DailyChoiceCatalogLoaded>());
      expect(
        (harness.state as DailyChoiceCatalogLoaded).freshness,
        DailyChoiceCatalogFreshness.refreshing,
      );
      expect(
        (harness.state as DailyChoiceCatalogLoaded).items.map((e) => e.id),
        [_choiceId(1), _choiceId(2), _choiceId(3)],
      );

      final refreshedCursor = _Cursor();
      harness.repository.first(
        2,
        [_item(4), _item(1)],
        total: 4,
        cursor: refreshedCursor,
        revision: 2,
      );
      await pumpEventQueue();
      expect((harness.state as DailyChoiceCatalogLoaded).totalCount, 3);
      harness.repository.more(3, [_item(2), _item(3)], revision: 2);
      await pumpEventQueue();
      final current = harness.state as DailyChoiceCatalogLoaded;
      expect(current.freshness, DailyChoiceCatalogFreshness.current);
      expect(current.totalCount, 4);
      expect(current.items.map((e) => e.id), [
        _choiceId(4),
        _choiceId(1),
        _choiceId(2),
        _choiceId(3),
      ]);
    },
  );

  test(
    'ошибка сборки сохраняет прежний снимок и допускает только уместный повтор',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.first(0, [_item(1)], total: 1);
      await pumpEventQueue();
      final completion = harness.createChoice(2, revision: 2);
      harness.repository.succeedCreation(0, 2, revision: 2);
      await completion.future;
      await pumpEventQueue();
      harness.repository.fail(1, const DailyChoiceCatalogCorruptionFailure());
      await pumpEventQueue();
      final stale = harness.state as DailyChoiceCatalogLoaded;
      expect(stale.items.single.id, _choiceId(1));
      expect(stale.freshness, DailyChoiceCatalogFreshness.stale);
      expect(stale.refreshFailure, isA<DailyChoiceCatalogCorruptionFailure>());
      await harness.model.retryRefresh();
      expect(harness.repository.queries, hasLength(2));
    },
  );

  test(
    'посторонняя ревизия требует новой основы до следующей порции',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.first(0, [_item(1)], total: 2, cursor: _Cursor());
      await pumpEventQueue();
      final completion = harness.createChoice(2, revision: 2);
      harness.repository.succeedUnrelatedCreation(0, 2, revision: 2);
      await completion.future;
      await pumpEventQueue();
      final load = harness.model.loadMore();
      expect(harness.repository.queries[1].cursor, isNull);
      harness.repository.first(
        1,
        [_item(2)],
        total: 2,
        revision: 2,
        cursor: _Cursor(),
      );
      await pumpEventQueue();
      harness.repository.more(2, [_item(1)], revision: 2);
      await load;
      expect(
        (harness.state as DailyChoiceCatalogLoaded).revision.compareTo(
          const _Revision(2),
        ),
        GraphRevisionOrder.same,
      );
    },
  );

  test('удаление во время подгрузки не возвращает удалённую строку', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.first(
      0,
      [_item(1), _item(2)],
      total: 3,
      cursor: _Cursor(),
    );
    await pumpEventQueue();
    final oldLoad = harness.model.loadMore();
    final deletion = harness.coordinator.acceptDailyChoiceDelete(
      DeleteDailyChoice(_choiceId(1)),
    ) as DailyChoiceCommandAccepted;
    harness.repository.succeedDeletion(0, 1, revision: 2);
    await deletion.future;
    await pumpEventQueue();
    expect(
      (harness.state as DailyChoiceCatalogLoaded).freshness,
      DailyChoiceCatalogFreshness.refreshing,
    );
    harness.repository.more(1, [_item(3)]);
    await oldLoad;
    expect(
      (harness.state as DailyChoiceCatalogLoaded).items.first.id,
      _choiceId(1),
    );
    harness.repository.first(2, [_item(2), _item(3)], total: 2, revision: 2);
    await pumpEventQueue();
    final updated = harness.state as DailyChoiceCatalogLoaded;
    expect(updated.items.map((item) => item.id), [_choiceId(2), _choiceId(3)]);
    expect(updated.totalCount, 2);
    expect(updated.freshness, DailyChoiceCatalogFreshness.current);
  });

  test('выполнение не меняет фильтр, а сброс возвращает все состояния того же '
      'дня', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model.selectCompletion(false);
    harness.repository.first(1, [_item(1)], total: 1);
    await pumpEventQueue();
    harness.repository.first(0, [], total: 0);
    await pumpEventQueue();
    final creation = harness.createChoice(2, revision: 2);
    harness.repository.succeedCreation(0, 2, revision: 2, isCompleted: true);
    await creation.future;
    await pumpEventQueue();
    expect(harness.state.selection.isCompleted, false);
    expect((harness.state as DailyChoiceCatalogLoaded).needsRebase, isTrue);
    expect(
      (harness.state as DailyChoiceCatalogLoaded).items.single.id,
      _choiceId(1),
    );
    harness.model.clearFilters();
    expect(harness.repository.queries.last.isCompleted, isNull);
    expect(harness.repository.queries.last.date, _today);
    harness.repository.first(2, [_item(2), _item(1)], total: 2, revision: 2);
    await pumpEventQueue();
    expect((harness.state as DailyChoiceCatalogLoaded).totalCount, 2);
  });

  test(
    'смена даты убирает строку из выбранного дня и показывает её в новом дне',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final oldDate = CalendarDate.fromParts(2026, 9, 25);
      final newDate = CalendarDate.fromParts(2026, 9, 26);
      harness.model.selectDate(oldDate);
      expect(harness.repository.queries[1].date, oldDate);
      harness.repository.first(1, [_item(1, date: oldDate)], total: 1);
      await pumpEventQueue();
      harness.repository.first(0, [], total: 0);
      await pumpEventQueue();

      final update = harness.coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: _choiceId(1),
          patch: DailyChoiceFieldsPatch(date: DailyChoiceFieldSet(newDate)),
        ),
      ) as DailyChoiceCommandAccepted;
      harness.repository.succeedDateUpdate(0, 1, oldDate, newDate, revision: 2);
      await update.future;
      await pumpEventQueue();
      expect(
        (harness.state as DailyChoiceCatalogLoaded).freshness,
        DailyChoiceCatalogFreshness.refreshing,
      );
      expect(harness.repository.queries[2].date, oldDate);
      harness.repository.first(2, [], total: 0, revision: 2);
      await pumpEventQueue();
      expect(harness.state, isA<DailyChoiceCatalogEmpty>());
      expect(harness.state.selection.date, oldDate);

      harness.model.selectDate(newDate);
      expect(harness.repository.queries[3].date, newDate);
      harness.repository.first(
        3,
        [_item(1, date: newDate)],
        total: 1,
        revision: 2,
      );
      await pumpEventQueue();
      expect(
        (harness.state as DailyChoiceCatalogLoaded).items.single.date,
        newDate,
      );
      expect(harness.state.selection.date, newDate);
    },
  );

  test('переименование участника обновляет показанную формулировку', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    final update = harness.coordinator.acceptExisting(
      UpdateIntention(
        id: _intentionId(1),
        title: 'Новое основание',
        description: null,
      ),
      presentationTitle: 'Основание',
    ) as IntentionCommandAccepted;
    harness.repository.succeedRename(1, revision: 2);
    await update.future;
    await pumpEventQueue();
    final newItem = DailyChoiceCatalogItem(
      id: _choiceId(1),
      source: DailyChoiceCatalogParticipant(
        id: _intentionId(1),
        title: 'Новое основание',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.notReady,
      ),
      selected: _item(1).selected,
      date: _today,
      isCompleted: false,
    );
    harness.repository.first(1, [newItem], total: 1, revision: 2);
    await pumpEventQueue();
    expect(
      (harness.state as DailyChoiceCatalogLoaded).items.single.source.title,
      'Новое основание',
    );
  });

  test('ответ прежней эпохи не заменяет подтверждённую новую основу', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final creation = harness.createChoice(2, revision: 1);
    harness.repository.succeedCreation(0, 2, revision: 1, epoch: 1);
    await creation.future;
    await pumpEventQueue();
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
    expect(harness.repository.queries, hasLength(2));
    harness.repository.first(
      1,
      [_item(2), _item(1)],
      total: 2,
      revision: 1,
      epoch: 1,
    );
    await pumpEventQueue();
    final current = harness.state as DailyChoiceCatalogLoaded;
    expect(current.items.map((item) => item.id), [_choiceId(2), _choiceId(1)]);
    expect(
      current.revision.compareTo(const _Revision(1, epoch: 1)),
      GraphRevisionOrder.same,
    );
  });

  test('тег обновляет основу перед продолжением, совпадение имени не повторяет чтение', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.first(0, [_item(1)], total: 2, cursor: _Cursor());
    await pumpEventQueue();

    final tag = Tag(id: _tagId(), name: TagName.fromInput('Дом'));
    const revision = _Revision(2);
    final creation = harness.coordinator.acceptTagCreation(
      TagCreationFormKey(),
      CreateTag(tag.name),
    ) as TagCommandAccepted;
    harness.repository.completeTag(
      0,
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagCreated(TagCreatedChange(revision: revision, after: tag)),
        ),
      ),
    );
    await creation.future;
    await pumpEventQueue();
    final old = harness.state as DailyChoiceCatalogLoaded;
    expect(old.needsRebase, isTrue);
    expect(old.items.map((item) => item.id), [_choiceId(1)]);

    final load = harness.model.loadMore();
    expect(harness.repository.queries[1].cursor, isNull);
    harness.repository.first(
      1,
      [_item(1)],
      total: 2,
      cursor: _Cursor(),
      revision: 2,
    );
    await pumpEventQueue();
    harness.repository.more(2, [_item(2)], revision: 2);
    await load;
    final current = harness.state as DailyChoiceCatalogLoaded;
    expect(current.revision.compareTo(revision), GraphRevisionOrder.same);
    expect(current.items.map((item) => item.id), [_choiceId(1), _choiceId(2)]);

    final unchanged = harness.coordinator.acceptTagRename(
      RenameTag(tagId: tag.id, name: tag.name),
    ) as TagCommandAccepted;
    harness.repository.completeTag(
      1,
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagUnchanged(TagUnchangedChange(revision: revision, tag: tag)),
        ),
      ),
    );
    await unchanged.future;
    await pumpEventQueue();
    expect(harness.state, same(current));
    expect(harness.repository.queries, hasLength(3));
  });

  test('пакет тега другой эпохи не принимает старую первую страницу', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final accepted = harness.coordinator.acceptTagDelete(
      DeleteTag(_tagId()),
    ) as TagCommandAccepted;
    const revision = _Revision(1, epoch: 1);
    harness.repository.completeTag(
      0,
      TagCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: TagDeleted(
            TagDeletedChange(revision: revision, tagId: _tagId()),
          ),
        ),
      ),
    );
    await accepted.future;
    await pumpEventQueue();
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
    expect(harness.repository.queries, hasLength(2));
    harness.repository.first(1, [_item(2)], total: 1, revision: 1, epoch: 1);
    await pumpEventQueue();
    final current = harness.state as DailyChoiceCatalogLoaded;
    expect(current.revision.compareTo(revision), GraphRevisionOrder.same);
    expect(current.items.map((item) => item.id), [_choiceId(2)]);
  });

  group('поздние ответы и отказы после смены дня', () {
    final firstDay = CalendarDate.fromParts(2026, 10, 5);
    final secondDay = CalendarDate.fromParts(2026, 10, 6);
    const unavailable = DailyChoiceCatalogUnavailableFailure();

    List<DailyChoiceId> ids(DailyChoiceCatalogState state) => [
      for (final item in (state as DailyChoiceCatalogLoaded).items) item.id,
    ];

    for (final late in _lateResults) {
      test('поздняя первая порция прежних дней (${late.name}) не заменяет '
          'загрузку и выдачу выбранного дня', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final queries = harness.repository.queries;
        harness.model.selectDate(firstDay);
        harness.model.selectDate(secondDay);
        expect(queries, hasLength(3));
        _expectQuery(queries[1], date: firstDay);
        _expectQuery(queries[2], date: secondDay);

        // Ответ за 2026-10-05 приходит раньше ответа за 2026-10-06.
        late.completeFirst(harness.repository, 1);
        await pumpEventQueue();
        expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
        expect(harness.state.selection.date, secondDay);

        final cursor = _Cursor();
        harness.repository.first(
          2,
          [_item(3, date: secondDay)],
          total: 2,
          cursor: cursor,
        );
        await pumpEventQueue();
        final loaded = harness.state as DailyChoiceCatalogLoaded;
        expect(loaded.selection.date, secondDay);
        expect(ids(loaded), [_choiceId(3)]);
        expect(loaded.totalCount, 2);
        expect(loaded.nextCursor, same(cursor));

        // Первое чтение сегодняшнего дня завершается уже после выдачи.
        late.completeFirst(harness.repository, 0);
        await pumpEventQueue();
        expect(harness.state, same(loaded));
        expect(queries, hasLength(3));

        final load = harness.model.loadMore();
        expect(queries, hasLength(4));
        _expectQuery(queries[3], date: secondDay, cursor: cursor);
        harness.repository.more(3, [_item(4, date: secondDay)]);
        await load;
        expect(ids(harness.state), [_choiceId(3), _choiceId(4)]);
      });

      test('позднее продолжение прежних дней (${late.name}) не меняет выдачу '
          'выбранного дня и не начинает чтений', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final queries = harness.repository.queries;
        harness.repository.first(0, [_item(1)], total: 2, cursor: _Cursor());
        await pumpEventQueue();
        unawaited(harness.model.loadMore());
        harness.model.selectDate(firstDay);
        final firstDayCursor = _Cursor();
        harness.repository.first(
          2,
          [_item(3, date: firstDay)],
          total: 2,
          cursor: firstDayCursor,
        );
        await pumpEventQueue();
        unawaited(harness.model.loadMore());
        _expectQuery(queries[3], date: firstDay, cursor: firstDayCursor);
        harness.model.selectDate(secondDay);
        expect(queries, hasLength(5));

        // Продолжение сегодняшнего дня приходит до первой порции выбранного.
        late.completeContinuation(harness.repository, 1);
        await pumpEventQueue();
        expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
        expect(harness.state.selection.date, secondDay);
        expect(queries, hasLength(5));

        final cursor = _Cursor();
        harness.repository.first(
          4,
          [_item(5, date: secondDay)],
          total: 2,
          cursor: cursor,
        );
        await pumpEventQueue();
        final loaded = harness.state as DailyChoiceCatalogLoaded;
        expect(ids(loaded), [_choiceId(5)]);
        expect(loaded.totalCount, 2);
        expect(loaded.nextCursor, same(cursor));
        expect(loaded.pageStatus, isA<DailyChoiceCatalogPageIdle>());

        // Продолжение за 2026-10-05 приходит уже после выдачи выбранного дня.
        late.completeContinuation(harness.repository, 3);
        await pumpEventQueue();
        expect(harness.state, same(loaded));
        expect(queries, hasLength(5));

        final load = harness.model.loadMore();
        _expectQuery(queries[5], date: secondDay, cursor: cursor);
        harness.repository.more(5, [_item(6, date: secondDay)]);
        await load;
        expect(ids(harness.state), [_choiceId(5), _choiceId(6)]);
      });

      test('поздняя пересборка прежних дней (${late.name}) не меняет выдачу '
          'выбранного дня и не продолжает чтение', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final queries = harness.repository.queries;
        harness.repository.first(0, [_item(1), _item(2)], total: 2);
        await pumpEventQueue();
        final todayCreation = harness.createChoice(5, revision: 2);
        harness.repository.succeedCreation(0, 5, revision: 2);
        await todayCreation.future;
        await pumpEventQueue();
        expect(
          (harness.state as DailyChoiceCatalogLoaded).freshness,
          DailyChoiceCatalogFreshness.refreshing,
        );
        _expectQuery(queries[1], date: _today);

        // Пересборка сегодняшнего дня остаётся на первой странице, а
        // пересборка 2026-10-05 — на продолжении.
        harness.model.selectDate(firstDay);
        harness.repository.first(
          2,
          [_item(3, date: firstDay), _item(4, date: firstDay)],
          total: 2,
          revision: 2,
        );
        await pumpEventQueue();
        final firstDayCreation = harness.createChoice(6, revision: 3);
        harness.repository.succeedCreation(1, 6, revision: 3, date: firstDay);
        await firstDayCreation.future;
        await pumpEventQueue();
        _expectQuery(queries[3], date: firstDay);
        final assemblyCursor = _Cursor();
        harness.repository.first(
          3,
          [_item(6, date: firstDay)],
          total: 3,
          cursor: assemblyCursor,
          revision: 3,
        );
        await pumpEventQueue();
        final refreshing = harness.state as DailyChoiceCatalogLoaded;
        expect(refreshing.freshness, DailyChoiceCatalogFreshness.refreshing);
        expect(ids(refreshing), [_choiceId(3), _choiceId(4)]);
        _expectQuery(queries[4], date: firstDay, cursor: assemblyCursor);
        harness.model.selectDate(secondDay);
        expect(queries, hasLength(6));

        late.completeFirst(harness.repository, 1);
        await pumpEventQueue();
        expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
        expect(harness.state.selection.date, secondDay);
        expect(queries, hasLength(6));

        final cursor = _Cursor();
        harness.repository.first(
          5,
          [_item(7, date: secondDay)],
          total: 2,
          cursor: cursor,
          revision: 3,
        );
        await pumpEventQueue();
        final loaded = harness.state as DailyChoiceCatalogLoaded;
        expect(loaded.selection.date, secondDay);
        expect(ids(loaded), [_choiceId(7)]);
        expect(loaded.freshness, DailyChoiceCatalogFreshness.current);
        expect(loaded.refreshFailure, isNull);

        late.completeContinuation(harness.repository, 4);
        await pumpEventQueue();
        expect(harness.state, same(loaded));
        expect(queries, hasLength(6));

        final load = harness.model.loadMore();
        _expectQuery(queries[6], date: secondDay, cursor: cursor);
        harness.repository.more(6, [_item(8, date: secondDay)], revision: 3);
        await load;
        expect(ids(harness.state), [_choiceId(7), _choiceId(8)]);
      });
    }

    test('после возврата к прежнему дню ответы его первого выбора не '
        'публикуются и не продолжают чтение', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final queries = harness.repository.queries;
      harness.model.selectDate(firstDay);
      harness.model.selectDate(secondDay);
      harness.model.selectDate(firstDay);
      expect(queries, hasLength(4));
      _expectQuery(queries[3], date: firstDay);

      // Порция первого выбора 2026-10-05 подходит под условия дня, но
      // принадлежит прежнему получению.
      harness.repository.first(
        1,
        [_item(1, date: firstDay)],
        total: 3,
        cursor: _Cursor(),
      );
      harness.repository.first(2, [_item(2, date: secondDay)], total: 1);
      await pumpEventQueue();
      expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
      expect(harness.state.selection.date, firstDay);
      expect(queries, hasLength(4));

      final cursor = _Cursor();
      harness.repository.first(
        3,
        [_item(3, date: firstDay), _item(1, date: firstDay)],
        total: 3,
        cursor: cursor,
        revision: 2,
      );
      await pumpEventQueue();
      final loaded = harness.state as DailyChoiceCatalogLoaded;
      expect(ids(loaded), [_choiceId(3), _choiceId(1)]);
      expect(loaded.totalCount, 3);
      expect(loaded.nextCursor, same(cursor));

      final load = harness.model.loadMore();
      expect(queries, hasLength(5));
      _expectQuery(queries[4], date: firstDay, cursor: cursor);
      harness.repository.more(4, [_item(4, date: firstDay)], revision: 2);
      await load;
      expect(ids(harness.state), [_choiceId(3), _choiceId(1), _choiceId(4)]);
    });

    test('после возврата к прежнему дню его прерванная пересборка не '
        'продолжает чтение и не заменяет новую выдачу', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final queries = harness.repository.queries;
      harness.model.selectDate(firstDay);
      harness.repository.first(1, [
        _item(1, date: firstDay),
        _item(2, date: firstDay),
      ], total: 2);
      await pumpEventQueue();
      final creation = harness.createChoice(5, revision: 2);
      harness.repository.succeedCreation(0, 5, revision: 2, date: firstDay);
      await creation.future;
      await pumpEventQueue();
      _expectQuery(queries[2], date: firstDay);
      harness.model.selectDate(secondDay);
      harness.model.selectDate(firstDay);
      expect(queries, hasLength(5));

      // Первая страница прерванной пересборки подходит под условия дня и
      // потребовала бы продолжения.
      harness.repository.first(
        2,
        [_item(5, date: firstDay)],
        total: 3,
        cursor: _Cursor(),
        revision: 2,
      );
      await pumpEventQueue();
      expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
      expect(queries, hasLength(5));

      harness.repository.first(
        4,
        [
          _item(5, date: firstDay),
          _item(1, date: firstDay),
          _item(2, date: firstDay),
        ],
        total: 3,
        revision: 2,
      );
      await pumpEventQueue();
      final loaded = harness.state as DailyChoiceCatalogLoaded;
      expect(loaded.freshness, DailyChoiceCatalogFreshness.current);
      expect(ids(loaded), [_choiceId(5), _choiceId(1), _choiceId(2)]);

      harness.repository.first(3, [], total: 0, revision: 2);
      await pumpEventQueue();
      expect(harness.state, same(loaded));
      expect(queries, hasLength(5));
    });

    test(
      'подтверждённое изменение во время первого чтения выбранного дня '
      'повторяет его с теми же условиями, не возвращая прежний день',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final queries = harness.repository.queries;
        harness.model.selectCompletion(false);
        harness.model.selectDate(firstDay);
        final creation = harness.createChoice(2, revision: 2);
        harness.repository.succeedCreation(0, 2, revision: 2, date: firstDay);
        await creation.future;
        await pumpEventQueue();
        expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());

        // Порция, прочитанная до изменения, требует нового чтения того же дня.
        harness.repository.first(2, [_item(3, date: firstDay)], total: 1);
        await pumpEventQueue();
        expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
        expect(queries, hasLength(4));
        _expectQuery(queries[3], date: firstDay, isCompleted: false);

        harness.repository.first(1, [_item(1)], total: 1, revision: 2);
        harness.repository.first(0, [_item(1)], total: 1, revision: 2);
        await pumpEventQueue();
        expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
        expect(queries, hasLength(4));

        harness.repository.first(
          3,
          [_item(2, date: firstDay), _item(3, date: firstDay)],
          total: 2,
          revision: 2,
        );
        await pumpEventQueue();
        final loaded = harness.state as DailyChoiceCatalogLoaded;
        expect(loaded.selection.date, firstDay);
        expect(loaded.selection.isCompleted, false);
        expect(ids(loaded), [_choiceId(2), _choiceId(3)]);
        expect(loaded.totalCount, 2);
        expect(
          loaded.revision.compareTo(const _Revision(2)),
          GraphRevisionOrder.same,
        );
        expect(loaded.freshness, DailyChoiceCatalogFreshness.current);
      },
    );

    test('подтверждённое изменение во время подгрузки выбранного дня '
        'пересобирает его выдачу, отбрасывая позднее продолжение', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final queries = harness.repository.queries;
      harness.model.selectDate(firstDay);
      final cursor = _Cursor();
      harness.repository.first(
        1,
        [_item(3, date: firstDay)],
        total: 2,
        cursor: cursor,
      );
      await pumpEventQueue();
      final load = harness.model.loadMore();
      _expectQuery(queries[2], date: firstDay, cursor: cursor);

      final creation = harness.createChoice(5, revision: 2);
      harness.repository.succeedUnrelatedCreation(0, 5, revision: 2);
      await creation.future;
      await pumpEventQueue();
      final refreshing = harness.state as DailyChoiceCatalogLoaded;
      expect(refreshing.freshness, DailyChoiceCatalogFreshness.refreshing);
      expect(ids(refreshing), [_choiceId(3)]);
      expect(queries, hasLength(4));
      _expectQuery(queries[3], date: firstDay);

      harness.repository.more(2, [_item(4, date: firstDay)]);
      harness.repository.first(0, [_item(1)], total: 1);
      await load;
      await pumpEventQueue();
      expect(harness.state, same(refreshing));
      expect(queries, hasLength(4));

      harness.repository.first(
        3,
        [_item(3, date: firstDay), _item(4, date: firstDay)],
        total: 2,
        revision: 2,
      );
      await pumpEventQueue();
      final current = harness.state as DailyChoiceCatalogLoaded;
      expect(current.selection.date, firstDay);
      expect(current.freshness, DailyChoiceCatalogFreshness.current);
      expect(ids(current), [_choiceId(3), _choiceId(4)]);
      expect(current.totalCount, 2);
      expect(
        current.revision.compareTo(const _Revision(2)),
        GraphRevisionOrder.same,
      );
    });

    test('временный отказ каждого чтения выбранного дня повторяется явно с '
        'его датой и охватом, сохраняя прежний снимок до замены', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final queries = harness.repository.queries;
      harness.model.selectCompletion(false);
      harness.model.selectDate(firstDay);

      // Первая порция.
      harness.repository.fail(2, unavailable);
      await pumpEventQueue();
      final initialFailure = harness.state as DailyChoiceCatalogInitialFailure;
      expect(initialFailure.selection.date, firstDay);
      expect(initialFailure.canRetry, isTrue);
      harness.repository.first(1, [_item(1)], total: 1);
      await pumpEventQueue();
      expect(harness.state, same(initialFailure));
      final retryFirst = harness.model.retryFirstPage();
      expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
      _expectQuery(queries[3], date: firstDay, isCompleted: false);
      final cursor = _Cursor();
      harness.repository.first(
        3,
        [_item(3, date: firstDay)],
        total: 2,
        cursor: cursor,
      );
      await retryFirst;

      // Подгрузка.
      final load = harness.model.loadMore();
      _expectQuery(
        queries[4],
        date: firstDay,
        isCompleted: false,
        cursor: cursor,
      );
      harness.repository.fail(4, unavailable);
      await load;
      final pageFailure = harness.state as DailyChoiceCatalogLoaded;
      expect(ids(pageFailure), [_choiceId(3)]);
      expect(
        (pageFailure.pageStatus as DailyChoiceCatalogPageFailure).canRetry,
        isTrue,
      );
      final retryMore = harness.model.retryLoadMore();
      _expectQuery(
        queries[5],
        date: firstDay,
        isCompleted: false,
        cursor: cursor,
      );
      harness.repository.more(5, [_item(4, date: firstDay)]);
      await retryMore;
      expect(ids(harness.state), [_choiceId(3), _choiceId(4)]);

      // Обновление после подтверждённой команды того же дня.
      final creation = harness.createChoice(5, revision: 2);
      harness.repository.succeedCreation(0, 5, revision: 2, date: firstDay);
      await creation.future;
      await pumpEventQueue();
      final refreshing = harness.state as DailyChoiceCatalogLoaded;
      expect(refreshing.freshness, DailyChoiceCatalogFreshness.refreshing);
      expect(ids(refreshing), [_choiceId(3), _choiceId(4)]);
      expect(refreshing.totalCount, 2);
      _expectQuery(queries[6], date: firstDay, isCompleted: false);
      harness.repository.fail(6, unavailable);
      await pumpEventQueue();
      final stale = harness.state as DailyChoiceCatalogLoaded;
      expect(stale.freshness, DailyChoiceCatalogFreshness.stale);
      expect(stale.refreshFailure, same(unavailable));
      expect(ids(stale), [_choiceId(3), _choiceId(4)]);
      expect(stale.totalCount, 2);
      final retryRefresh = harness.model.retryRefresh();
      _expectQuery(queries[7], date: firstDay, isCompleted: false);
      harness.repository.first(
        7,
        [
          _item(5, date: firstDay),
          _item(3, date: firstDay),
          _item(4, date: firstDay),
        ],
        total: 3,
        revision: 2,
      );
      await retryRefresh;
      final replaced = harness.state as DailyChoiceCatalogLoaded;
      expect(replaced.freshness, DailyChoiceCatalogFreshness.current);
      expect(replaced.refreshFailure, isNull);
      expect(ids(replaced), [_choiceId(5), _choiceId(3), _choiceId(4)]);
      expect(replaced.totalCount, 3);
      expect(queries, hasLength(8));
    });

    for (final (outcome, failure) in const [
      ('повреждение', DailyChoiceCatalogCorruptionFailure()),
      ('неизвестный отказ', DailyChoiceCatalogUnexpectedFailure()),
    ]) {
      test('$outcome чтений выбранного дня остаётся отдельным объяснением без '
          'повтора', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final queries = harness.repository.queries;
        harness.model.selectDate(firstDay);

        harness.repository.fail(1, failure);
        await pumpEventQueue();
        final initialFailure =
            harness.state as DailyChoiceCatalogInitialFailure;
        expect(initialFailure.failure, same(failure));
        expect(initialFailure.canRetry, isFalse);
        await harness.model.retryFirstPage();
        expect(harness.state, same(initialFailure));
        expect(queries, hasLength(2));

        harness.model.selectDate(secondDay);
        harness.repository.first(
          2,
          [_item(3, date: secondDay)],
          total: 2,
          cursor: _Cursor(),
        );
        await pumpEventQueue();
        final load = harness.model.loadMore();
        harness.repository.fail(3, failure);
        await load;
        final pageFailure = harness.state as DailyChoiceCatalogLoaded;
        final pageStatus =
            pageFailure.pageStatus as DailyChoiceCatalogPageFailure;
        expect(pageStatus.failure, same(failure));
        expect(pageStatus.canRetry, isFalse);
        expect(ids(pageFailure), [_choiceId(3)]);
        await harness.model.retryLoadMore();
        expect(harness.state, same(pageFailure));
        expect(queries, hasLength(4));

        final creation = harness.createChoice(5, revision: 2);
        harness.repository.succeedCreation(0, 5, revision: 2, date: secondDay);
        await creation.future;
        await pumpEventQueue();
        _expectQuery(queries[4], date: secondDay);
        harness.repository.fail(4, failure);
        await pumpEventQueue();
        final stale = harness.state as DailyChoiceCatalogLoaded;
        expect(stale.freshness, DailyChoiceCatalogFreshness.stale);
        expect(stale.refreshFailure, same(failure));
        expect(ids(stale), [_choiceId(3)]);
        await harness.model.retryRefresh();
        expect(harness.state, same(stale));
        expect(queries, hasLength(5));
      });
    }

    // Состояния выдачи сегодняшнего дня с охватом невыполненных: первое
    // чтение без охвата (запрос 0) остаётся незавершённым.
    for (final (state, prepare) in <(String, Future<void> Function(_Harness))>[
      ('загрузка первой порции', (harness) async {}),
      for (final (kind, failure) in const [
        ('временный отказ', DailyChoiceCatalogUnavailableFailure()),
        ('повреждение', DailyChoiceCatalogCorruptionFailure()),
        ('неизвестный отказ', DailyChoiceCatalogUnexpectedFailure()),
      ])
        (
          '$kind первой порции',
          (harness) async {
            harness.repository.fail(1, failure);
            await pumpEventQueue();
          },
        ),
      (
        'пустая выдача',
        (harness) async {
          harness.repository.first(1, [], total: 0);
          await pumpEventQueue();
        },
      ),
      (
        'подгрузка',
        (harness) async {
          harness.repository.first(1, [_item(1)], total: 2, cursor: _Cursor());
          await pumpEventQueue();
          unawaited(harness.model.loadMore());
        },
      ),
      (
        'отказ подгрузки',
        (harness) async {
          harness.repository.first(1, [_item(1)], total: 2, cursor: _Cursor());
          await pumpEventQueue();
          final load = harness.model.loadMore();
          harness.repository.fail(2, unavailable);
          await load;
        },
      ),
      (
        'обновление после команды',
        (harness) async {
          harness.repository.first(1, [_item(1)], total: 1);
          await pumpEventQueue();
          final creation = harness.createChoice(2, revision: 2);
          harness.repository.succeedCreation(0, 2, revision: 2);
          await creation.future;
          await pumpEventQueue();
        },
      ),
      (
        'отказ обновления',
        (harness) async {
          harness.repository.first(1, [_item(1)], total: 1);
          await pumpEventQueue();
          final creation = harness.createChoice(2, revision: 2);
          harness.repository.succeedCreation(0, 2, revision: 2);
          await creation.future;
          await pumpEventQueue();
          harness.repository.fail(2, unavailable);
          await pumpEventQueue();
        },
      ),
    ]) {
      test('из состояния «$state» другой день выбирается с прежним охватом и '
          'получает собственную выдачу', () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final queries = harness.repository.queries;
        harness.model.selectCompletion(false);
        await prepare(harness);
        final readCount = queries.length;

        harness.model.selectDate(firstDay);

        final restarted = harness.state;
        expect(restarted, isA<DailyChoiceCatalogInitialLoad>());
        expect(restarted.selection.date, firstDay);
        expect(restarted.selection.isCompleted, false);
        expect(queries, hasLength(readCount + 1));
        _expectQuery(queries.last, date: firstDay, isCompleted: false);

        harness.repository.first(
          readCount,
          [_item(3, date: firstDay)],
          total: 1,
          revision: 2,
        );
        await pumpEventQueue();
        final loaded = harness.state as DailyChoiceCatalogLoaded;
        expect(loaded.selection.date, firstDay);
        expect(ids(loaded), [_choiceId(3)]);
        expect(loaded.freshness, DailyChoiceCatalogFreshness.current);
        expect(loaded.pageStatus, isA<DailyChoiceCatalogPageIdle>());
        expect(queries, hasLength(readCount + 1));
      });
    }
  });
}

/// Локальное сегодня проверок модели и дата строк фикстуры: первое чтение
/// каталога охватывает этот день.
final _today = CalendarDate.fromParts(2026, 9, 24);

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
        localDate.override,
      ],
    );
    subscription = container.listen(
      dailyChoiceCatalogViewModelProvider,
      (_, _) {},
    );
  }

  final _Repository repository = _Repository();
  final localDate = ControlledDailyChoiceLocalDate(_today);
  late final ProviderContainer container;
  late final ProviderSubscription<DailyChoiceCatalogState> subscription;
  DailyChoiceCatalogViewModel get model =>
      container.read(dailyChoiceCatalogViewModelProvider.notifier);
  DailyChoiceCatalogState get state =>
      container.read(dailyChoiceCatalogViewModelProvider);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  DailyChoiceCommandAccepted createChoice(int id, {required int revision}) =>
      coordinator.acceptDailyChoiceCreation(
        DailyChoiceCreationFormKey(),
        CreateDailyChoice(
          sourceIntentionId: _intentionId(1),
          selectedIntentionId: _intentionId(2),
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: _relationId(1),
              sourceIntentionId: _intentionId(1),
              type: LongTermRelationType.need,
              relatedIntentionId: _intentionId(2),
            ),
          ]),
          date: _today,
          description: null,
          isCompleted: false,
        ),
      ) as DailyChoiceCommandAccepted;
  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Repository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  final queries = <DailyChoiceCatalogQuery>[];
  final _pages = <Completer<DailyChoiceCatalogPageResult>>[];
  final _commands = <Completer<DailyChoiceCommandResult>>[];
  final _intentionCommands =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  final _tagCommands = <Completer<TagCommandResult>>[];

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    queries.add(query);
    final request = Completer<DailyChoiceCatalogPageResult>();
    _pages.add(request);
    return request.future;
  }

  void first(
    int index,
    List<DailyChoiceCatalogItem> items, {
    required int total,
    DailyChoiceCatalogCursor? cursor,
    int revision = 1,
    int epoch = 0,
  }) => _pages[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogFirstPage(
        items: items,
        totalCount: total,
        nextCursor: cursor,
        revision: _Revision(revision, epoch: epoch),
      ),
    ),
  );
  void more(
    int index,
    List<DailyChoiceCatalogItem> items, {
    DailyChoiceCatalogCursor? cursor,
    int revision = 1,
  }) => _pages[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogContinuationPage(
        items: items,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );
  void fail(int index, DailyChoiceCatalogReadFailure failure) =>
      _pages[index].complete(DailyChoiceCatalogPageError(failure));

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is TagCommand) {
      final request = Completer<TagCommandResult>();
      _tagCommands.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    if (command is UpdateIntention) {
      final request =
          Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
      _intentionCommands.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    final request = Completer<DailyChoiceCommandResult>();
    _commands.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void completeTag(int index, TagCommandResult result) =>
      _tagCommands[index].complete(result);

  void succeedCreation(
    int index,
    int id, {
    required int revision,
    bool isCompleted = false,
    int epoch = 0,
    CalendarDate? date,
  }) {
    final choice = DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: date ?? _today,
      description: null,
      isCompleted: isCompleted,
    );
    final change = DailyChoiceChange(
      revision: _Revision(revision, epoch: epoch),
      before: null,
      after: choice,
      releasedRelationIds: const [],
      occupiedRelationIds: [_relationId(1)],
      intentionCounts: {_intentionId(1): _counts(), _intentionId(2): _counts()},
      relationPermissions: {
        _relationId(1):
            const LongTermRelationPermissions.referencedByDailyPath(),
      },
    );
    _commands[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(revision, epoch: epoch),
          value: DailyChoiceCreated(
            choice: choice,
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(id),
                dailyChoiceId: choice.id,
                relationId: _relationId(1),
                previousStepId: null,
              ),
            ]),
            changes: [change],
          ),
        ),
      ),
    );
  }

  void succeedDeletion(int index, int id, {required int revision}) {
    final choice = DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: _today,
      description: null,
      isCompleted: false,
    );
    final change = DailyChoiceChange(
      revision: _Revision(revision),
      before: choice,
      after: null,
      releasedRelationIds: [_relationId(1)],
      occupiedRelationIds: const [],
      intentionCounts: {_intentionId(1): _counts(), _intentionId(2): _counts()},
      relationPermissions: {
        _relationId(1): const LongTermRelationPermissions.unrestricted(),
      },
    );
    _commands[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: DailyChoiceDeleted(choice: choice, changes: [change]),
        ),
      ),
    );
  }

  void succeedDateUpdate(
    int index,
    int id,
    CalendarDate beforeDate,
    CalendarDate afterDate, {
    required int revision,
  }) {
    DailyChoice choice(CalendarDate date) => DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: date,
      description: null,
      isCompleted: false,
    );
    final before = choice(beforeDate);
    final after = choice(afterDate);
    final change = DailyChoiceChange(
      revision: _Revision(revision),
      before: before,
      after: after,
      releasedRelationIds: const [],
      occupiedRelationIds: const [],
      intentionCounts: {_intentionId(1): _counts(), _intentionId(2): _counts()},
      relationPermissions: const {},
    );
    _commands[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: DailyChoiceFieldsUpdated(
            before: before,
            choice: after,
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(id),
                dailyChoiceId: after.id,
                relationId: _relationId(1),
                previousStepId: null,
              ),
            ]),
            changes: [change],
          ),
        ),
      ),
    );
  }

  void succeedRename(int id, {required int revision}) {
    final before = _IntentionEntry(_summary(id, 'Основание'));
    final after = _IntentionEntry(_summary(id, 'Новое основание'));
    final mutation = IntentionCatalogUpdated(
      revision: _Revision(revision),
      before: before,
      after: after,
    );
    final intention = Intention(
      id: _intentionId(id),
      title: 'Новое основание',
      description: null,
      readiness: IntentionReadiness.notReady,
      archiveState: IntentionArchiveState.active,
      createdAt: IntentionTimestamp(DateTime.utc(2026)),
      updatedAt: IntentionTimestamp(DateTime.utc(2026)),
    );
    _intentionCommands[0].complete(
      ResultSuccess(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: IntentionSaved(intention, catalogMutation: mutation),
        ),
      ),
    );
  }

  void succeedUnrelatedCreation(int index, int id, {required int revision}) {
    final choice = DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: _today,
      description: null,
      isCompleted: false,
    );
    _commands[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: DailyChoiceCreated(
            choice: choice,
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(id),
                dailyChoiceId: choice.id,
                relationId: _relationId(1),
                previousStepId: null,
              ),
            ]),
            changes: [_UnrelatedChange(_Revision(revision))],
          ),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Cursor implements DailyChoiceCatalogCursor {}

/// Проверяет условия запроса страницы: день, охват выполнения и cursor
/// продолжения; без [cursor] ожидается первая порция.
void _expectQuery(
  DailyChoiceCatalogQuery query, {
  required CalendarDate date,
  bool? isCompleted,
  DailyChoiceCatalogCursor? cursor,
}) {
  expect(query.date, date);
  expect(query.isCompleted, isCompleted);
  expect(query.cursor, cursor == null ? isNull : same(cursor));
}

/// Поздний результат чтения прежней выборки: успешная порция, способная
/// заменить выдачу или потребовать следующего чтения, либо отказ.
final class _LateResult {
  const _LateResult(this.name, {this.failure});

  final String name;
  final DailyChoiceCatalogReadFailure? failure;

  void completeFirst(_Repository repository, int index) => switch (failure) {
    null => repository.first(
      index,
      [_item(7), _item(8)],
      total: 3,
      cursor: _Cursor(),
      revision: 9,
    ),
    final failure => repository.fail(index, failure),
  };

  void completeContinuation(_Repository repository, int index) =>
      switch (failure) {
        null => repository.more(index, [_item(7)], cursor: _Cursor()),
        final failure => repository.fail(index, failure),
      };
}

const _lateResults = [
  _LateResult('успех'),
  _LateResult(
    'временный отказ',
    failure: DailyChoiceCatalogUnavailableFailure(),
  ),
  _LateResult('повреждение', failure: DailyChoiceCatalogCorruptionFailure()),
  _LateResult(
    'неизвестный отказ',
    failure: DailyChoiceCatalogUnexpectedFailure(),
  ),
  _LateResult(
    'устаревший снимок',
    failure: DailyChoiceCatalogSnapshotExpired(),
  ),
];

final class _UnrelatedChange implements GraphChange {
  const _UnrelatedChange(this.revision);
  @override
  final GraphRevision revision;
}

final class _IntentionEntry implements IntentionCatalogEntrySnapshot {
  const _IntentionEntry(this.summary);
  @override
  final IntentionSummary summary;
  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

IntentionSummary _summary(int id, String title) => IntentionSummary(
  id: _intentionId(id),
  title: title,
  hasDescription: false,
  readiness: IntentionReadiness.notReady,
  archiveState: IntentionArchiveState.active,
  activeRelationCount: 0,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
  favoriteMark: FavoriteMark.notFavorite,
);

final class _Revision implements GraphRevision {
  const _Revision(this.value, {this.epoch = 0});
  final int value;
  final int epoch;
  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is! _Revision || epoch != other.epoch
      ? GraphRevisionOrder.differentEpoch
      : value < other.value
      ? GraphRevisionOrder.older
      : value > other.value
      ? GraphRevisionOrder.newer
      : GraphRevisionOrder.same;
}

DailyChoiceCatalogItem _item(int id, {CalendarDate? date}) =>
    DailyChoiceCatalogItem(
      id: _choiceId(id),
      source: DailyChoiceCatalogParticipant(
        id: _intentionId(1),
        title: 'Основание',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.notReady,
      ),
      selected: DailyChoiceCatalogParticipant(
        id: _intentionId(2),
        title: 'Действие',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.ready,
      ),
      date: date ?? _today,
      isCompleted: false,
    );

RelationCounts _counts() => RelationCounts(
  activeNeedIncoming: 0,
  activeNeedOutgoing: 0,
  activeCanIncoming: 0,
  activeCanOutgoing: 0,
  archivedNeedIncoming: 0,
  archivedNeedOutgoing: 0,
  archivedCanIncoming: 0,
  archivedCanOutgoing: 0,
);

IntentionId _intentionId(int value) => switch (IntentionId.decode(
  '018f1200-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  _ => throw StateError('ID'),
};
TagId _tagId() =>
    switch (TagId.decode('018f1400-0000-7000-8000-000000000001')) {
      TagIdDecodingSuccess(:final id) => id,
      InvalidTagIdDecoding() => throw StateError('ID тега'),
    };
LongTermRelationId _relationId(int value) => switch (LongTermRelationId.decode(
  '018f1300-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  _ => throw StateError('ID'),
};
DailyChoiceId _choiceId(int value) => switch (DailyChoiceId.decode(
  '018f1400-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  DailyChoiceIdDecodingSuccess(:final id) => id,
  _ => throw StateError('ID'),
};
ChoicePathStepId _stepId(int value) => switch (ChoicePathStepId.decode(
  '018f1500-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  ChoicePathStepIdDecodingSuccess(:final id) => id,
  _ => throw StateError('ID'),
};
