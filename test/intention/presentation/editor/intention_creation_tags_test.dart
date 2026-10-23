import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
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
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/quick_creation.dart';
import '../catalog/catalog_test_support.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/tag_positions.dart';

/// Показ актуальности и ручного порядка выбранных тегов в панели создания и
/// отказ создания из-за удалённых тегов.
///
/// Сценарии идут на английском; русские состояния тегов проверяет
/// сценарий доступности.
///
/// Наблюдение каждого выбранного тега управляется тестом, поэтому проверки
/// задают загрузку, переименование, перестановку и отказ чтения. Теги
/// добавляются через контракт набора сессии, как это делает общий выбор.
void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('теги черновика показывают точку и кольцо перед названиями', (
    tester,
  ) async {
    final observations = _TagObservations();
    final sessions = _EditorSessions();
    final repository = ControlledCatalogRepository()
      ..tagObservations = observations.watch;
    await _openEditor(tester, repository, observers: [sessions]);
    sessions.notifier(tester).draftTagSet
      ..add(_tag(1, 'Дом', color: TagColor.blue))
      ..add(_tag(2, 'Работа'));
    await tester.pumpAndSettle();

    for (final (number, color, style) in [
      (1, DoableColors.light.tagBlue, PaintingStyle.fill),
      (2, DoableColors.light.grip, PaintingStyle.stroke),
    ]) {
      final name = find.byKey(_chipNameKey(number));
      final dot = find.descendant(
        of: find.byKey(_chip(number)),
        matching: find.byType(TagDot),
      );
      expect(dot, findsOneWidget);
      expect(tester.getSize(dot), const Size.square(8));
      expect(tester.getTopRight(dot).dx, lessThan(tester.getTopLeft(name).dx));
      expect(
        tester.renderObject(dot),
        paints..circle(color: color, style: style),
      );
      expect(
        tester.widget<Text>(name).style?.color,
        Theme.of(tester.element(name)).textTheme.labelLarge?.color,
      );
    }
  });

  testWidgets(
    'пока наблюдение не ответило, тег показан с названием из выбора и '
    'доступным признаком проверки, а подтверждённое переименование меняет '
    'только название',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final (locale, checking) in [(const Locale('en'), 'Checking tag')]) {
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

  testWidgets(
    'выбранные теги идут в ручном порядке независимо от порядка добавления, '
    'а подтверждённая перестановка меняет только их показ',
    (tester) async {
      final observations = _TagObservations();
      final sessions = _EditorSessions();
      final repository = ControlledCatalogRepository()
        ..tagObservations = observations.watch;
      await _openEditor(tester, repository, observers: [sessions]);
      sessions.notifier(tester).draftTagSet
        ..add(_tag(3, 'Сад'))
        ..add(_tag(1, 'Дом'))
        ..add(_tag(2, 'Работа'));
      await tester.pumpAndSettle();

      expect(_chipOrder(tester, [1, 2, 3]), ['Дом', 'Работа', 'Сад']);

      // «Сад» переставлен в начало ручного порядка.
      observations.emit(
        _tagId(3),
        _tag(3, 'Сад', position: tagPositionAt(0)),
        revision: 1,
      );
      await tester.pumpAndSettle();

      expect(_chipOrder(tester, [1, 2, 3]), ['Сад', 'Дом', 'Работа']);
      expect(sessions.state(tester).draft.tagIds, [
        _tagId(3),
        _tagId(1),
        _tagId(2),
      ]);
      expect(repository.commands, isEmpty);
    },
  );

  testWidgets('устранимый отказ наблюдения показывает причину и предлагает '
      'доступный повтор, который заново наблюдает тег без изменения набора', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final (locale, failed, retry) in [
      (const Locale('en'), "Couldn't check tag", 'Check tag Дом again'),
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

      await tester.tap(find.byKey(_chipRetry(1)));
      await tester.pumpAndSettle();

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
  });

  for (final (failure, en) in [
    (
      const TagReadCorruptionFailure() as TagReadFailure,
      'Tag data is corrupted',
    ),
    (
      const TagReadUnexpectedFailure(),
      'Tag not checked due to an unexpected error',
    ),
  ]) {
    testWidgets(
      'неповторяемый отказ наблюдения ${failure.runtimeType} показывает '
      'причину без повтора и сохраняет явное снятие',
      (tester) async {
        final semantics = tester.ensureSemantics();
        for (final (locale, message) in [(const Locale('en'), en)]) {
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
    'отказ создания из-за удалённых тегов объясняет удаление, убирает именно '
    'их из набора и снова разрешает только явную отправку',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final observations = _TagObservations();
      final sessions = _EditorSessions();
      final repository = ControlledCatalogRepository()
        ..tagObservations = observations.watch;
      await _openEditor(tester, repository, observers: [sessions]);
      final tagSet = sessions.notifier(tester).draftTagSet;
      for (final (number, name) in [(1, 'Дом'), (2, 'Работа'), (3, 'Сад')]) {
        tagSet.add(_tag(number, name));
        await tester.pumpAndSettle();
        // Наблюдение ещё видит теги: отсутствие подтверждает только проверка
        // при сохранении.
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
        isSemantics(
          label:
              '2 selected tags were deleted from the catalog and removed from '
              'the draft. Save the intention again.',
          isLiveRegion: true,
        ),
      );
      expect(find.byKey(_chip(1)), findsNothing);
      expect(_chipName(tester, 2), 'Работа');
      expect(find.byKey(_chip(3)), findsNothing);
      expect(sessions.state(tester).draft.tagIds, [_tagId(2)]);
      expect(find.text('Save'), findsOneWidget);
      expect(_submitButton(tester).onPressed, isNotNull);
      // Отказ не повторяет сохранение сам.
      expect(repository.commands, hasLength(1));

      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();

      expect(repository.commands, hasLength(2));
      expect(
        repository.commands.last,
        isA<CreateIntention>()
            .having((command) => command.title, 'название', 'Намерение')
            .having((command) => command.tagIds, 'теги', [_tagId(2)]),
      );
      expect(repository.tagCommands, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'состояния выбранных тегов, их снятие и повтор проверки доступны',
    (tester) async {
      final semantics = tester.ensureSemantics();

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
        ..emit(_tagId(1), _tag(1, longName.trim()), revision: 1)
        ..fail(_tagId(2), const TagReadUnavailableFailure())
        ..fail(_tagId(3), const TagReadCorruptionFailure());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(_chipStatus(1)), findsNothing);
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

/// Показанные названия выбранных тегов [numbers] в порядке чтения.
List<String?> _chipOrder(WidgetTester tester, List<int> numbers) {
  final chips =
      [
        for (final number in numbers)
          (number: number, at: tester.getTopLeft(find.byKey(_chip(number)))),
      ]..sort(
        (a, b) => a.at.dy == b.at.dy
            ? a.at.dx.compareTo(b.at.dx)
            : a.at.dy.compareTo(b.at.dy),
      );
  return [for (final chip in chips) _chipName(tester, chip.number)];
}

/// Показанное название выбранного тега.
String? _chipName(WidgetTester tester, int number) =>
    tester.widget<Text>(find.byKey(_chipNameKey(number))).data;

/// Видимый текст состояния выбранного тега.
String? _statusText(WidgetTester tester, int number) =>
    tester.widget<Text>(find.byKey(_chipStatus(number))).data;

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_submit));

Tag _tag(int number, String name, {TagColor? color, TagPosition? position}) =>
    Tag(
      id: _tagId(number),
      name: TagName.fromInput(name),
      color: color,
      position: position ?? tagPositionAt(number),
    );

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
        theme: doableTheme(Brightness.light),
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
