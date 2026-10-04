import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/operation/operation_state.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_test_support.dart';

void main() {
  test(
    'синхронно принимает одну отправку и не ставит повторную в очередь',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('  Быть здоровым  ')
        ..changeDescription('  Сохранить буквально\n');

      editor.submit();
      editor.submit();

      final state = container.read(provider);
      expect(state.operation, isA<OperationRunning<Intention>>());
      expect(repository.commands, hasLength(1));
      expect(
        repository.commands.single,
        isA<CreateIntention>()
            .having((command) => command.title, 'title', '  Быть здоровым  ')
            .having(
              (command) => command.description,
              'description',
              '  Сохранить буквально\n',
            ),
      );
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await _settle(container);

      expect(repository.commands, hasLength(1));
    },
  );

  test(
    'не принимает повтор той же формы после пересоздания ViewModel',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final firstSubscription = container.listen(provider, (_, _) {});

      container.read(provider.notifier)
        ..changeTitle('Первое намерение')
        ..submit();
      expect(repository.commands, hasLength(1));

      firstSubscription.close();
      await _settle(container);
      final reopenedSubscription = container.listen(provider, (_, _) {});
      addTearDown(reopenedSubscription.close);
      container.read(provider.notifier)
        ..changeTitle('Повтор той же формы')
        ..submit();

      expect(repository.commands, hasLength(1));
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await _settle(container);
    },
  );

  test(
    'независимые формы позволяют создать намерения с одинаковым названием',
    () {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final firstProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final secondProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final firstSubscription = container.listen(firstProvider, (_, _) {});
      final secondSubscription = container.listen(secondProvider, (_, _) {});
      addTearDown(firstSubscription.close);
      addTearDown(secondSubscription.close);

      container.read(firstProvider.notifier)
        ..changeTitle('Одинаковое намерение')
        ..submit();
      container.read(secondProvider.notifier)
        ..changeTitle('Одинаковое намерение')
        ..submit();

      expect(repository.commands, hasLength(2));
      expect(
        repository.commands,
        everyElement(
          isA<CreateIntention>().having(
            (command) => command.title,
            'название',
            'Одинаковое намерение',
          ),
        ),
      );
    },
  );

  test('сохраняет поля и field-specific validation для исправления', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository);
    final provider = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final editor = container.read(provider.notifier)
      ..changeTitle('')
      ..changeDescription('Описание')
      ..submit();

    repository.completeCommand(
      0,
      const ResultFailure(
        IntentionTextInputValidationFailure(
          IntentionTextValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.empty,
          ),
        ),
      ),
    );
    await _settle(container);

    final failed = container.read(provider);
    expect(failed.draft.title, isEmpty);
    expect(failed.draft.description, 'Описание');
    expect(
      failed.operation,
      isA<OperationFailed<Intention>>().having(
        (operation) => operation.failure,
        'failure',
        isA<IntentionTextInputValidationFailure>(),
      ),
    );
    expect(failed.canSubmit, isFalse);

    editor.changeTitle('Исправленное намерение');

    final corrected = container.read(provider);
    expect(corrected.operation, isA<OperationIdle<Intention>>());
    expect(corrected.canSubmit, isTrue);
    expect(corrected.draft.description, 'Описание');
  });

  test(
    'разрешает новый token после unavailable и не оставляет прежний failure',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final tokens = <IntentionOperationToken>[];
      final coordinatorSubscription = container
          .read(graphCommandCoordinatorProvider.notifier)
          .intentionCompletions
          .listen((completion) => tokens.add(completion.token));
      addTearDown(coordinatorSubscription.cancel);
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение')
        ..submit();

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(container);

      expect(container.read(provider).canRetry, isTrue);
      editor.submit();
      expect(repository.commands, hasLength(2));
      expect(
        container.read(provider).operation,
        isA<OperationRunning<Intention>>(),
      );

      repository.completeCommand(1, _savedResult());
      await _settle(container);

      final succeeded = container.read(provider);
      expect(succeeded.operation, isA<OperationSucceeded<Intention>>());
      expect(succeeded.event, isA<IntentionEditorCreated>());
      expect(tokens, hasLength(2));
      expect(identical(tokens.first, tokens.last), isFalse);
    },
  );

  test('публикует claim failure, а renderer передаёт его оболочке', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final presenter = coordinator.registerAppPresentation();
    final provider = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    final subscription = container.listen(provider, (_, _) {});

    container.read(provider.notifier)
      ..changeTitle('Намерение')
      ..submit();
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnexpectedFailure()),
    );
    await _settle(container);

    final failed = container.read(provider);
    expect(failed.operation, isA<OperationFailed<Intention>>());
    expect(failed.failurePresentation, isA<GraphInitiatorPresentationClaim>());
    GraphAppPresentationClaim? fallback;
    final fallbackRequest = presenter.nextClaim()
      ..then((claim) => fallback = claim);
    await _settle(container);
    expect(fallback, isNull);

    coordinator.releaseInitiatorClaim(failed.failurePresentation!);
    await _settle(container);
    await fallbackRequest;

    expect(fallback!.token, same(failed.failurePresentation!.token));
    coordinator.confirmPresentation(failed.failurePresentation!);
    coordinator.confirmPresentation(fallback!);
    subscription.close();
  });

  test(
    'success закрывает форму без initiator claim и сразу доступен оболочке',
    () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      container.read(provider.notifier)
        ..changeTitle('Намерение')
        ..submit();
      repository.completeCommand(0, _savedResult());
      await _settle(container);

      final succeeded = container.read(provider);
      expect(succeeded.event, isA<IntentionEditorCreated>());
      expect(succeeded.failurePresentation, isNull);
      final claim = await presenter.nextClaim();
      expect(
        claim!.completion,
        isA<IntentionCommandCompletion>().having(
          (completion) => completion.result,
          'результат',
          isA<ResultSuccess<IntentionCommandSuccess>>(),
        ),
      );
      coordinator.confirmPresentation(claim);
    },
  );

  test('предъявленный failure не переходит оболочке после успешной повторной попытки', () async {
    final repository = ControlledCatalogRepository();
    final container = _container(repository);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final presenter = coordinator.registerAppPresentation();
    final tokens = <IntentionOperationToken>[];
    final completionSubscription = coordinator.intentionCompletions.listen(
      (completion) => tokens.add(completion.token),
    );
    addTearDown(completionSubscription.cancel);
    final provider = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    final subscription = container.listen(provider, (_, _) {});
    final editor = container.read(provider.notifier)
      ..changeTitle('Намерение')
      ..submit();
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await _settle(container);
    coordinator.confirmPresentation(
      container.read(provider).failurePresentation!,
    );

    editor.submit();
    repository.completeCommand(1, _savedResult());
    await _settle(container);
    subscription.close();
    await _settle(container);

    final success = await presenter.nextClaim();
    expect(tokens, hasLength(2));
    expect(success!.token, same(tokens.last));
    coordinator.confirmPresentation(success);
    GraphAppPresentationClaim? stale;
    unawaited(presenter.nextClaim().then((claim) => stale = claim));
    await _settle(container);
    expect(stale, isNull);
  });

  group('черновик создания', () {
    test('новая сессия начинается с пустого черновика без наследования других открытий и фильтров каталога', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final catalog = container.read(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog())
            .notifier,
      );
      final catalogSubscription = container.listen(
        intentionCatalogViewModelProvider(const BrowseIntentionCatalog()),
        (_, _) {},
      );
      addTearDown(catalogSubscription.close);
      catalog
        ..changeTitleFilter('Дом')
        ..changeTagFilter(IntentionTagFilter(requiredTagIds: [_tagId(1)]));
      final previousProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final previousSubscription = container.listen(
        previousProvider,
        (_, _) {},
      );
      container.read(previousProvider.notifier)
        ..changeTitle('Прежний черновик')
        ..changeDescription('Прежнее описание')
        ..markFavorite()
        ..confirmReadiness()
        ..draftTagSet.add(_tag(1, 'Дом'));
      previousSubscription.close();
      await _deliverEvents(container);

      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      final state = container.read(provider);
      expect(state.draft.title, isEmpty);
      expect(state.draft.description, isEmpty);
      expect(state.draft.tagIds, isEmpty);
      expect(state.draft.readiness, IntentionReadiness.notReady);
      expect(state.draft.favoriteMark, FavoriteMark.notFavorite);
      expect(state.draft.isChanged, isFalse);
      expect(state.selectedTagNames, isEmpty);
      expect(state.operation, isA<OperationIdle<Intention>>());
      expect(
        container.read(provider.notifier).draftTagSet.current.tagIds,
        isEmpty,
      );
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('каждое из пяти полей отдельно делает черновик изменённым, а возврат к началу снимает изменённость', () {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier);
      bool isChanged() => container.read(provider).draft.isChanged;

      final edits = <String, (void Function(), void Function())>{
        'название': (
          () => editor.changeTitle('Намерение'),
          () => editor.changeTitle(''),
        ),
        'описание': (
          () => editor.changeDescription('Описание'),
          () => editor.changeDescription(''),
        ),
        'набор тегов': (
          () => editor.draftTagSet.add(_tag(1, 'Дом')),
          () => editor.removeTag(_tagId(1)),
        ),
        'готовность': (editor.confirmReadiness, editor.disableReadiness),
        'избранное': (editor.markFavorite, editor.unmarkFavorite),
      };
      for (final MapEntry(key: field, value: (change, revert))
          in edits.entries) {
        change();
        expect(isChanged(), isTrue, reason: field);
        revert();
        expect(isChanged(), isFalse, reason: field);
      }

      expect(container.read(provider).draft.tagIds, isEmpty);
      expect(container.read(provider).selectedTagNames, isEmpty);
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test(
      'сохраняет полностью пробельные строки сырыми и считает их изменением',
      () {
        final repository = ControlledCatalogRepository();
        final container = _container(repository);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        final editor = container.read(provider.notifier)..changeTitle('   ');

        expect(container.read(provider).draft.title, '   ');
        expect(container.read(provider).draft.isChanged, isTrue);

        editor
          ..changeTitle('')
          ..changeDescription('\n\t ');

        expect(container.read(provider).draft.description, '\n\t ');
        expect(container.read(provider).draft.isChanged, isTrue);
      },
    );

    test('явное добавление через контракт набора меняет только черновик и сохраняет последнее известное название', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final completions = <GraphCommandCompletion>[];
      final completionSubscription = container
          .read(graphCommandCoordinatorProvider.notifier)
          .completions
          .listen(completions.add);
      addTearDown(completionSubscription.cancel);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final tagSet = container.read(provider.notifier).draftTagSet;
      final published = <IntentionDraftTagSetSnapshot>[];
      final changesSubscription = tagSet.changes.listen(published.add);
      addTearDown(changesSubscription.cancel);

      final first = tagSet.add(_tag(1, 'Дом'));
      final second = tagSet.add(_tag(2, 'Выходные'));
      await _deliverEvents(container);

      expect(first, IntentionDraftTagAddition.added);
      expect(second, IntentionDraftTagAddition.added);
      final state = container.read(provider);
      expect(state.draft.tagIds, [_tagId(1), _tagId(2)]);
      expect(
        state.selectedTagNames.map((id, name) => MapEntry(id, name.value)),
        {_tagId(1): 'Дом', _tagId(2): 'Выходные'},
      );
      expect(tagSet.current.tagIds, [_tagId(1), _tagId(2)]);
      expect(tagSet.current.availability, IntentionDraftAvailability.editable);
      expect(published.map((snapshot) => snapshot.tagIds), [
        [_tagId(1)],
        [_tagId(1), _tagId(2)],
      ]);
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
      expect(completions, isEmpty);
    });

    test('повторное добавление включённого тега идемпотентно и не публикует изменение', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final tagSet = container.read(provider.notifier).draftTagSet
        ..add(_tag(1, 'Дом'));
      await _deliverEvents(container);
      final before = container.read(provider);
      final published = <IntentionDraftTagSetSnapshot>[];
      final changesSubscription = tagSet.changes.listen(published.add);
      addTearDown(changesSubscription.cancel);

      final repeated = tagSet.add(_tag(1, 'Дом'));
      await _deliverEvents(container);

      expect(repeated, IntentionDraftTagAddition.alreadyIncluded);
      expect(container.read(provider), same(before));
      expect(tagSet.current.tagIds, [_tagId(1)]);
      expect(published, isEmpty);
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test(
      'опубликованные наборы неизменяемы и не меняются последующими правками',
      () {
        final repository = ControlledCatalogRepository();
        final container = _container(repository);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        final editor = container.read(provider.notifier);
        final tagSet = editor.draftTagSet..add(_tag(1, 'Дом'));
        final stateTags = container.read(provider).draft.tagIds;
        final contractTags = tagSet.current.tagIds;
        final names = container.read(provider).selectedTagNames;

        expect(() => stateTags.add(_tagId(2)), throwsUnsupportedError);
        expect(() => contractTags.add(_tagId(2)), throwsUnsupportedError);
        expect(
          () => names[_tagId(2)] = TagName.fromInput('Чужой'),
          throwsUnsupportedError,
        );

        tagSet.add(_tag(2, 'Выходные'));
        editor.removeTag(_tagId(1));

        expect(stateTags, [_tagId(1)]);
        expect(contractTags, [_tagId(1)]);
        expect(names.keys, [_tagId(1)]);
        expect(container.read(provider).draft.tagIds, [_tagId(2)]);
        expect(container.read(provider).selectedTagNames.keys, [_tagId(2)]);
      },
    );

    test('снятие тега и обе отметки меняют только черновик', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier);
      final tagSet = editor.draftTagSet;
      final published = <IntentionDraftTagSetSnapshot>[];
      final changesSubscription = tagSet.changes.listen(published.add);
      addTearDown(changesSubscription.cancel);

      tagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Выходные'));
      editor
        ..removeTag(_tagId(1))
        ..removeTag(_tagId(3))
        ..markFavorite()
        ..confirmReadiness();
      await _deliverEvents(container);

      final state = container.read(provider);
      expect(state.draft.tagIds, [_tagId(2)]);
      expect(state.selectedTagNames.keys, [_tagId(2)]);
      expect(state.draft.favoriteMark, FavoriteMark.favorite);
      expect(state.draft.readiness, IntentionReadiness.ready);
      expect(state.operation, isA<OperationIdle<Intention>>());
      expect(published.map((snapshot) => snapshot.tagIds), [
        [_tagId(1)],
        [_tagId(1), _tagId(2)],
        [_tagId(2)],
      ]);

      editor
        ..unmarkFavorite()
        ..disableReadiness();

      expect(
        container.read(provider).draft.favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(
        container.read(provider).draft.readiness,
        IntentionReadiness.notReady,
      );
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('готовность не выводится из других полей и включается только явным подтверждением', () {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Купить хлеб сегодня')
        ..changeDescription('Понятное однодневное действие')
        ..markFavorite()
        ..draftTagSet.add(_tag(1, 'Дела'));

      expect(
        container.read(provider).draft.readiness,
        IntentionReadiness.notReady,
      );

      editor.confirmReadiness();

      expect(
        container.read(provider).draft.readiness,
        IntentionReadiness.ready,
      );
      expect(repository.commands, isEmpty);
    });

    test('разные сессии не обмениваются черновиками и наборами', () {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final firstProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final secondProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final firstSubscription = container.listen(firstProvider, (_, _) {});
      final secondSubscription = container.listen(secondProvider, (_, _) {});
      addTearDown(firstSubscription.close);
      addTearDown(secondSubscription.close);

      container.read(firstProvider.notifier)
        ..changeTitle('Первое')
        ..markFavorite()
        ..confirmReadiness()
        ..draftTagSet.add(_tag(1, 'Дом'));
      container
          .read(secondProvider.notifier)
          .draftTagSet
          .add(_tag(2, 'Выходные'));

      final first = container.read(firstProvider);
      final second = container.read(secondProvider);
      expect(first.draft.tagIds, [_tagId(1)]);
      expect(second.draft.tagIds, [_tagId(2)]);
      expect(second.draft.title, isEmpty);
      expect(second.draft.favoriteMark, FavoriteMark.notFavorite);
      expect(second.draft.readiness, IntentionReadiness.notReady);
      expect(
        container.read(secondProvider.notifier).draftTagSet.current.tagIds,
        [_tagId(2)],
      );
    });

    test(
      'освобождённая сессия закрывает наблюдаемый набор и отвергает добавление',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _container(repository);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        final subscription = container.listen(provider, (_, _) {});
        final tagSet = container.read(provider.notifier).draftTagSet
          ..add(_tag(1, 'Дом'));
        final published = <IntentionDraftTagSetSnapshot>[];
        var isDone = false;
        final changesSubscription = tagSet.changes.listen(
          published.add,
          onDone: () => isDone = true,
        );
        addTearDown(changesSubscription.cancel);
        await _deliverEvents(container);

        subscription.close();
        await _deliverEvents(container);

        expect(isDone, isTrue);
        expect(published.last.availability, IntentionDraftAvailability.closed);
        expect(tagSet.current.availability, IntentionDraftAvailability.closed);
        expect(tagSet.current.tagIds, [_tagId(1)]);
        expect(
          tagSet.add(_tag(2, 'Выходные')),
          IntentionDraftTagAddition.sessionClosed,
        );
        expect(tagSet.current.tagIds, [_tagId(1)]);
        expect(repository.commands, isEmpty);
        expect(repository.tagCommands, isEmpty);
      },
    );

    test(
      'завершённая успешным созданием сессия отвергает правки черновика',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _container(repository);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        final editor = container.read(provider.notifier)
          ..changeTitle('Намерение')
          ..submit();
        final published = <IntentionDraftTagSetSnapshot>[];
        var isDone = false;
        final changesSubscription = editor.draftTagSet.changes.listen(
          published.add,
          onDone: () => isDone = true,
        );
        addTearDown(changesSubscription.cancel);
        repository.completeCommand(0, _savedResult());
        await _deliverEvents(container);
        final completed = container.read(provider);
        expect(completed.operation, isA<OperationSucceeded<Intention>>());
        expect(published.map((snapshot) => snapshot.availability), [
          IntentionDraftAvailability.closed,
        ]);
        expect(isDone, isTrue);

        final addition = editor.draftTagSet.add(_tag(1, 'Дом'));
        editor
          ..changeTitle('Поздняя правка')
          ..changeDescription('Поздняя правка')
          ..markFavorite()
          ..confirmReadiness()
          ..removeTag(_tagId(1));

        expect(addition, IntentionDraftTagAddition.sessionClosed);
        expect(container.read(provider), same(completed));
        expect(container.read(provider).draft.title, 'Намерение');
        expect(
          editor.draftTagSet.current.availability,
          IntentionDraftAvailability.closed,
        );
        expect(repository.commands, hasLength(1));
      },
    );
  });
}

ProviderContainer _container(ControlledCatalogRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle(ProviderContainer container) async {
  await container.pump();
  await container.pump();
}

/// Доставляет асинхронные события наблюдаемого набора после правок сессии.
Future<void> _deliverEvents(ProviderContainer container) async {
  await _settle(container);
  await Future<void>.delayed(Duration.zero);
}

Result<IntentionCommandSuccess> _savedResult() {
  final intention = testIntention(title: 'Намерение');
  return ResultSuccess(
    IntentionSaved(
      intention,
      catalogMutation: IntentionCatalogCreated(
        revision: const TestCatalogRevision(1),
        entry: TestCatalogEntrySnapshot(
          IntentionSummary(
            id: intention.id,
            title: intention.title,
            hasDescription: intention.description != null,
            readiness: intention.readiness,
            archiveState: intention.archiveState,
            activeRelationCount: 0,
            createdAt: intention.createdAt,
            updatedAt: intention.updatedAt,
            favoriteMark: FavoriteMark.notFavorite,
          ),
        ),
      ),
    ),
  );
}

TagId _tagId(int number) => switch (TagId.decode(
  '018f47c2-6b7d-7abc-8def-${number.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный UUID тега.'),
};

Tag _tag(int number, String name) =>
    Tag(id: _tagId(number), name: TagName.fromInput(name));
