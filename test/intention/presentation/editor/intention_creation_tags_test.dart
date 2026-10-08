import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/quick_creation.dart';
import '../catalog/catalog_test_support.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

/// Показ актуальности выбранных тегов в панели создания и исправление их
/// отсутствия.
///
/// Наблюдение каждого выбранного тега управляется тестом, поэтому проверки
/// задают загрузку, переименование, отсутствие и отказ чтения. Теги
/// добавляются через контракт набора сессии, как это делает общий выбор.
void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'пока наблюдение не ответило, тег показан с названием из выбора и '
    'доступным признаком проверки, а подтверждённое переименование меняет '
    'только название',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final (locale, checking) in [
        (const Locale('en'), 'Checking tag'),
        (const Locale('ru'), 'Проверяем тег'),
      ]) {
        final observations = _TagObservations();
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository()
          ..tagObservations = observations.watch;
        await _openEditor(
          tester,
          repository,
          locale: locale,
          observers: [sessions],
        );

        sessions.notifier(tester).draftTagSet.add(_tag(1, 'Дом'));
        await tester.pumpAndSettle();

        expect(_chipName(tester, 1), 'Дом');
        expect(find.byKey(_chipLoading(1)), findsOneWidget);
        expect(find.byKey(_chipStatus(1)), findsNothing);
        expect(find.byKey(_chipRetry(1)), findsNothing);
        expect(
          tester.getSemantics(find.byKey(_chip(1))),
          isSemantics(label: 'Дом\n$checking'),
        );
        expect(
          tester.widget<IconButton>(find.byKey(_chipRemove(1))).onPressed,
          isNotNull,
        );

        observations.emit(_tagId(1), _tag(1, 'Быт'), revision: 1);
        await tester.pumpAndSettle();

        expect(_chipName(tester, 1), 'Быт');
        expect(find.byKey(_chipLoading(1)), findsNothing);
        expect(find.byKey(_chipStatus(1)), findsNothing);
        expect(
          tester.getSemantics(find.byKey(_chip(1))),
          isSemantics(label: 'Быт'),
        );
        expect(sessions.state(tester).draft.tagIds, [_tagId(1)]);
        expect(repository.commands, isEmpty);
        expect(repository.tagCommands, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      semantics.dispose();
    },
  );

  testWidgets('подтверждённое отсутствие сохраняет тег с последним названием, '
      'признаком удаления и явным снятием, а одноимённый новый тег его не '
      'заменяет', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (locale, deleted, remove) in [
      (const Locale('en'), 'Tag deleted', 'Remove tag Дом from draft'),
      (const Locale('ru'), 'Тег удалён', 'Убрать тег «Дом» из черновика'),
    ]) {
      final observations = _TagObservations();
      final sessions = _EditorSessions();
      final repository = ControlledCatalogRepository()
        ..tagObservations = observations.watch;
      await _openEditor(
        tester,
        repository,
        locale: locale,
        observers: [sessions],
      );
      final tagSet = sessions.notifier(tester).draftTagSet;

      tagSet.add(_tag(1, 'Дом'));
      await tester.pumpAndSettle();
      observations.emit(_tagId(1), _tag(1, 'Дом'), revision: 1);
      await tester.pumpAndSettle();
      observations.emit(_tagId(1), null, revision: 2);
      await tester.pumpAndSettle();

      expect(_chipName(tester, 1), 'Дом');
      expect(_statusText(tester, 1), deleted);
      expect(find.byKey(_chipRetry(1)), findsNothing);
      expect(
        tester.getSemantics(find.byKey(_chip(1))),
        isSemantics(label: 'Дом\n$deleted'),
      );
      expect(
        tester.getSemantics(find.byKey(_chipRemove(1))),
        isSemantics(
          tooltip: remove,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(sessions.state(tester).draft.tagIds, [_tagId(1)]);

      // Одноимённый тег с другим идентификатором — отдельный выбор.
      tagSet.add(_tag(2, 'Дом'));
      await tester.pumpAndSettle();
      observations.emit(_tagId(2), _tag(2, 'Дом'), revision: 3);
      await tester.pumpAndSettle();

      expect(sessions.state(tester).draft.tagIds, [_tagId(1), _tagId(2)]);
      expect(_chipName(tester, 1), 'Дом');
      expect(_statusText(tester, 1), deleted);
      expect(_chipName(tester, 2), 'Дом');
      expect(find.byKey(_chipStatus(2)), findsNothing);

      // Удалённый тег уходит из черновика только явным снятием.
      await tester.tap(find.byKey(_chipRemove(1)));
      await tester.pumpAndSettle();

      expect(sessions.state(tester).draft.tagIds, [_tagId(2)]);
      expect(find.byKey(_chip(1)), findsNothing);
      expect(_chipName(tester, 2), 'Дом');
      expect(repository.commands, isEmpty);
      expect(repository.tagCommands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    semantics.dispose();
  });

  testWidgets(
    'устранимый отказ наблюдения не выдаётся за удаление и предлагает '
    'доступный повтор, который заново наблюдает тег без изменения набора',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final (locale, failed, retry, deleted) in [
        (
          const Locale('en'),
          "Couldn't check tag",
          'Check tag Дом again',
          'Tag deleted',
        ),
        (
          const Locale('ru'),
          'Не удалось проверить тег',
          'Повторить проверку тега «Дом»',
          'Тег удалён',
        ),
      ]) {
        final observations = _TagObservations();
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository()
          ..tagObservations = observations.watch;
        await _openEditor(
          tester,
          repository,
          locale: locale,
          observers: [sessions],
        );

        sessions.notifier(tester).draftTagSet.add(_tag(1, 'Дом'));
        await tester.pumpAndSettle();
        observations.fail(_tagId(1), const TagReadUnavailableFailure());
        await tester.pumpAndSettle();

        expect(_chipName(tester, 1), 'Дом');
        expect(_statusText(tester, 1), failed);
        expect(find.text(deleted), findsNothing);
        expect(
          tester.getSemantics(find.byKey(_chip(1))),
          isSemantics(label: 'Дом\n$failed'),
        );
        expect(
          tester.getSemantics(find.byKey(_chipRetry(1))),
          isSemantics(
            tooltip: retry,
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        expect(observations.count(_tagId(1)), 1);

        await tester.tap(find.byKey(_chipRetry(1)));
        await tester.pumpAndSettle();

        expect(observations.count(_tagId(1)), 2);
        expect(find.byKey(_chipLoading(1)), findsOneWidget);
        expect(find.byKey(_chipRetry(1)), findsNothing);

        observations.emit(_tagId(1), _tag(1, 'Дом'), revision: 1);
        await tester.pumpAndSettle();

        expect(find.byKey(_chipStatus(1)), findsNothing);
        expect(find.byKey(_chipLoading(1)), findsNothing);
        expect(_chipName(tester, 1), 'Дом');
        expect(sessions.state(tester).draft.tagIds, [_tagId(1)]);
        expect(repository.commands, isEmpty);
        expect(repository.tagCommands, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      semantics.dispose();
    },
  );

  for (final (failure, en, ru) in [
    (
      const TagReadCorruptionFailure() as TagReadFailure,
      'Tag data is corrupted',
      'Данные тега повреждены',
    ),
    (
      const TagReadUnexpectedFailure(),
      'Tag not checked due to an unexpected error',
      'Тег не проверен из-за непредвиденной ошибки',
    ),
  ]) {
    testWidgets(
      'неповторяемый отказ наблюдения ${failure.runtimeType} показывает '
      'причину без повтора и удаления и сохраняет явное снятие',
      (tester) async {
        final semantics = tester.ensureSemantics();
        for (final (locale, message) in [
          (const Locale('en'), en),
          (const Locale('ru'), ru),
        ]) {
          final observations = _TagObservations();
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository()
            ..tagObservations = observations.watch;
          await _openEditor(
            tester,
            repository,
            locale: locale,
            observers: [sessions],
          );

          sessions.notifier(tester).draftTagSet.add(_tag(1, 'Дом'));
          await tester.pumpAndSettle();
          observations.fail(_tagId(1), failure);
          await tester.pumpAndSettle();

          expect(_chipName(tester, 1), 'Дом');
          expect(_statusText(tester, 1), message);
          expect(
            tester.getSemantics(find.byKey(_chip(1))),
            isSemantics(label: 'Дом\n$message'),
          );
          expect(find.byKey(_chipRetry(1)), findsNothing);
          expect(observations.count(_tagId(1)), 1);
          expect(sessions.state(tester).draft.tagIds, [_tagId(1)]);

          await tester.tap(find.byKey(_chipRemove(1)));
          await tester.pumpAndSettle();

          expect(sessions.state(tester).draft.tagIds, isEmpty);
          expect(find.byKey(_chip(1)), findsNothing);
          expect(repository.commands, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'отказ создания из-за удалённых тегов объясняет исправление и отмечает '
    'именно их, сохраняет набор до явной правки, а исправление не отправляет '
    'сохранение повторно',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final (locale, explanation, fix, deleted, save) in [
        (
          const Locale('en'),
          '2 selected tags were deleted from the catalog. Remove them from '
              'the draft to save the intention.',
          'Remove deleted tags',
          'Tag deleted',
          'Save',
        ),
        (
          const Locale('ru'),
          'Удалено из каталога выбранных тегов: 2. Уберите их из черновика, '
              'чтобы сохранить намерение.',
          'Убрать удалённые теги',
          'Тег удалён',
          'Сохранить',
        ),
      ]) {
        final observations = _TagObservations();
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository()
          ..tagObservations = observations.watch;
        await _openEditor(
          tester,
          repository,
          locale: locale,
          observers: [sessions],
        );
        final tagSet = sessions.notifier(tester).draftTagSet;
        for (final (number, name) in [(1, 'Дом'), (2, 'Работа'), (3, 'Сад')]) {
          tagSet.add(_tag(number, name));
          await tester.pumpAndSettle();
          // Наблюдение ещё видит теги: отсутствие подтверждает только
          // проверка при сохранении.
          observations.emit(_tagId(number), _tag(number, name), revision: 1);
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byKey(_title), 'Намерение');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(_submit));
        await tester.pumpAndSettle();
        expect(repository.commands, hasLength(1));
        repository.completeCommand(
          0,
          ResultFailure(
            IntentionCreationTagsMissingFailure([_tagId(1), _tagId(3)]),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSemantics(find.byKey(_failure)),
          isSemantics(label: explanation, isLiveRegion: true),
        );
        expect(_statusText(tester, 1), deleted);
        expect(find.byKey(_chipStatus(2)), findsNothing);
        expect(_statusText(tester, 3), deleted);
        expect(sessions.state(tester).draft.tagIds, [
          _tagId(1),
          _tagId(2),
          _tagId(3),
        ]);
        expect(_submitButton(tester).onPressed, isNull);
        expect(
          tester.getSemantics(find.byKey(_removeMissing)),
          isSemantics(
            label: fix,
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );

        // Правка, которая не снимает удалённые теги, отказ не снимает.
        await tester.enterText(find.byKey(_title), 'Другое намерение');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_chipRemove(2)));
        await tester.pumpAndSettle();
        expect(sessions.state(tester).draft.tagIds, [_tagId(1), _tagId(3)]);
        expect(find.byKey(_failure), findsOneWidget);
        expect(_submitButton(tester).onPressed, isNull);

        await tester.tap(find.byKey(_removeMissing));
        await tester.pumpAndSettle();

        expect(sessions.state(tester).draft.tagIds, isEmpty);
        expect(find.byKey(_failure), findsNothing);
        expect(find.byKey(_removeMissing), findsNothing);
        expect(find.text(save), findsOneWidget);
        expect(_submitButton(tester).onPressed, isNotNull);
        await tester.pumpAndSettle();
        expect(repository.commands, hasLength(1));
        expect(repository.tagCommands, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'после явного снятия каждого удалённого тега сохранение отправляет '
    'только оставшийся набор и только по нажатию',
    (tester) async {
      final observations = _TagObservations();
      final sessions = _EditorSessions();
      final repository = ControlledCatalogRepository()
        ..tagObservations = observations.watch;
      await _openEditor(tester, repository, observers: [sessions]);
      final tagSet = sessions.notifier(tester).draftTagSet;
      tagSet
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Работа'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_title), 'Намерение');
      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();
      repository.completeCommand(
        0,
        ResultFailure(IntentionCreationTagsMissingFailure([_tagId(1)])),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(_failure)),
        isSemantics(
          label:
              'A selected tag was deleted from the catalog. Remove it from '
              'the draft to save the intention.',
        ),
      );
      expect(find.text('Remove deleted tag'), findsOneWidget);
      expect(_statusText(tester, 1), 'Tag deleted');

      await tester.tap(find.byKey(_chipRemove(1)));
      await tester.pumpAndSettle();

      expect(find.byKey(_failure), findsNothing);
      expect(repository.commands, hasLength(1));

      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();

      expect(repository.commands, hasLength(2));
      expect(
        repository.commands.last,
        isA<CreateIntention>().having((command) => command.tagIds, 'теги', [
          _tagId(2),
        ]),
      );
    },
  );

  testWidgets(
    'состояния выбранных тегов, их снятие, повтор проверки и исправление '
    'удалённых тегов доступны при увеличенном тексте',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final observations = _TagObservations();
      final sessions = _EditorSessions();
      final repository = ControlledCatalogRepository()
        ..tagObservations = observations.watch;
      await _openEditor(
        tester,
        repository,
        locale: const Locale('ru'),
        observers: [sessions],
      );
      final tagSet = sessions.notifier(tester).draftTagSet;
      final longName = 'Очень длинное название тега ' * 4;
      tagSet
        ..add(_tag(1, longName.trim()))
        ..add(_tag(2, 'Работа'))
        ..add(_tag(3, 'Сад'))
        ..add(_tag(4, 'Дача'));
      await tester.pumpAndSettle();
      observations
        ..emit(_tagId(1), null, revision: 1)
        ..fail(_tagId(2), const TagReadUnavailableFailure())
        ..fail(_tagId(3), const TagReadCorruptionFailure());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_title), 'Намерение');
      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();
      repository.completeCommand(
        0,
        ResultFailure(IntentionCreationTagsMissingFailure([_tagId(1)])),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_statusText(tester, 1), 'Тег удалён');
      expect(_statusText(tester, 2), 'Не удалось проверить тег');
      expect(_statusText(tester, 3), 'Данные тега повреждены');
      expect(find.byKey(_chipLoading(4)), findsOneWidget);
      // Длинная форма прокручивается внутри панели: каждое действие
      // доводится до видимости и сохраняет размер и доступную семантику.
      for (final target in [
        _chipRemove(1),
        _chipRetry(2),
        _chipRemove(2),
        _chipRemove(3),
        _chipRemove(4),
        _removeMissing,
      ]) {
        await tester.ensureVisible(find.byKey(target));
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byKey(target));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(
          tester.getSemantics(find.byKey(target)),
          isSemantics(
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
          ),
        );
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    },
  );
}

const _title = ValueKey('intention-editor-title');
const _submit = ValueKey('intention-editor-submit');
const _failure = ValueKey('intention-editor-failure');
const _removeMissing = ValueKey('intention-editor-remove-missing-tags');

ValueKey<String> _chip(int number) =>
    ValueKey('intention-editor-tag-${_tagId(number).toCanonicalString()}');

ValueKey<String> _chipRemove(int number) => ValueKey(
  'intention-editor-tag-remove-${_tagId(number).toCanonicalString()}',
);

ValueKey<String> _chipRetry(int number) => ValueKey(
  'intention-editor-tag-retry-${_tagId(number).toCanonicalString()}',
);

ValueKey<String> _chipNameKey(int number) =>
    ValueKey('intention-editor-tag-name-${_tagId(number).toCanonicalString()}');

ValueKey<String> _chipStatus(int number) => ValueKey(
  'intention-editor-tag-status-${_tagId(number).toCanonicalString()}',
);

ValueKey<String> _chipLoading(int number) => ValueKey(
  'intention-editor-tag-loading-${_tagId(number).toCanonicalString()}',
);

/// Показанное название выбранного тега.
String? _chipName(WidgetTester tester, int number) =>
    tester.widget<Text>(find.byKey(_chipNameKey(number))).data;

/// Видимый текст состояния выбранного тега.
String? _statusText(WidgetTester tester, int number) =>
    tester.widget<Text>(find.byKey(_chipStatus(number))).data;

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_submit));

Tag _tag(int number, String name) =>
    Tag(id: _tagId(number), name: TagName.fromInput(name));

TagId _tagId(int number) => switch (TagId.decode(
  '018f47c2-6b7d-7abc-8def-${number.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный UUID тега.'),
};

/// Управляемые наблюдения выбранных тегов: каждое обращение к `watchTag`
/// открывает новый поток, а ответы получает последний поток тега.
final class _TagObservations {
  final _streams = <TagId, List<StreamController<TagReadResult>>>{};

  Stream<TagReadResult> watch(TagId id) {
    final controller = StreamController<TagReadResult>();
    (_streams[id] ??= []).add(controller);
    return controller.stream;
  }

  /// Число наблюдений тега [id], открытых сессией.
  int count(TagId id) => _streams[id]?.length ?? 0;

  /// Подтверждает тег [tag] или, если он null, отсутствие тега [id].
  void emit(TagId id, Tag? tag, {required int revision}) =>
      _streams[id]!.last.add(
        TagReadSuccess(
          GraphSnapshot(value: tag, revision: TestCatalogRevision(revision)),
        ),
      );

  void fail(TagId id, TagReadFailure failure) =>
      _streams[id]!.last.add(TagReadError(failure));
}

/// Последняя построенная сессия формы создания.
final class _EditorSessions extends ProviderObserver {
  IntentionEditorViewModelProvider? _latest;

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    if (context.provider case final IntentionEditorViewModelProvider provider) {
      _latest = provider;
    }
  }

  IntentionEditorViewModel notifier(WidgetTester tester) =>
      _container(tester).read(_latest!.notifier);

  IntentionEditorState state(WidgetTester tester) =>
      _container(tester).read(_latest!);

  ProviderContainer _container(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(IntentionEditorPage)),
      );
}

/// Открывает панель через быстрое создание над пустым каталогом намерений.
Future<void> _openEditor(
  WidgetTester tester,
  ControlledCatalogRepository repository, {
  Locale locale = const Locale('en'),
  List<ProviderObserver> observers = const [],
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      observers: observers,
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openIntentionGraph(tester);
  repository.complete(
    0,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const TestCatalogRevision(0),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openQuickCreation(
    tester,
    QuickCreationMode.intention,
    openedPage: find.byType(IntentionEditorPage),
  );
}
