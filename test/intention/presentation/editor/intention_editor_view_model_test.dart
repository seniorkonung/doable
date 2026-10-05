import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
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
import 'package:doable/src/tag/application/tag_read_result.dart';
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
      expect(state.selectedTags, isEmpty);
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
      expect(container.read(provider).selectedTags, isEmpty);
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
      expect(_tagNames(state), {_tagId(1): 'Дом', _tagId(2): 'Выходные'});
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
        final names = container.read(provider).selectedTags;

        expect(() => stateTags.add(_tagId(2)), throwsUnsupportedError);
        expect(() => contractTags.add(_tagId(2)), throwsUnsupportedError);
        expect(() => names.remove(_tagId(1)), throwsUnsupportedError);

        tagSet.add(_tag(2, 'Выходные'));
        editor.removeTag(_tagId(1));

        expect(stateTags, [_tagId(1)]);
        expect(contractTags, [_tagId(1)]);
        expect(names.keys, [_tagId(1)]);
        expect(container.read(provider).draft.tagIds, [_tagId(2)]);
        expect(container.read(provider).selectedTags.keys, [_tagId(2)]);
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
      expect(state.selectedTags.keys, [_tagId(2)]);
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

  group('отправка черновика', () {
    test('передаёт координатору по ключу сессии одну команду со всеми пятью полями черновика', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('  Быть здоровым  ')
        ..changeDescription('  Описание буквально\n')
        ..markFavorite()
        ..confirmReadiness();
      editor.draftTagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Выходные'));

      editor.submit();

      expect(repository.commands, [
        isA<CreateIntention>()
            .having((command) => command.title, 'название', '  Быть здоровым  ')
            .having(
              (command) => command.description,
              'описание',
              '  Описание буквально\n',
            )
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
            .having((command) => command.tagIds, 'теги', {
              _tagId(1),
              _tagId(2),
            }),
      ]);
      expect(coordinator.isKeyRunning(formKey), isTrue);
      expect(
        container.read(provider).operation,
        isA<OperationRunning<Intention>>(),
      );
      expect(repository.tagCommands, isEmpty);

      repository.completeCommand(0, _savedResult());
      await _settle(container);
    });

    test(
      'минимальный черновик отправляется без описания, тегов и обеих отметок',
      () async {
        final repository = ControlledCatalogRepository();
        final container = _container(repository);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);

        container.read(provider.notifier)
          ..changeTitle('Намерение')
          ..submit();

        expect(repository.commands, [
          isA<CreateIntention>()
              .having((command) => command.title, 'название', 'Намерение')
              .having((command) => command.description, 'описание', isNull)
              .having(
                (command) => command.readiness,
                'готовность',
                IntentionReadiness.notReady,
              )
              .having(
                (command) => command.favoriteMark,
                'избранное',
                FavoriteMark.notFavorite,
              )
              .having((command) => command.tagIds, 'теги', isEmpty),
        ]);

        repository.completeCommand(0, _savedResult());
        await _settle(container);
      },
    );

    test('до результата отвергает все правки, запоздалое добавление общего выбора и повторную отправку, сохраняя состав принятой команды', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Название')
        ..changeDescription('Описание')
        ..markFavorite()
        ..confirmReadiness();
      // Общий выбор получил контракт набора до отправки и вызывает его позже.
      final tagSet = editor.draftTagSet..add(_tag(1, 'Дом'));
      await _deliverEvents(container);
      final published = <IntentionDraftTagSetSnapshot>[];
      final changesSubscription = tagSet.changes.listen(published.add);
      addTearDown(changesSubscription.cancel);

      editor.submit();
      final submitted = container.read(provider);
      final command = repository.commands.single as CreateIntention;

      final lateAddition = tagSet.add(_tag(2, 'Выходные'));
      editor
        ..changeTitle('Правка во время отправки')
        ..changeDescription('Правка во время отправки')
        ..removeTag(_tagId(1))
        ..unmarkFavorite()
        ..disableReadiness()
        ..submit();
      await _deliverEvents(container);

      expect(lateAddition, IntentionDraftTagAddition.submitting);
      expect(container.read(provider), same(submitted));
      expect(submitted.draft.title, 'Название');
      expect(submitted.draft.description, 'Описание');
      expect(submitted.draft.tagIds, [_tagId(1)]);
      expect(submitted.draft.readiness, IntentionReadiness.ready);
      expect(submitted.draft.favoriteMark, FavoriteMark.favorite);
      expect(
        submitted.draftAvailability,
        IntentionDraftAvailability.submitting,
      );
      expect(tagSet.current.tagIds, [_tagId(1)]);
      expect(
        tagSet.current.availability,
        IntentionDraftAvailability.submitting,
      );
      expect(published.map((snapshot) => snapshot.availability), [
        IntentionDraftAvailability.submitting,
      ]);
      expect(repository.commands, [same(command)]);
      expect(command.title, 'Название');
      expect(command.description, 'Описание');
      expect(command.tagIds, {_tagId(1)});
      expect(command.readiness, IntentionReadiness.ready);
      expect(command.favoriteMark, FavoriteMark.favorite);
      expect(repository.tagCommands, isEmpty);

      // Результат снимает фиксацию черновика, но не меняет принятую команду.
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _deliverEvents(container);

      expect(tagSet.current.availability, IntentionDraftAvailability.editable);
      expect(published.last.availability, IntentionDraftAvailability.editable);
      expect(tagSet.add(_tag(2, 'Выходные')), IntentionDraftTagAddition.added);
      editor.unmarkFavorite();
      expect(container.read(provider).draft.tagIds, [_tagId(1), _tagId(2)]);
      expect(
        container.read(provider).draft.favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(command.tagIds, {_tagId(1)});
      expect(command.favoriteMark, FavoriteMark.favorite);
      expect(repository.commands, hasLength(1));
    });

    test('успех публикует событие завершения только своей сессии и только один раз', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final otherProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final events = <IntentionEditorEvent>[];
      final subscription = container.listen(provider, (previous, next) {
        final event = next.event;
        if (event != null && previous?.event == null) {
          events.add(event);
        }
      });
      addTearDown(subscription.close);
      final otherSubscription = container.listen(otherProvider, (_, _) {});
      addTearDown(otherSubscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение')
        ..markFavorite()
        ..submit();

      repository.completeCommand(0, _savedResult());
      await _deliverEvents(container);
      editor
        ..consumeEvent()
        ..submit()
        ..changeTitle('После успеха');
      await _deliverEvents(container);

      expect(events, [isA<IntentionEditorCreated>()]);
      expect(container.read(provider).event, isNull);
      expect(
        container.read(provider).operation,
        isA<OperationSucceeded<Intention>>(),
      );
      expect(container.read(otherProvider).event, isNull);
      expect(
        container.read(otherProvider).operation,
        isA<OperationIdle<Intention>>(),
      );
      expect(repository.commands, hasLength(1));
    });

    test('освобождение инициатора не отменяет принятую отправку полного черновика и не снимает её ограничение до результата', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final firstSubscription = container.listen(provider, (_, _) {});
      final editor = container.read(provider.notifier)
        ..changeTitle('Полное намерение')
        ..markFavorite()
        ..confirmReadiness();
      editor.draftTagSet.add(_tag(1, 'Дом'));
      editor.submit();
      final command = repository.commands.single;

      firstSubscription.close();
      await _deliverEvents(container);

      expect(coordinator.isKeyRunning(formKey), isTrue);
      final reopenedSubscription = container.listen(provider, (_, _) {});
      addTearDown(reopenedSubscription.close);
      container.read(provider.notifier)
        ..changeTitle('Повтор той же сессии')
        ..submit();
      expect(repository.commands, [same(command)]);
      expect(
        command,
        isA<CreateIntention>()
            .having((command) => command.title, 'название', 'Полное намерение')
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
            .having((command) => command.tagIds, 'теги', {_tagId(1)}),
      );

      repository.completeCommand(0, _savedResult());
      await _settle(container);

      final claim = await presenter.nextClaim();
      expect(
        claim!.completion,
        isA<IntentionCommandCompletion>().having(
          (completion) => completion.result,
          'результат',
          isA<ResultSuccess<IntentionCommandSuccess>>(),
        ),
      );
      expect(coordinator.isKeyRunning(formKey), isFalse);
      expect(container.read(provider).event, isNull);
      coordinator.confirmPresentation(claim);
      expect(repository.commands, hasLength(1));
    });
  });

  group('восстановление после отказа', () {
    test(
      'любой отказ сохраняет весь сырой черновик без нормализации и сброса',
      () async {
        for (final (name, failure) in _failureCases()) {
          final session = await _failedFullDraftSession(failure);
          final failed = session.state;

          expect(failed.draft.title, _rawTitle, reason: name);
          expect(failed.draft.description, _rawDescription, reason: name);
          expect(failed.draft.tagIds, [_tagId(1), _tagId(2)], reason: name);
          expect(
            failed.draft.readiness,
            IntentionReadiness.ready,
            reason: name,
          );
          expect(
            failed.draft.favoriteMark,
            FavoriteMark.favorite,
            reason: name,
          );
          expect(_tagNames(failed), {
            _tagId(1): 'Дом',
            _tagId(2): 'Выходные',
          }, reason: name);
          expect(
            failed.operation,
            isA<OperationFailed<Intention>>().having(
              (operation) => operation.failure,
              'отказ',
              same(failure),
            ),
            reason: name,
          );
          expect(
            failed.draftAvailability,
            IntentionDraftAvailability.editable,
            reason: name,
          );
          expect(session.editor.draftTagSet.current.tagIds, [
            _tagId(1),
            _tagId(2),
          ], reason: name);
          expect(failed.failurePresentation, isNotNull, reason: name);
          expect(session.repository.commands, hasLength(1), reason: name);
          expect(session.repository.tagCommands, isEmpty, reason: name);
        }
      },
    );

    test('правка снимает отказ только по его типизированной причине и не отправляет черновик сама', () async {
      final edits = <String, void Function(IntentionEditorViewModel)>{
        'название': (editor) => editor.changeTitle('Исправленное название'),
        'описание': (editor) => editor.changeDescription('Исправленное'),
        'добавление нового тега': (editor) =>
            editor.draftTagSet.add(_tag(3, 'Спорт')),
        'повторное добавление включённого тега с новым названием': (editor) =>
            editor.draftTagSet.add(_tag(1, 'Быт')),
        'снятие доступного тега': (editor) => editor.removeTag(_tagId(2)),
        'снятие отсутствующего тега': (editor) => editor.removeTag(_tagId(1)),
        'избранное': (editor) => editor.unmarkFavorite(),
        'готовность': (editor) => editor.disableReadiness(),
      };
      _Recovery expected(IntentionFailure failure, String edit) =>
          switch (failure) {
            IntentionTextInputValidationFailure(:final textFailure) => switch ((
              textFailure.field,
              edit,
            )) {
              (IntentionTextField.title, 'название') ||
              (
                IntentionTextField.description,
                'описание',
              ) => _Recovery.correctable,
              _ => _Recovery.blocked,
            },
            IntentionGenericValidationFailure() =>
              edit == 'название' || edit == 'описание'
                  ? _Recovery.correctable
                  : _Recovery.blocked,
            IntentionCreationTagsMissingFailure() =>
              edit == 'снятие отсутствующего тега'
                  ? _Recovery.correctable
                  : _Recovery.blocked,
            IntentionUnavailableFailure() => _Recovery.retryable,
            IntentionNotFoundFailure() ||
            IntentionConflictFailure() ||
            IntentionHasBlockingRelationsFailure() ||
            IntentionCorruptionFailure() ||
            IntentionUnexpectedFailure() => _Recovery.blocked,
          };

      for (final (name, failure) in _failureCases()) {
        for (final MapEntry(key: edit, value: apply) in edits.entries) {
          final reason = '$name × $edit';
          final session = await _failedFullDraftSession(failure);
          final surface = _AppSurface(session.coordinator);
          final failed = session.state;
          final claim = failed.failurePresentation!;

          apply(session.editor);
          await _deliverEvents(session.container);

          final edited = session.state;
          switch (expected(failure, edit)) {
            case _Recovery.correctable:
              expect(
                edited.operation,
                isA<OperationIdle<Intention>>(),
                reason: reason,
              );
              expect(edited.canSubmit, isTrue, reason: reason);
              expect(edited.failurePresentation, isNull, reason: reason);
              // Снятый отказ сессия больше не публикует: его неподтверждённое
              // право переходит общей поверхности.
              expect(
                session.coordinator.claimInitiatorFailure(claim.token),
                isNull,
                reason: reason,
              );
              expect(surface.tokens, [same(claim.token)], reason: reason);
            case _Recovery.retryable:
              expect(edited.operation, same(failed.operation), reason: reason);
              expect(edited.canRetry, isTrue, reason: reason);
              expect(edited.canSubmit, isTrue, reason: reason);
              _expectClaimKeptByForm(session, surface, claim, reason: reason);
            case _Recovery.blocked:
              expect(edited.operation, same(failed.operation), reason: reason);
              expect(edited.canRetry, isFalse, reason: reason);
              expect(edited.canSubmit, isFalse, reason: reason);
              _expectClaimKeptByForm(session, surface, claim, reason: reason);
          }
          expect(session.repository.commands, hasLength(1), reason: reason);
          expect(session.repository.tagCommands, isEmpty, reason: reason);
        }
      }
    });

    test('отказ отсутствующих тегов сохраняет точные идентификаторы и разрешает новую проверку только после явного снятия каждого из них', () async {
      final missing = IntentionCreationTagsMissingFailure([
        _tagId(1),
        _tagId(3),
      ]);
      final session = await _failedFullDraftSession(
        missing,
        tags: [_tag(1, 'Дом'), _tag(2, 'Выходные'), _tag(3, 'Спорт')],
      );
      final editor = session.editor;
      final claim = session.state.failurePresentation;
      expect(session.state.missingTagIds, {_tagId(1), _tagId(3)});

      // Одноимённый новый тег не заменяет отсутствующий.
      expect(
        editor.draftTagSet.add(_tag(4, 'Дом')),
        IntentionDraftTagAddition.added,
      );
      expect(
        editor.draftTagSet.add(_tag(1, 'Быт')),
        IntentionDraftTagAddition.alreadyIncluded,
      );
      editor
        ..removeTag(_tagId(2))
        ..changeTitle('Другое название')
        ..unmarkFavorite();
      await _deliverEvents(session.container);

      expect(session.state.draft.tagIds, [_tagId(1), _tagId(3), _tagId(4)]);
      expect(session.state.canSubmit, isFalse);
      expect(session.state.missingTagIds, {_tagId(1), _tagId(3)});
      expect(session.state.failurePresentation, same(claim));

      editor.removeTag(_tagId(1));
      await _deliverEvents(session.container);

      expect(session.state.canSubmit, isFalse);
      expect(session.state.missingTagIds, {_tagId(3)});
      expect(
        session.state.operation,
        isA<OperationFailed<Intention>>().having(
          (operation) => operation.failure,
          'отказ',
          isA<IntentionCreationTagsMissingFailure>()
              .having((failure) => failure, 'тот же отказ', same(missing))
              .having(
                (failure) => failure.missingTagIds,
                'точные отсутствующие теги',
                {_tagId(1), _tagId(3)},
              ),
        ),
      );
      editor.submit();
      expect(session.repository.commands, hasLength(1));

      editor.removeTag(_tagId(3));
      await _deliverEvents(session.container);

      expect(session.state.operation, isA<OperationIdle<Intention>>());
      expect(session.state.canSubmit, isTrue);
      expect(session.state.missingTagIds, isEmpty);
      expect(session.state.failurePresentation, isNull);
      expect(session.repository.commands, hasLength(1));

      editor.submit();

      expect(session.repository.commands, hasLength(2));
      expect(
        session.repository.commands.last,
        isA<CreateIntention>()
            .having((command) => command.title, 'название', 'Другое название')
            .having(
              (command) => command.description,
              'описание',
              _rawDescription,
            )
            .having((command) => command.tagIds, 'теги', {_tagId(4)})
            .having(
              (command) => command.readiness,
              'готовность',
              IntentionReadiness.ready,
            )
            .having(
              (command) => command.favoriteMark,
              'избранное',
              FavoriteMark.notFavorite,
            ),
      );
      session.repository.completeCommand(1, _savedResult());
      await _settle(session.container);
    });

    test('устранимая unavailable повторяется только явной отправкой с новым токеном и текущим черновиком', () async {
      final session = await _failedFullDraftSession(
        const IntentionUnavailableFailure(),
      );
      final tokens = <IntentionOperationToken>[];
      final completionSubscription = session.coordinator.intentionCompletions
          .listen((completion) => tokens.add(completion.token));
      addTearDown(completionSubscription.cancel);
      final firstToken = session.state.failurePresentation!.token;
      final editor = session.editor..changeTitle('Повтор');
      editor.draftTagSet.add(_tag(3, 'Спорт'));
      await _deliverEvents(session.container);

      expect(session.state.canRetry, isTrue);
      expect(session.repository.commands, hasLength(1));

      editor.submit();

      expect(session.repository.commands, hasLength(2));
      expect(
        session.repository.commands.last,
        isA<CreateIntention>()
            .having((command) => command.title, 'название', 'Повтор')
            .having((command) => command.tagIds, 'теги', {
              _tagId(1),
              _tagId(2),
              _tagId(3),
            }),
      );
      expect(session.state.operation, isA<OperationRunning<Intention>>());
      expect(session.state.failurePresentation, isNull);

      session.repository.completeCommand(
        1,
        const ResultFailure(IntentionConflictFailure()),
      );
      await _deliverEvents(session.container);

      expect(tokens, hasLength(1));
      expect(identical(tokens.single, firstToken), isFalse);
      expect(session.state.failurePresentation!.token, same(tokens.single));
      editor
        ..changeTitle('После конфликта')
        ..removeTag(_tagId(3))
        ..submit();
      await _deliverEvents(session.container);

      expect(session.state.canSubmit, isFalse);
      expect(
        session.state.operation,
        isA<OperationFailed<Intention>>().having(
          (operation) => operation.failure,
          'отказ',
          isA<IntentionConflictFailure>(),
        ),
      );
      expect(session.state.draft.title, 'После конфликта');
      expect(session.repository.commands, hasLength(2));
    });

    test('отказ координатора принять отправку сохраняет весь черновик и не отправляет команду', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle(_rawTitle)
        ..changeDescription(_rawDescription)
        ..markFavorite()
        ..confirmReadiness();
      editor.draftTagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Выходные'));
      // Остановка приложения запрещает координатору принимать новую работу.
      await coordinator.shutdown();

      editor.submit();
      await _deliverEvents(container);

      final failed = container.read(provider);
      expect(
        failed.operation,
        isA<OperationFailed<Intention>>().having(
          (operation) => operation.failure,
          'отказ',
          isA<IntentionUnexpectedFailure>(),
        ),
      );
      expect(failed.draft.title, _rawTitle);
      expect(failed.draft.description, _rawDescription);
      expect(failed.draft.tagIds, [_tagId(1), _tagId(2)]);
      expect(failed.draft.readiness, IntentionReadiness.ready);
      expect(failed.draft.favoriteMark, FavoriteMark.favorite);
      expect(_tagNames(failed), {_tagId(1): 'Дом', _tagId(2): 'Выходные'});
      expect(failed.draftAvailability, IntentionDraftAvailability.editable);
      expect(failed.canSubmit, isFalse);
      expect(editor.draftTagSet.current.tagIds, [_tagId(1), _tagId(2)]);
      expect(coordinator.isKeyRunning(formKey), isFalse);
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('одновременные отправки и отказ одной сессии не меняют черновик, набор и результат другой', () async {
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
      final first = container.read(firstProvider.notifier)
        ..changeTitle('Первое')
        ..changeDescription('Описание первого')
        ..markFavorite()
        ..confirmReadiness();
      first.draftTagSet.add(_tag(1, 'Дом'));
      final second = container.read(secondProvider.notifier)
        ..changeTitle('  Второе  ');
      second.draftTagSet.add(_tag(2, 'Выходные'));
      await _deliverEvents(container);
      final firstPublished = <IntentionDraftTagSetSnapshot>[];
      final firstChanges = first.draftTagSet.changes.listen(firstPublished.add);
      addTearDown(firstChanges.cancel);

      first.submit();
      final firstCommand = repository.commands.single as CreateIntention;

      // Отправка первой сессии не фиксирует черновик второй.
      expect(
        second.draftTagSet.current.availability,
        IntentionDraftAvailability.editable,
      );
      expect(
        second.draftTagSet.add(_tag(1, 'Дом')),
        IntentionDraftTagAddition.added,
      );
      second
        ..unmarkFavorite()
        ..markFavorite()
        ..submit();
      await _deliverEvents(container);

      expect(repository.commands, hasLength(2));
      expect(container.read(firstProvider).draft.tagIds, [_tagId(1)]);
      expect(
        container.read(secondProvider).operation,
        isA<OperationRunning<Intention>>(),
      );

      repository.completeCommand(
        0,
        ResultFailure(IntentionCreationTagsMissingFailure([_tagId(1)])),
      );
      await _deliverEvents(container);

      final firstFailed = container.read(firstProvider);
      expect(firstFailed.missingTagIds, {_tagId(1)});
      expect(firstFailed.failurePresentation, isNotNull);
      expect(firstFailed.draft.title, 'Первое');
      expect(firstFailed.draft.description, 'Описание первого');
      expect(firstFailed.draft.tagIds, [_tagId(1)]);
      expect(firstFailed.draft.readiness, IntentionReadiness.ready);
      expect(firstFailed.draft.favoriteMark, FavoriteMark.favorite);
      // Отказ первой сессии не помечает тот же тег отсутствующим во второй
      // и не снимает фиксацию её принятой отправки.
      final secondRunning = container.read(secondProvider);
      expect(secondRunning.operation, isA<OperationRunning<Intention>>());
      expect(secondRunning.missingTagIds, isEmpty);
      expect(secondRunning.failurePresentation, isNull);
      expect(
        second.draftTagSet.current.availability,
        IntentionDraftAvailability.submitting,
      );

      repository.completeCommand(1, _savedResult());
      await _deliverEvents(container);

      final secondSucceeded = container.read(secondProvider);
      expect(secondSucceeded.operation, isA<OperationSucceeded<Intention>>());
      expect(secondSucceeded.event, isA<IntentionEditorCreated>());
      expect(
        second.draftTagSet.current.availability,
        IntentionDraftAvailability.closed,
      );
      expect(container.read(firstProvider), same(firstFailed));
      expect(
        first.draftTagSet.current.availability,
        IntentionDraftAvailability.editable,
      );
      expect(firstPublished.map((snapshot) => snapshot.tagIds), [
        [_tagId(1)],
        [_tagId(1)],
      ]);
      expect(firstPublished.map((snapshot) => snapshot.availability), [
        IntentionDraftAvailability.submitting,
        IntentionDraftAvailability.editable,
      ]);
      expect(repository.commands, [
        same(firstCommand),
        isA<CreateIntention>()
            .having((command) => command.title, 'название', '  Второе  ')
            .having((command) => command.description, 'описание', isNull)
            .having((command) => command.tagIds, 'теги', {_tagId(2), _tagId(1)})
            .having(
              (command) => command.readiness,
              'готовность',
              IntentionReadiness.notReady,
            )
            .having(
              (command) => command.favoriteMark,
              'избранное',
              FavoriteMark.favorite,
            ),
      ]);
      expect(firstCommand.tagIds, {_tagId(1)});
      expect(firstCommand.favoriteMark, FavoriteMark.favorite);
      expect(repository.tagCommands, isEmpty);
    });
  });

  group('проекция выбранных тегов', () {
    test('название из выбора доступно сразу, а переименование через watchTag обновляет только проекцию', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier);

      editor.draftTagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Выходные'));

      final added = container.read(provider);
      expect(_tagNames(added), {_tagId(1): 'Дом', _tagId(2): 'Выходные'});
      expect(_tagStatus(added, 1), isA<IntentionDraftTagLoading>());
      expect(_tagStatus(added, 2), isA<IntentionDraftTagLoading>());
      expect(watches.of(_tagId(1)), hasLength(1));
      expect(watches.of(_tagId(2)), hasLength(1));
      await _deliverEvents(container);
      final tagIds = container.read(provider).draft.tagIds;
      final published = <IntentionDraftTagSetSnapshot>[];
      final changesSubscription = editor.draftTagSet.changes.listen(
        published.add,
      );
      addTearDown(changesSubscription.cancel);

      watches.single(_tagId(1)).observe(_tag(1, 'Быт'), revision: 2);
      watches.single(_tagId(2)).observe(_tag(2, 'Выходные'), revision: 2);
      await _deliverEvents(container);

      final renamed = container.read(provider);
      expect(_tagNames(renamed), {_tagId(1): 'Быт', _tagId(2): 'Выходные'});
      expect(_tagStatus(renamed, 1), isA<IntentionDraftTagAvailable>());
      expect(_tagStatus(renamed, 2), isA<IntentionDraftTagAvailable>());
      expect(renamed.draft.tagIds, same(tagIds));
      expect(renamed.draft.tagIds, [_tagId(1), _tagId(2)]);
      expect(editor.draftTagSet.current.tagIds, same(tagIds));
      expect(published, isEmpty);
      expect(renamed.operation, isA<OperationIdle<Intention>>());
      expect(watches.count, 2);
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('подтверждённое отсутствие сохраняет идентификатор и последнее название до явного снятия и не подменяется одноимённым тегом', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение');
      editor.draftTagSet.add(_tag(1, 'Дом'));
      await _deliverEvents(container);
      final deletedWatch = watches.single(_tagId(1))
        ..observe(_tag(1, 'Быт'), revision: 2)
        ..observe(null, revision: 3);
      await _deliverEvents(container);

      final missing = container.read(provider);
      expect(missing.draft.tagIds, [_tagId(1)]);
      expect(_tagNames(missing), {_tagId(1): 'Быт'});
      expect(_tagStatus(missing, 1), isA<IntentionDraftTagMissing>());
      // Отсутствие в проекции не заменяет транзакционную проверку при
      // сохранении и само не блокирует отправку.
      expect(missing.operation, isA<OperationIdle<Intention>>());
      expect(missing.canSubmit, isTrue);

      expect(
        editor.draftTagSet.add(_tag(4, 'Быт')),
        IntentionDraftTagAddition.added,
      );
      watches.single(_tagId(4)).observe(_tag(4, 'Быт'), revision: 4);
      // Окончание наблюдения после подтверждённого отсутствия сохраняет его.
      deletedWatch.end();
      await _deliverEvents(container);

      final withReplacement = container.read(provider);
      expect(withReplacement.draft.tagIds, [_tagId(1), _tagId(4)]);
      expect(_tagNames(withReplacement), {_tagId(1): 'Быт', _tagId(4): 'Быт'});
      expect(_tagStatus(withReplacement, 1), isA<IntentionDraftTagMissing>());
      expect(_tagStatus(withReplacement, 4), isA<IntentionDraftTagAvailable>());

      editor.removeTag(_tagId(1));

      final corrected = container.read(provider);
      expect(corrected.draft.tagIds, [_tagId(4)]);
      expect(_tagNames(corrected), {_tagId(4): 'Быт'});
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('загрузка и типизированный отказ чтения отличаются от удаления, а повтор наблюдения доступен только после устранимого отказа', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier);
      editor.draftTagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Выходные'))
        ..add(_tag(3, 'Спорт'));
      final loading = container.read(provider);
      for (final number in [1, 2, 3]) {
        expect(
          _tagStatus(loading, number),
          isA<IntentionDraftTagLoading>(),
          reason: '$number',
        );
      }
      await _deliverEvents(container);

      watches.single(_tagId(1)).fail(const TagReadUnavailableFailure());
      watches.single(_tagId(2)).fail(const TagReadCorruptionFailure());
      watches.single(_tagId(3)).fail(const TagReadUnexpectedFailure());
      await _deliverEvents(container);

      final failed = container.read(provider);
      expect(failed.draft.tagIds, [_tagId(1), _tagId(2), _tagId(3)]);
      expect(_tagNames(failed), {
        _tagId(1): 'Дом',
        _tagId(2): 'Выходные',
        _tagId(3): 'Спорт',
      });
      expect(
        _tagStatus(failed, 1),
        _readFailed<TagReadUnavailableFailure>(canRetry: true),
      );
      expect(
        _tagStatus(failed, 2),
        _readFailed<TagReadCorruptionFailure>(canRetry: false),
      );
      expect(
        _tagStatus(failed, 3),
        _readFailed<TagReadUnexpectedFailure>(canRetry: false),
      );
      expect(failed.canSubmit, isTrue);

      editor
        ..retryTagObservation(_tagId(2))
        ..retryTagObservation(_tagId(3));

      expect(watches.of(_tagId(2)), hasLength(1));
      expect(watches.of(_tagId(3)), hasLength(1));
      expect(container.read(provider), same(failed));

      editor
        ..retryTagObservation(_tagId(1))
        ..retryTagObservation(_tagId(1));

      final retrying = container.read(provider);
      expect(watches.of(_tagId(1)), hasLength(2));
      expect(_tagStatus(retrying, 1), isA<IntentionDraftTagLoading>());
      expect(_tagNames(retrying)[_tagId(1)], 'Дом');

      final [failedWatch, retriedWatch] = watches.of(_tagId(1));
      retriedWatch.observe(_tag(1, 'Быт'), revision: 2);
      // Поздний ответ отказавшего наблюдения не меняет восстановленное.
      failedWatch
        ..deliverLate(_tag(1, 'Поздний'), revision: 3)
        ..endLate();
      await _deliverEvents(container);

      final recovered = container.read(provider);
      expect(_tagNames(recovered)[_tagId(1)], 'Быт');
      expect(_tagStatus(recovered, 1), isA<IntentionDraftTagAvailable>());
      expect(failedWatch.isReleased, isTrue);
      expect(retriedWatch.isReleased, isFalse);
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('окончание наблюдения сохраняет установленную причину, а необъяснённое окончание даёт неизвестный отказ', () async {
      final watches = _TagWatches()..failingIds.add(_tagId(5));
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier);
      editor.draftTagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Выходные'))
        ..add(_tag(3, 'Спорт'))
        ..add(_tag(4, 'Чтение'))
        ..add(_tag(5, 'Сад'));
      await _deliverEvents(container);

      watches.single(_tagId(1))
        ..fail(const TagReadUnavailableFailure())
        ..end();
      watches.single(_tagId(2))
        ..observe(_tag(2, 'Выходные'), revision: 1)
        ..end();
      watches.single(_tagId(3)).end();
      watches.single(_tagId(4)).throwError();
      await _deliverEvents(container);

      final ended = container.read(provider);
      expect(ended.draft.tagIds, [for (var n = 1; n <= 5; n++) _tagId(n)]);
      expect(_tagNames(ended), {
        _tagId(1): 'Дом',
        _tagId(2): 'Выходные',
        _tagId(3): 'Спорт',
        _tagId(4): 'Чтение',
        _tagId(5): 'Сад',
      });
      expect(
        _tagStatus(ended, 1),
        _readFailed<TagReadUnavailableFailure>(canRetry: true),
      );
      for (final number in [2, 3, 4, 5]) {
        expect(
          _tagStatus(ended, number),
          _readFailed<TagReadUnexpectedFailure>(canRetry: false),
          reason: '$number',
        );
      }
      expect(watches.of(_tagId(5)), isEmpty);
      expect(ended.canSubmit, isTrue);
      expect(repository.commands, isEmpty);
    });

    test('старый ответ не отменяет новое название, не возвращает снятый тег и не меняет повторно добавленный', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier);
      final tagSet = editor.draftTagSet..add(_tag(1, 'Дом'));
      await _deliverEvents(container);
      final firstWatch = watches.single(_tagId(1))
        ..observe(_tag(1, 'Быт'), revision: 3)
        ..observe(_tag(1, 'Дом'), revision: 2)
        ..observe(null, revision: 1);
      await _deliverEvents(container);

      final renamed = container.read(provider);
      expect(_tagNames(renamed), {_tagId(1): 'Быт'});
      expect(_tagStatus(renamed, 1), isA<IntentionDraftTagAvailable>());

      editor.removeTag(_tagId(1));
      await _deliverEvents(container);
      expect(firstWatch.isReleased, isTrue);
      final published = <IntentionDraftTagSetSnapshot>[];
      final changesSubscription = tagSet.changes.listen(published.add);
      addTearDown(changesSubscription.cancel);

      firstWatch
        ..deliverLate(_tag(1, 'Поздний'), revision: 4)
        ..endLate();
      await _deliverEvents(container);

      final removed = container.read(provider);
      expect(removed.draft.tagIds, isEmpty);
      expect(removed.selectedTags, isEmpty);
      expect(removed.draft.isChanged, isFalse);
      expect(published, isEmpty);

      expect(tagSet.add(_tag(1, 'Дом')), IntentionDraftTagAddition.added);
      expect(watches.of(_tagId(1)), hasLength(2));
      firstWatch
        ..deliverLate(_tag(1, 'Поздний'), revision: 5)
        ..deliverLate(null, revision: 6)
        ..endLate();
      await _deliverEvents(container);

      final readded = container.read(provider);
      expect(readded.draft.tagIds, [_tagId(1)]);
      expect(_tagNames(readded), {_tagId(1): 'Дом'});
      expect(_tagStatus(readded, 1), isA<IntentionDraftTagLoading>());

      final readdedWatch = watches.of(_tagId(1)).last
        ..observe(_tag(1, 'Дом'), revision: 7);
      await _deliverEvents(container);

      expect(
        _tagStatus(container.read(provider), 1),
        isA<IntentionDraftTagAvailable>(),
      );
      expect(readdedWatch.isReleased, isFalse);
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('наблюдения разных сессий одного тега независимы', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final firstProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final secondProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final firstSubscription = container.listen(firstProvider, (_, _) {});
      final secondSubscription = container.listen(secondProvider, (_, _) {});
      addTearDown(secondSubscription.close);
      container.read(firstProvider.notifier).draftTagSet.add(_tag(1, 'Дом'));
      container.read(secondProvider.notifier).draftTagSet.add(_tag(1, 'Дом'));
      await _deliverEvents(container);
      final [firstWatch, secondWatch] = watches.of(_tagId(1));

      firstWatch.observe(_tag(1, 'Быт'), revision: 2);
      await _deliverEvents(container);

      final first = container.read(firstProvider);
      final second = container.read(secondProvider);
      expect(_tagNames(first), {_tagId(1): 'Быт'});
      expect(_tagStatus(first, 1), isA<IntentionDraftTagAvailable>());
      expect(_tagNames(second), {_tagId(1): 'Дом'});
      expect(_tagStatus(second, 1), isA<IntentionDraftTagLoading>());

      firstSubscription.close();
      await _deliverEvents(container);
      secondWatch.observe(_tag(1, 'Быт'), revision: 2);
      await _deliverEvents(container);

      expect(firstWatch.isReleased, isTrue);
      expect(secondWatch.isReleased, isFalse);
      expect(_tagNames(container.read(secondProvider)), {_tagId(1): 'Быт'});
      expect(repository.commands, isEmpty);
    });

    test('снятие, успешное создание и освобождение сессии освобождают подписки, а наблюдения не отправляют команды графа', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
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
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение');
      editor.draftTagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Выходные'))
        ..add(_tag(3, 'Спорт'));
      await _deliverEvents(container);

      editor.removeTag(_tagId(3));

      expect(watches.single(_tagId(3)).isReleased, isTrue);
      expect(watches.single(_tagId(1)).isReleased, isFalse);
      expect(watches.single(_tagId(2)).isReleased, isFalse);

      editor.submit();
      // Во время отправки проекция обновляется, а состав набора зафиксирован.
      watches.single(_tagId(1)).observe(_tag(1, 'Быт'), revision: 2);
      editor.removeTag(_tagId(2));
      await _deliverEvents(container);

      final running = container.read(provider);
      expect(running.operation, isA<OperationRunning<Intention>>());
      expect(running.draft.tagIds, [_tagId(1), _tagId(2)]);
      expect(_tagNames(running), {_tagId(1): 'Быт', _tagId(2): 'Выходные'});
      expect(watches.single(_tagId(2)).isReleased, isFalse);
      expect(
        repository.commands.single,
        isA<CreateIntention>().having((command) => command.tagIds, 'теги', {
          _tagId(1),
          _tagId(2),
        }),
      );

      repository.completeCommand(0, _savedResult());
      await _deliverEvents(container);

      final closed = container.read(provider);
      expect(closed.draftAvailability, IntentionDraftAvailability.closed);
      expect(watches.single(_tagId(1)).isReleased, isTrue);
      expect(watches.single(_tagId(2)).isReleased, isTrue);
      watches.single(_tagId(1)).deliverLate(_tag(1, 'Поздний'), revision: 3);
      expect(container.read(provider), same(closed));

      final otherProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final otherSubscription = container.listen(otherProvider, (_, _) {});
      container.read(otherProvider.notifier).draftTagSet.add(_tag(4, 'Сад'));
      await _deliverEvents(container);
      otherSubscription.close();
      await _deliverEvents(container);

      expect(watches.single(_tagId(4)).isReleased, isTrue);
      expect(watches.count, 4);
      expect(repository.commands, hasLength(1));
      expect(repository.tagCommands, isEmpty);
      expect(completions, hasLength(1));
    });
  });

  group('решение о закрытии сессии', () {
    test('неизменённая сессия завершается сразу без подтверждения, а повторный запрос ничего не закрывает', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier);
      final tagSetClosed = Completer<void>();
      editor.draftTagSet.changes.listen((_) {}, onDone: tagSetClosed.complete);

      final decision = editor.requestClose();

      expect(
        decision,
        isA<IntentionCreationClosedImmediately>().having(
          (decision) => decision.savingOnClose,
          'отправка',
          IntentionCreationSavingOnClose.notStarted,
        ),
      );
      final closed = container.read(provider);
      expect(closed.closing, isA<IntentionCreationClosedOnRequest>());
      expect(closed.draftAvailability, IntentionDraftAvailability.closed);
      expect(closed.canSubmit, isFalse);
      expect(editor.requestClose(), isA<IntentionCreationCloseSessionEnded>());

      editor
        ..changeTitle('После закрытия')
        ..markFavorite()
        ..submit();
      expect(
        editor.draftTagSet.add(_tag(1, 'Дом')),
        IntentionDraftTagAddition.sessionClosed,
      );
      await _deliverEvents(container);

      expect(tagSetClosed.isCompleted, isTrue);
      expect(container.read(provider), same(closed));
      expect(closed.draft.isChanged, isFalse);
      expect(repository.commands, isEmpty);
      expect(
        container
            .read(graphCommandCoordinatorProvider.notifier)
            .isKeyRunning(formKey),
        isFalse,
      );
    });

    test('возврат всех полей к начальным значениям позволяет закрыть сессию без подтверждения', () {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('  ')
        ..changeDescription('Описание')
        ..markFavorite()
        ..confirmReadiness();
      editor.draftTagSet.add(_tag(1, 'Дом'));
      editor
        ..changeTitle('')
        ..changeDescription('')
        ..unmarkFavorite()
        ..disableReadiness()
        ..removeTag(_tagId(1));

      expect(editor.requestClose(), isA<IntentionCreationClosedImmediately>());
      expect(
        container.read(provider).draftAvailability,
        IntentionDraftAvailability.closed,
      );
      expect(repository.commands, isEmpty);
    });

    test('изменение каждого поля требует одного подтверждения, связанного с ключом сессии', () {
      final edits = <String, void Function(IntentionEditorViewModel)>{
        'название': (editor) => editor.changeTitle('Намерение'),
        'пробельное название': (editor) => editor.changeTitle('   '),
        'описание': (editor) => editor.changeDescription('Описание'),
        'набор тегов': (editor) => editor.draftTagSet.add(_tag(1, 'Дом')),
        'готовность': (editor) => editor.confirmReadiness(),
        'избранное': (editor) => editor.markFavorite(),
      };
      for (final MapEntry(key: name, value: edit) in edits.entries) {
        final repository = ControlledCatalogRepository();
        final container = _container(repository);
        final formKey = IntentionCreationFormKey();
        final provider = intentionEditorViewModelProvider(formKey);
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        final editor = container.read(provider.notifier);
        edit(editor);
        final draft = container.read(provider).draft;

        final decision = editor.requestClose();
        final repeated = editor.requestClose();

        final confirmation = _confirmationOf(decision);
        expect(confirmation.formKey, same(formKey), reason: name);
        expect(
          confirmation.savingOnClose,
          IntentionCreationSavingOnClose.notStarted,
          reason: name,
        );
        expect(
          repeated,
          isA<IntentionCreationCloseAwaitingConfirmation>(),
          reason: name,
        );
        final confirming = container.read(provider);
        expect(
          confirming.closing,
          isA<IntentionCreationCloseConfirming>().having(
            (closing) => closing.confirmation,
            'подтверждение',
            same(confirmation),
          ),
          reason: name,
        );
        expect(confirming.draft, same(draft), reason: name);
        expect(
          confirming.draftAvailability,
          IntentionDraftAvailability.editable,
          reason: name,
        );
        expect(repository.commands, isEmpty, reason: name);
      }
    });

    test('продолжение сохраняет весь черновик и сессию, а прежнее подтверждение больше не действует', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle(_rawTitle)
        ..changeDescription(_rawDescription)
        ..markFavorite()
        ..confirmReadiness();
      editor.draftTagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Выходные'));
      await _deliverEvents(container);
      final before = container.read(provider);
      final confirmation = _confirmationOf(editor.requestClose());

      final resolution = editor.resolveClose(
        confirmation,
        IntentionCreationCloseChoice.continueEditing,
      );

      expect(resolution, IntentionCreationCloseResolution.continued);
      final continued = container.read(provider);
      expect(continued.draft, same(before.draft));
      expect(_tagNames(continued), {_tagId(1): 'Дом', _tagId(2): 'Выходные'});
      expect(continued.closing, isA<IntentionCreationCloseNotRequested>());
      expect(continued.draftAvailability, IntentionDraftAvailability.editable);
      expect(continued.canSubmit, isTrue);
      expect(watches.single(_tagId(1)).isReleased, isFalse);
      expect(watches.single(_tagId(2)).isReleased, isFalse);
      expect(
        editor.draftTagSet.current.availability,
        IntentionDraftAvailability.editable,
      );

      expect(
        editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.outdated,
      );
      expect(container.read(provider), same(continued));
      final renewed = _confirmationOf(editor.requestClose());
      expect(renewed, isNot(same(confirmation)));

      // Прежнее подтверждение не отвечает за новое ожидающее.
      expect(
        editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.outdated,
      );
      final pending = container.read(provider);
      expect(
        pending.closing,
        isA<IntentionCreationCloseConfirming>().having(
          (closing) => closing.confirmation,
          'подтверждение',
          same(renewed),
        ),
      );
      expect(pending.draftAvailability, IntentionDraftAvailability.editable);
      expect(watches.single(_tagId(1)).isReleased, isFalse);
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('подтверждённый сброс до отправки завершает сессию без записи и освобождает наблюдения', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final completions = <GraphCommandCompletion>[];
      final completionSubscription = coordinator.completions.listen(
        completions.add,
      );
      addTearDown(completionSubscription.cancel);
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение')
        ..markFavorite()
        ..confirmReadiness();
      editor.draftTagSet.add(_tag(1, 'Дом'));
      final tagSetClosed = Completer<void>();
      editor.draftTagSet.changes.listen((_) {}, onDone: tagSetClosed.complete);
      await _deliverEvents(container);
      final confirmation = _confirmationOf(editor.requestClose());

      final resolution = editor.resolveClose(
        confirmation,
        IntentionCreationCloseChoice.discardDraft,
      );

      expect(resolution, IntentionCreationCloseResolution.closed);
      final closed = container.read(provider);
      expect(closed.closing, isA<IntentionCreationClosedOnRequest>());
      expect(closed.draftAvailability, IntentionDraftAvailability.closed);
      expect(closed.canSubmit, isFalse);
      expect(watches.single(_tagId(1)).isReleased, isTrue);

      editor
        ..changeTitle('После сброса')
        ..unmarkFavorite()
        ..submit();
      expect(
        editor.draftTagSet.add(_tag(2, 'Спорт')),
        IntentionDraftTagAddition.sessionClosed,
      );
      await _deliverEvents(container);

      expect(tagSetClosed.isCompleted, isTrue);
      expect(container.read(provider), same(closed));
      expect(editor.requestClose(), isA<IntentionCreationCloseSessionEnded>());
      expect(
        editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.outdated,
      );
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
      expect(completions, isEmpty);
      expect(coordinator.isKeyRunning(formKey), isFalse);
    });

    test('переходы в общий выбор тегов и обратно не завершают сессию и не запрашивают сброс', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение')
        ..markFavorite();

      // Каждое открытие выбора наблюдает набор, добавляет тег и закрывается,
      // не затрагивая владельца сессии.
      for (final tag in [_tag(1, 'Дом'), _tag(2, 'Спорт')]) {
        final opening = editor.draftTagSet.changes.listen((_) {});
        expect(editor.draftTagSet.add(tag), IntentionDraftTagAddition.added);
        await _deliverEvents(container);
        await opening.cancel();
      }

      final returned = container.read(provider);
      expect(returned.closing, isA<IntentionCreationCloseNotRequested>());
      expect(returned.draftAvailability, IntentionDraftAvailability.editable);
      expect(returned.draft.title, 'Намерение');
      expect(returned.draft.favoriteMark, FavoriteMark.favorite);
      expect(returned.draft.tagIds, [_tagId(1), _tagId(2)]);
      expect(
        editor.draftTagSet.current.availability,
        IntentionDraftAvailability.editable,
      );
      expect(
        editor.requestClose(),
        isA<IntentionCreationCloseNeedsConfirmation>(),
      );
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
    });

    test('отправка во время ожидания подтверждения не принимается и не меняет подтверждение', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение');
      final confirmation = _confirmationOf(editor.requestClose());

      editor.submit();

      final confirming = container.read(provider);
      expect(repository.commands, isEmpty);
      expect(confirming.operation, isA<OperationIdle<Intention>>());
      expect(confirming.canSubmit, isFalse);
      expect(
        confirming.closing,
        isA<IntentionCreationCloseConfirming>().having(
          (closing) => closing.confirmation,
          'подтверждение',
          same(confirmation),
        ),
      );

      expect(
        editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.continueEditing,
        ),
        IntentionCreationCloseResolution.continued,
      );
      expect(container.read(provider).canSubmit, isTrue);
      editor.submit();

      expect(
        repository.commands.single,
        isA<CreateIntention>().having(
          (command) => command.title,
          'название',
          'Намерение',
        ),
      );
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await _settle(container);
    });

    test('во время принятой отправки решение сообщает о продолжении сохранения, а подтверждённое закрытие не отменяет операцию', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();
      addTearDown(presenter.release);
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Полное намерение')
        ..markFavorite();
      editor.draftTagSet.add(_tag(1, 'Дом'));
      editor.submit();
      final command = repository.commands.single;

      final confirmation = _confirmationOf(editor.requestClose());
      expect(
        confirmation.savingOnClose,
        IntentionCreationSavingOnClose.continues,
      );
      final resolution = editor.resolveClose(
        confirmation,
        IntentionCreationCloseChoice.discardDraft,
      );

      expect(resolution, IntentionCreationCloseResolution.closed);
      final closed = container.read(provider);
      expect(closed.draftAvailability, IntentionDraftAvailability.closed);
      expect(watches.single(_tagId(1)).isReleased, isTrue);
      expect(coordinator.isKeyRunning(formKey), isTrue);
      expect(editor.requestClose(), isA<IntentionCreationCloseSessionEnded>());

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(container);

      final fallback = await presenter.nextClaim();
      expect(
        fallback!.completion,
        isA<IntentionCommandCompletion>().having(
          (completion) => completion.result,
          'результат',
          isA<ResultFailure<IntentionCommandSuccess>>().having(
            (result) => result.failure,
            'отказ',
            isA<IntentionUnavailableFailure>(),
          ),
        ),
      );
      coordinator.confirmPresentation(fallback);
      expect(container.read(provider), same(closed));
      expect(closed.failurePresentation, isNull);
      expect(closed.event, isNull);
      expect(coordinator.isKeyRunning(formKey), isFalse);
      expect(repository.commands, [same(command)]);
    });

    test('неизменённая сессия во время принятой отправки закрывается сразу с продолжением сохранения', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();
      addTearDown(presenter.release);
      final formKey = IntentionCreationFormKey();
      final provider = intentionEditorViewModelProvider(formKey);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)..submit();
      expect(repository.commands, hasLength(1));

      final decision = editor.requestClose();

      expect(
        decision,
        isA<IntentionCreationClosedImmediately>().having(
          (decision) => decision.savingOnClose,
          'отправка',
          IntentionCreationSavingOnClose.continues,
        ),
      );
      expect(coordinator.isKeyRunning(formKey), isTrue);
      final closed = container.read(provider);
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

      final fallback = await presenter.nextClaim();
      expect(fallback!.completion, isA<IntentionCommandCompletion>());
      coordinator.confirmPresentation(fallback);
      expect(container.read(provider), same(closed));
      expect(repository.commands, hasLength(1));
    });

    test('успех при ожидающем подтверждении завершает только свою сессию и делает её прежний ответ недействительным', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();
      addTearDown(presenter.release);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final otherProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final events = <IntentionEditorEvent>[];
      final subscription = container.listen(provider, (previous, next) {
        final event = next.event;
        if (event != null && previous?.event == null) {
          events.add(event);
        }
      });
      addTearDown(subscription.close);
      final otherSubscription = container.listen(otherProvider, (_, _) {});
      addTearDown(otherSubscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение')
        ..submit();
      final otherEditor = container.read(otherProvider.notifier)
        ..changeTitle('Другое намерение');
      final confirmation = _confirmationOf(editor.requestClose());
      final otherConfirmation = _confirmationOf(otherEditor.requestClose());

      repository.completeCommand(0, _savedResult());
      await _settle(container);

      final succeeded = container.read(provider);
      expect(events, [isA<IntentionEditorCreated>()]);
      expect(succeeded.operation, isA<OperationSucceeded<Intention>>());
      expect(succeeded.closing, isA<IntentionCreationCloseNotRequested>());
      expect(succeeded.draftAvailability, IntentionDraftAvailability.closed);
      for (final choice in IntentionCreationCloseChoice.values) {
        expect(
          editor.resolveClose(confirmation, choice),
          IntentionCreationCloseResolution.outdated,
        );
      }
      expect(editor.requestClose(), isA<IntentionCreationCloseSessionEnded>());
      expect(container.read(provider), same(succeeded));

      expect(
        otherEditor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.outdated,
      );
      final other = container.read(otherProvider);
      expect(
        other.closing,
        isA<IntentionCreationCloseConfirming>().having(
          (closing) => closing.confirmation,
          'подтверждение',
          same(otherConfirmation),
        ),
      );
      expect(other.draftAvailability, IntentionDraftAvailability.editable);
      expect(other.event, isNull);
      expect(
        otherEditor.resolveClose(
          otherConfirmation,
          IntentionCreationCloseChoice.continueEditing,
        ),
        IntentionCreationCloseResolution.continued,
      );
      expect(container.read(otherProvider).draft.title, 'Другое намерение');

      final success = await presenter.nextClaim();
      expect(
        success!.completion,
        isA<IntentionCommandCompletion>().having(
          (completion) => completion.result,
          'результат',
          isA<ResultSuccess<IntentionCommandSuccess>>(),
        ),
      );
      coordinator.confirmPresentation(success);
      expect(repository.commands, hasLength(1));
    });

    test('отказ при ожидающем подтверждении сохраняет черновик и право живой формы и требует нового решения', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();
      addTearDown(presenter.release);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)
        ..changeTitle(_rawTitle)
        ..markFavorite()
        ..submit();
      final confirmation = _confirmationOf(editor.requestClose());
      expect(
        confirmation.savingOnClose,
        IntentionCreationSavingOnClose.continues,
      );

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(container);

      final failed = container.read(provider);
      final claim = failed.failurePresentation!;
      expect(failed.operation, isA<OperationFailed<Intention>>());
      expect(failed.closing, isA<IntentionCreationCloseNotRequested>());
      expect(
        editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.outdated,
      );
      final kept = container.read(provider);
      expect(kept, same(failed));
      expect(kept.draftAvailability, IntentionDraftAvailability.editable);
      expect(kept.draft.title, _rawTitle);
      expect(kept.draft.favoriteMark, FavoriteMark.favorite);
      expect(kept.canRetry, isTrue);
      expect(coordinator.claimInitiatorFailure(claim.token), same(claim));
      GraphAppPresentationClaim? fallback;
      unawaited(presenter.nextClaim().then((value) => fallback = value));
      await _settle(container);
      expect(fallback, isNull);

      final renewed = _confirmationOf(editor.requestClose());
      expect(renewed, isNot(same(confirmation)));
      expect(renewed.savingOnClose, IntentionCreationSavingOnClose.notStarted);
      expect(repository.commands, hasLength(1));
    });

    test('сброс после отказа без renderer передаёт непредъявленное право общей поверхности один раз и не подтверждает его во ViewModel', () async {
      final session = await _failedFullDraftSession(
        const IntentionUnavailableFailure(),
      );
      final surface = _AppSurface(session.coordinator);
      final claim = session.state.failurePresentation!;
      final confirmation = _confirmationOf(session.editor.requestClose());
      expect(
        confirmation.savingOnClose,
        IntentionCreationSavingOnClose.notStarted,
      );
      await _settle(session.container);
      // Подтверждение поверх формы оставляет право ей.
      expect(session.state.failurePresentation, same(claim));
      expect(surface.presented, isEmpty);

      expect(
        session.editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.closed,
      );
      await _settle(session.container);

      final closed = session.state;
      expect(closed.draftAvailability, IntentionDraftAvailability.closed);
      expect(closed.failurePresentation, isNull);
      expect(surface.presented.map((claim) => claim.completion), [
        isA<IntentionCommandCompletion>()
            .having(
              (completion) => completion.token,
              'token',
              same(claim.token),
            )
            .having(
              (completion) => completion.result,
              'исход',
              isA<ResultFailure<IntentionCommandSuccess>>().having(
                (result) => result.failure,
                'отказ',
                isA<IntentionUnavailableFailure>(),
              ),
            ),
      ]);
      expect(session.coordinator.claimInitiatorFailure(claim.token), isNull);

      // Освобождение закрытой сессии право повторно не передаёт.
      session.release();
      await _settle(session.container);
      expect(surface.presented, hasLength(1));
      expect(session.repository.commands, hasLength(1));
    });

    test('новое открытие после сброса пусто и не получает данные или событие прежней команды', () async {
      final watches = _TagWatches();
      final repository = ControlledCatalogRepository()
        ..tagObservations = watches.watch;
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();
      addTearDown(presenter.release);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      final editor = container.read(provider.notifier)
        ..changeTitle('Оставленный черновик')
        ..changeDescription('Описание')
        ..markFavorite()
        ..confirmReadiness();
      editor.draftTagSet.add(_tag(1, 'Дом'));
      editor.submit();
      expect(
        editor.resolveClose(
          _confirmationOf(editor.requestClose()),
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.closed,
      );
      subscription.close();
      await _settle(container);

      final reopenedProvider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final reopenedEvents = <IntentionEditorEvent>[];
      final reopenedSubscription = container.listen(reopenedProvider, (
        previous,
        next,
      ) {
        final event = next.event;
        if (event != null) {
          reopenedEvents.add(event);
        }
      });
      addTearDown(reopenedSubscription.close);
      final reopened = container.read(reopenedProvider);

      expect(reopened.draft.title, isEmpty);
      expect(reopened.draft.description, isEmpty);
      expect(reopened.draft.tagIds, isEmpty);
      expect(reopened.draft.readiness, IntentionReadiness.notReady);
      expect(reopened.draft.favoriteMark, FavoriteMark.notFavorite);
      expect(reopened.selectedTags, isEmpty);
      expect(reopened.closing, isA<IntentionCreationCloseNotRequested>());
      expect(reopened.draftAvailability, IntentionDraftAvailability.editable);

      repository.completeCommand(0, _savedResult());
      await _settle(container);

      expect(container.read(reopenedProvider), same(reopened));
      expect(reopenedEvents, isEmpty);
      expect(watches.count, 1);
      final success = await presenter.nextClaim();
      expect(
        success!.completion,
        isA<IntentionCommandCompletion>().having(
          (completion) => completion.result,
          'результат',
          isA<ResultSuccess<IntentionCommandSuccess>>(),
        ),
      );
      coordinator.confirmPresentation(success);
      expect(repository.commands, hasLength(1));
    });

    test('освобождение сессии делает ожидающее подтверждение недействительным и для нового построения того же ключа', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final firstSubscription = container.listen(provider, (_, _) {});
      final editor = container.read(provider.notifier)
        ..changeTitle('Намерение');
      final confirmation = _confirmationOf(editor.requestClose());

      firstSubscription.close();
      await _settle(container);

      expect(
        editor.resolveClose(
          confirmation,
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.outdated,
      );
      expect(editor.requestClose(), isA<IntentionCreationCloseSessionEnded>());
      final reopenedSubscription = container.listen(provider, (_, _) {});
      addTearDown(reopenedSubscription.close);
      final rebuilt = container.read(provider.notifier);
      for (final choice in IntentionCreationCloseChoice.values) {
        expect(
          rebuilt.resolveClose(confirmation, choice),
          IntentionCreationCloseResolution.outdated,
        );
      }
      final reopened = container.read(provider);
      expect(reopened.closing, isA<IntentionCreationCloseNotRequested>());
      expect(reopened.draftAvailability, IntentionDraftAvailability.editable);
      expect(reopened.draft.isChanged, isFalse);
      expect(repository.commands, isEmpty);
    });
  });

  group('передача права ошибки общей поверхности', () {
    test('освобождение сессии без renderer передаёт непредъявленное право общей поверхности ровно один раз', () async {
      final session = await _failedFullDraftSession(
        const IntentionUnavailableFailure(),
      );
      final surface = _AppSurface(session.coordinator);
      final claim = session.state.failurePresentation!;
      await _settle(session.container);
      expect(surface.presented, isEmpty);

      session.release();
      await _settle(session.container);

      expect(surface.tokens, [same(claim.token)]);
      expect(session.coordinator.claimInitiatorFailure(claim.token), isNull);
      expect(session.repository.commands, hasLength(1));
    });

    test('немедленное закрытие неизменённой сессии передаёт право её отказа общей поверхности', () async {
      final repository = ControlledCatalogRepository();
      final container = _container(repository);
      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final surface = _AppSurface(coordinator);
      final provider = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final editor = container.read(provider.notifier)..submit();
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
      await _deliverEvents(container);
      final claim = container.read(provider).failurePresentation!;
      expect(container.read(provider).draft.isChanged, isFalse);

      expect(
        editor.requestClose(),
        isA<IntentionCreationClosedImmediately>().having(
          (decision) => decision.savingOnClose,
          'отправка',
          IntentionCreationSavingOnClose.notStarted,
        ),
      );
      await _settle(container);

      expect(container.read(provider).failurePresentation, isNull);
      expect(surface.tokens, [same(claim.token)]);
      expect(coordinator.claimInitiatorFailure(claim.token), isNull);
    });

    test(
      'снятие отказа правкой передаёт право общей поверхности ровно один раз',
      () async {
        final corrections =
            <
              (
                String,
                IntentionFailure,
                void Function(IntentionEditorViewModel),
              )
            >[
              (
                'название',
                const IntentionTextInputValidationFailure(
                  IntentionTextValidationFailure(
                    field: IntentionTextField.title,
                    reason: IntentionTextValidationReason.tooLong,
                  ),
                ),
                (editor) => editor.changeTitle('Исправленное название'),
              ),
              (
                'описание',
                const IntentionTextInputValidationFailure(
                  IntentionTextValidationFailure(
                    field: IntentionTextField.description,
                    reason: IntentionTextValidationReason.tooLong,
                  ),
                ),
                (editor) => editor.changeDescription('Исправленное описание'),
              ),
              (
                'общая проверка',
                const IntentionGenericValidationFailure(),
                (editor) => editor.changeTitle('Исправленное название'),
              ),
              (
                'отсутствующий тег',
                IntentionCreationTagsMissingFailure([_tagId(1)]),
                (editor) => editor.removeTag(_tagId(1)),
              ),
            ];
        for (final (name, failure, correct) in corrections) {
          final session = await _failedFullDraftSession(failure);
          final surface = _AppSurface(session.coordinator);
          final claim = session.state.failurePresentation!;

          correct(session.editor);
          await _deliverEvents(session.container);

          expect(
            session.state.operation,
            isA<OperationIdle<Intention>>(),
            reason: name,
          );
          expect(session.state.failurePresentation, isNull, reason: name);
          expect(surface.tokens, [same(claim.token)], reason: name);

          // Дальнейшие правки, закрытие и освобождение право не повторяют.
          session.editor.changeTitle('Ещё одна правка');
          session.editor.requestClose();
          session.release();
          await _deliverEvents(session.container);
          expect(surface.presented, hasLength(1), reason: name);
          expect(
            session.coordinator.claimInitiatorFailure(claim.token),
            isNull,
            reason: name,
          );
          expect(session.repository.commands, hasLength(1), reason: name);
        }
      },
    );

    test('новая отправка после устранимого отказа передаёт прежнее право общей поверхности до результата повтора', () async {
      final session = await _failedFullDraftSession(
        const IntentionUnavailableFailure(),
      );
      final surface = _AppSurface(session.coordinator);
      final claim = session.state.failurePresentation!;

      session.editor.submit();
      await _settle(session.container);

      expect(session.state.operation, isA<OperationRunning<Intention>>());
      expect(session.state.failurePresentation, isNull);
      expect(surface.tokens, [same(claim.token)]);
      expect(session.coordinator.claimInitiatorFailure(claim.token), isNull);

      session.repository.completeCommand(1, _savedResult());
      await _settle(session.container);

      expect(session.repository.commands, hasLength(2));
      expect(surface.presented.map((claim) => claim.completion), [
        isA<IntentionCommandCompletion>().having(
          (completion) => completion.result,
          'отказ первой отправки',
          isA<ResultFailure<IntentionCommandSuccess>>(),
        ),
        isA<IntentionCommandCompletion>().having(
          (completion) => completion.result,
          'успех повтора',
          isA<ResultSuccess<IntentionCommandSuccess>>(),
        ),
      ]);
    });

    test('право, уже подтверждённое renderer, общая поверхность не получает ни при одном завершении публикации', () async {
      final transitions =
          <(String, IntentionFailure, void Function(_FailedSession))>[
            (
              'снятие отказа правкой',
              const IntentionTextInputValidationFailure(
                IntentionTextValidationFailure(
                  field: IntentionTextField.title,
                  reason: IntentionTextValidationReason.tooLong,
                ),
              ),
              (session) => session.editor.changeTitle('Исправленное название'),
            ),
            (
              'новая отправка',
              const IntentionUnavailableFailure(),
              (session) => session.editor.submit(),
            ),
            (
              'подтверждённое закрытие',
              const IntentionUnavailableFailure(),
              (session) => session.editor.resolveClose(
                _confirmationOf(session.editor.requestClose()),
                IntentionCreationCloseChoice.discardDraft,
              ),
            ),
            (
              'освобождение сессии',
              const IntentionUnavailableFailure(),
              (session) => session.release(),
            ),
          ];
      for (final (name, failure, transition) in transitions) {
        final session = await _failedFullDraftSession(failure);
        final surface = _AppSurface(session.coordinator);
        final claim = session.state.failurePresentation!;
        // Renderer подтверждает предъявление по кадру с видимым сообщением.
        session.coordinator.confirmPresentation(claim);

        transition(session);
        await _deliverEvents(session.container);

        expect(surface.presented, isEmpty, reason: name);
        expect(
          session.coordinator.claimInitiatorFailure(claim.token),
          isNull,
          reason: name,
        );
      }
    });

    test('право, освобождённое исчезнувшим renderer, общая поверхность получает один раз без повтора сессией', () async {
      final session = await _failedFullDraftSession(
        const IntentionUnavailableFailure(),
      );
      final surface = _AppSurface(session.coordinator);
      final claim = session.state.failurePresentation!;
      // Renderer исчезает до предъявления и освобождает право по своему
      // протоколу, пока сессия ещё публикует отказ.
      session.coordinator.releaseInitiatorClaim(claim);
      await _settle(session.container);
      expect(surface.tokens, [same(claim.token)]);

      expect(
        session.editor.resolveClose(
          _confirmationOf(session.editor.requestClose()),
          IntentionCreationCloseChoice.discardDraft,
        ),
        IntentionCreationCloseResolution.closed,
      );
      session.release();
      await _settle(session.container);

      expect(surface.tokens, [same(claim.token)]);
      expect(session.repository.commands, hasLength(1));
    });
  });
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

enum _Recovery {
  /// Правка устранила причину: возможна новая проверка всей команды.
  correctable,

  /// Причина устранима повтором: явная отправка остаётся доступной.
  retryable,

  /// Причина не устранена: отправка недоступна.
  blocked,
}

const _rawTitle = '  Название  ';
const _rawDescription = '  Описание буквально\n';

List<(String, IntentionFailure)> _failureCases() => [
  (
    'ошибка названия',
    const IntentionTextInputValidationFailure(
      IntentionTextValidationFailure(
        field: IntentionTextField.title,
        reason: IntentionTextValidationReason.tooLong,
      ),
    ),
  ),
  (
    'ошибка описания',
    const IntentionTextInputValidationFailure(
      IntentionTextValidationFailure(
        field: IntentionTextField.description,
        reason: IntentionTextValidationReason.tooLong,
      ),
    ),
  ),
  ('общая ошибка проверки', const IntentionGenericValidationFailure()),
  ('отсутствующий тег', IntentionCreationTagsMissingFailure([_tagId(1)])),
  ('недоступность', const IntentionUnavailableFailure()),
  ('конфликт', const IntentionConflictFailure()),
  (
    'блокирующие связи',
    IntentionHasBlockingRelationsFailure(testIntention().id),
  ),
  ('отсутствие намерения', const IntentionNotFoundFailure()),
  ('повреждение данных', const IntentionCorruptionFailure()),
  ('непредвиденная ошибка', const IntentionUnexpectedFailure()),
];

/// Сессия, отправка полного черновика которой отклонена [failure].
final class _FailedSession {
  const _FailedSession(
    this._owner, {
    required this.container,
    required this.repository,
    required this.provider,
  });

  final ProviderContainer container;
  final ControlledCatalogRepository repository;
  final IntentionEditorViewModelProvider provider;
  final ProviderSubscription<IntentionEditorState> _owner;

  IntentionEditorState get state => container.read(provider);

  IntentionEditorViewModel get editor => container.read(provider.notifier);

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  /// Владелец уходит без нового построения, и сессия освобождается.
  void release() => _owner.close();
}

Future<_FailedSession> _failedFullDraftSession(
  IntentionFailure failure, {
  List<Tag>? tags,
}) async {
  final repository = ControlledCatalogRepository();
  final container = _container(repository);
  final provider = intentionEditorViewModelProvider(IntentionCreationFormKey());
  final subscription = container.listen(provider, (_, _) {});
  addTearDown(subscription.close);
  final editor = container.read(provider.notifier)
    ..changeTitle(_rawTitle)
    ..changeDescription(_rawDescription)
    ..markFavorite()
    ..confirmReadiness();
  for (final tag in tags ?? [_tag(1, 'Дом'), _tag(2, 'Выходные')]) {
    editor.draftTagSet.add(tag);
  }
  editor.submit();
  repository.completeCommand(0, ResultFailure(failure));
  await _deliverEvents(container);
  return _FailedSession(
    subscription,
    container: container,
    repository: repository,
    provider: provider,
  );
}

/// Неснятый отказ остаётся у формы: сессия публикует его право, а ViewModel
/// его не подтверждает и не передаёт общей поверхности.
void _expectClaimKeptByForm(
  _FailedSession session,
  _AppSurface surface,
  GraphInitiatorPresentationClaim claim, {
  required String reason,
}) {
  expect(session.state.failurePresentation, same(claim), reason: reason);
  expect(
    session.coordinator.claimInitiatorFailure(claim.token),
    same(claim),
    reason: reason,
  );
  expect(surface.presented, isEmpty, reason: reason);
}

/// Общая поверхность приложения: получает права предъявления по очереди
/// и сразу подтверждает каждое предъявление.
final class _AppSurface {
  _AppSurface(this._coordinator)
    : _registration = _coordinator.registerAppPresentation() {
    addTearDown(_registration.release);
    _requestNext();
  }

  final GraphCommandCoordinator _coordinator;
  final GraphAppPresentationRegistration _registration;

  /// Предъявленные результаты в порядке выдачи.
  final presented = <GraphAppPresentationClaim>[];

  List<GraphOperationToken> get tokens => [
    for (final claim in presented) claim.token,
  ];

  void _requestNext() => unawaited(
    _registration.nextClaim().then((claim) {
      if (claim == null) {
        return;
      }
      presented.add(claim);
      _coordinator.confirmPresentation(claim);
      _requestNext();
    }),
  );
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

Map<TagId, String> _tagNames(IntentionEditorState state) =>
    state.selectedTags.map((id, tag) => MapEntry(id, tag.name.value));

IntentionDraftTagStatus? _tagStatus(IntentionEditorState state, int number) =>
    state.selectedTags[_tagId(number)]?.status;

Matcher _readFailed<F extends TagReadFailure>({required bool canRetry}) =>
    isA<IntentionDraftTagReadFailed>()
        .having((status) => status.failure, 'отказ чтения', isA<F>())
        .having((status) => status.canRetry, 'повтор', canRetry);

/// Управляемый источник контракта `watchTag`: каждое наблюдение — отдельный
/// поток, для которого видны освобождение подписки и её callbacks.
final class _TagWatches {
  final _watches = <_TagWatch>[];

  /// Теги, наблюдение которых отказывает синхронно при подписке.
  final failingIds = <TagId>{};

  int get count => _watches.length;

  Stream<TagReadResult> watch(TagId id) {
    if (failingIds.contains(id)) {
      throw StateError('SQL и личные данные');
    }
    final watch = _TagWatch(id);
    _watches.add(watch);
    return watch._stream;
  }

  /// Наблюдения тега [id] в порядке запроса.
  List<_TagWatch> of(TagId id) => [
    for (final watch in _watches)
      if (watch.id == id) watch,
  ];

  _TagWatch single(TagId id) => of(id).single;
}

final class _TagWatch {
  _TagWatch(this.id) {
    _controller = StreamController<TagReadResult>(
      onCancel: () => _isReleased = !_isEndedBySource,
    );
  }

  final TagId id;
  late final StreamController<TagReadResult> _controller;
  void Function(TagReadResult)? _onData;
  void Function()? _onDone;
  bool _isEndedBySource = false;
  bool _isReleased = false;

  /// Подписку отменил наблюдатель, а не источник.
  bool get isReleased => _isReleased;

  Stream<TagReadResult> get _stream => _CapturingTagStream(this);

  void observe(Tag? tag, {required int revision}) =>
      _controller.add(_snapshot(tag, revision));

  void fail(TagReadFailure failure) => _controller.add(TagReadError(failure));

  void throwError() => _controller.addError(StateError('SQL и личные данные'));

  void end() {
    _isEndedBySource = true;
    unawaited(_controller.close());
  }

  /// Доставляет ответ, поставленный в очередь до освобождения подписки.
  void deliverLate(Tag? tag, {required int revision}) =>
      _onData!(_snapshot(tag, revision));

  void endLate() => _onDone!();

  TagReadResult _snapshot(Tag? tag, int revision) => TagReadSuccess(
    GraphSnapshot(value: tag, revision: TestCatalogRevision(revision)),
  );
}

final class _CapturingTagStream extends Stream<TagReadResult> {
  _CapturingTagStream(this._watch);

  final _TagWatch _watch;

  @override
  StreamSubscription<TagReadResult> listen(
    void Function(TagReadResult)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _watch
      .._onData = onData
      .._onDone = onDone;
    return _watch._controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
