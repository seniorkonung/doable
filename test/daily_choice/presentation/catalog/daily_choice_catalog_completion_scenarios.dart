part of 'daily_choice_catalog_view_model_test.dart';

void _completionScenarios() {
  test('выполнение меняет только одно поле и ждёт обе секции до следующего нажатия', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _pair(h, incomplete: [_item(1), _item(2)]);

    h.model.changeCompletion(_choiceId(1), true);
    final command = h.repository.commands.single as UpdateDailyChoiceFields;
    expect(command.choiceId, _choiceId(1));
    expect(
      command.patch.isCompleted,
      isA<DailyChoiceFieldSet<bool>>().having(
        (patch) => patch.value,
        'целевое выполнение',
        true,
      ),
    );
    expect(command.patch.date, isA<DailyChoiceFieldUnchanged<CalendarDate>>());
    expect(
      command.patch.schedule,
      isA<DailyChoiceFieldUnchanged<DailyChoiceSchedule>>(),
    );
    expect(
      command.patch.priority,
      isA<DailyChoiceFieldUnchanged<DailyChoicePriority>>(),
    );
    expect(command.patch.description, isA<DailyChoiceDescriptionUnchanged>());
    expect(
      h.state.completionOperations[_choiceId(1)],
      isA<DailyChoiceCompletionSubmitting>(),
    );
    expect(h.state.canChangeCompletion(_choiceId(1)), isFalse);
    expect(h.state.canChangeCompletion(_choiceId(2)), isTrue);
    expect(_loaded(h).incomplete.items.first.isCompleted, isFalse);
    h.model.changeCompletion(_choiceId(1), true);
    expect(h.repository.commands, hasLength(1));

    h.repository.succeedCompletionUpdate(0, 1, revision: 2);
    await pumpEventQueue();
    expect(
      h.state.completionOperations[_choiceId(1)],
      isA<DailyChoiceCompletionAwaitingSnapshot>(),
    );
    h.model.changeCompletion(_choiceId(1), true);
    expect(h.repository.commands, hasLength(1));
    h.repository.first(2, [_item(2)], total: 1, revision: 2);
    await pumpEventQueue();
    expect(_loaded(h).incomplete.items.first.isCompleted, isFalse);
    expect(h.state.canChangeCompletion(_choiceId(1)), isFalse);
    h.repository.first(3, [_item(1, completed: true)], total: 1, revision: 2);
    await pumpEventQueue();
    expect(h.state.completionOperations, isEmpty);
    expect(_loaded(h).completed.items.single.isCompleted, isTrue);
    expect(h.state.canChangeCompletion(_choiceId(1)), isTrue);

    h.model.changeCompletion(_choiceId(1), false);
    expect(
      (h.repository.commands.last as UpdateDailyChoiceFields).patch.isCompleted,
      isA<DailyChoiceFieldSet<bool>>().having(
        (patch) => patch.value,
        'снятие выполнения',
        false,
      ),
    );
    h.repository.succeedCompletionUpdate(1, 1, revision: 3, completed: false);
    await pumpEventQueue();
    await _pair(h, index: 4, incomplete: [_item(1), _item(2)], revision: 3);
    expect(h.state.completionOperations, isEmpty);
    expect(_loaded(h).completed.items, isEmpty);
    expect(_loaded(h).incomplete.items.first.isCompleted, isFalse);
  });

  test('отказ перечитывания сохраняет блокировку до актуальной пары без перенесённой строки', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _pair(h, incomplete: [_item(1)]);
    h.model.changeCompletion(_choiceId(1), true);
    h.repository.succeedCompletionUpdate(0, 1, revision: 2);
    await pumpEventQueue();
    h.repository.fail(2, const DailyChoiceCatalogUnavailableFailure());
    await pumpEventQueue();
    expect(
      _loaded(h).refreshFailure,
      isA<DailyChoiceCatalogUnavailableFailure>(),
    );
    expect(
      h.state.completionOperations[_choiceId(1)],
      isA<DailyChoiceCompletionAwaitingSnapshot>(),
    );
    h.model.changeCompletion(_choiceId(1), true);
    expect(h.repository.commands, hasLength(1));

    final retry = h.model.retryRefresh();
    await _pair(h, index: 3, incomplete: [_item(1)]);
    expect(_loaded(h).incomplete.items.single.isCompleted, isFalse);
    expect(h.state.canChangeCompletion(_choiceId(1)), isFalse);
    h.repository.first(5, [], total: 0, revision: 2);
    await pumpEventQueue();
    h.repository.first(
      6,
      [_item(2, completed: true)],
      total: 2,
      cursor: _Cursor(),
      revision: 2,
    );
    await retry;
    expect(h.state.completionOperations, isEmpty);
    expect(_loaded(h).items.any((item) => item.id == _choiceId(1)), isFalse);
    final more = h.model.loadMore(isCompleted: true);
    h.repository.more(7, [_item(1, completed: true)], revision: 2);
    await more;
    expect(h.state.canChangeCompletion(_choiceId(1)), isTrue);
    expect(h.repository.commands, hasLength(1));
  });

  for (final failure in const [
    DailyChoiceUnavailableFailure(),
    DailyChoiceConflictFailure(DailyChoiceConflictReason.dependencyChanged),
    DailyChoiceCorruptionFailure(),
    DailyChoiceUnexpectedFailure(),
  ]) {
    test(
      'отказ выполнения ${failure.runtimeType} сохраняет данные и определяет допустимое действие',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await _pair(h, incomplete: [_item(1)]);
        final session = DailyChoiceCompletionSession(isCurrent: () => true);
        h.model.changeCompletion(_choiceId(1), true, session: session);
        h.repository.failCommand(0, failure);
        await pumpEventQueue();
        final failed =
            h.state.completionOperations[_choiceId(1)]
                as DailyChoiceCompletionFailed;
        expect(failed.failure, same(failure));
        expect(failed.inline?.session, same(session));
        expect(failed.inline?.claim, isNotNull);
        expect(failed.canRetry, failure is DailyChoiceUnavailableFailure);
        expect(failed.requiresRefresh, failure is DailyChoiceConflictFailure);
        expect(_loaded(h).incomplete.items.single.isCompleted, isFalse);
        expect(_loaded(h).completed.items, isEmpty);
        expect(h.repository.queries, hasLength(2));
        h.model.changeCompletion(_choiceId(1), true);
        if (failure is DailyChoiceUnavailableFailure) {
          expect(h.repository.commands, hasLength(2));
          expect(
            h.state.completionOperations[_choiceId(1)],
            isA<DailyChoiceCompletionSubmitting>(),
          );
          h.repository.succeedCompletionUpdate(1, 1, revision: 2);
          await pumpEventQueue();
          await _pair(
            h,
            index: 2,
            completed: [_item(1, completed: true)],
            revision: 2,
          );
          expect(h.state.completionOperations, isEmpty);
        } else {
          expect(h.repository.commands, hasLength(1));
        }
        if (failure is DailyChoiceConflictFailure) {
          final failedRefresh = h.model.refreshCompletion(_choiceId(1));
          h.repository.fail(2, const DailyChoiceCatalogUnavailableFailure());
          await failedRefresh;
          expect(h.state.canChangeCompletion(_choiceId(1)), isFalse);
          final refresh = h.model.refreshCompletion(_choiceId(1));
          await _pair(h, index: 3, incomplete: [_item(1)], revision: 2);
          await refresh;
          expect(h.state.canChangeCompletion(_choiceId(1)), isTrue);
          expect(h.repository.commands, hasLength(1));
          h.model.changeCompletion(_choiceId(1), true);
          expect(h.repository.commands, hasLength(2));
        }
      },
    );
  }

  test('другой экземпляр каталога не обходит занятый ключ выбора', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _pair(h, incomplete: [_item(1)]);
    final otherProvider = dailyChoiceCatalogViewModelProvider(
      DailyChoiceCatalogInstance(initialDate: _today),
    );
    final subscription = h.container.listen(otherProvider, (_, _) {});
    addTearDown(subscription.close);
    await _pair(h, index: 2, incomplete: [_item(1)]);
    final otherModel = h.container.read(otherProvider.notifier);
    h.model.changeCompletion(_choiceId(1), true);
    otherModel.changeCompletion(_choiceId(1), true);
    expect(h.repository.commands, hasLength(1));
    expect(
      h.state.completionOperations[_choiceId(1)],
      isA<DailyChoiceCompletionSubmitting>(),
    );
    final rejected =
        h.container.read(otherProvider).completionOperations[_choiceId(1)]
            as DailyChoiceCompletionFailed;
    expect(rejected.failure, isA<DailyChoiceConflictFailure>());
    expect(rejected.requiresRefresh, isTrue);
    expect(rejected.inline, isNull);
    h.repository.failCommand(0, const DailyChoiceUnavailableFailure());
    await pumpEventQueue();
  });

  test('отказ сборки не теряет результат другой операции, завершившейся во время чтения', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _pair(h, incomplete: [_item(1), _item(2)]);
    h.model.changeCompletion(_choiceId(1), true);
    h.model.changeCompletion(_choiceId(2), true);
    h.repository.succeedCompletionUpdate(0, 1, revision: 2);
    await pumpEventQueue();
    h.repository.failCommand(1, const DailyChoiceUnavailableFailure());
    await pumpEventQueue();
    h.repository.fail(2, const DailyChoiceCatalogUnavailableFailure());
    await pumpEventQueue();
    expect(
      h.state.completionOperations[_choiceId(1)],
      isA<DailyChoiceCompletionAwaitingSnapshot>(),
    );
    expect(
      h.state.completionOperations[_choiceId(2)],
      isA<DailyChoiceCompletionFailed>(),
    );
    expect(h.state.canChangeCompletion(_choiceId(1)), isFalse);
    expect(h.state.canChangeCompletion(_choiceId(2)), isTrue);

    final refresh = h.model.retryRefresh();
    await _pair(
      h,
      index: 3,
      incomplete: [_item(2)],
      completed: [_item(1, completed: true)],
      revision: 2,
    );
    await refresh;
    expect(h.state.completionOperations[_choiceId(1)], isNull);
    expect(
      h.state.completionOperations[_choiceId(2)],
      isA<DailyChoiceCompletionFailed>(),
    );
    expect(h.repository.commands, hasLength(2));
  });
}
