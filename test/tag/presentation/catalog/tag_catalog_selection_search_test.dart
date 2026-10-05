import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_assignment_changed.dart';

void main() {
  testWidgets(
    'поиск сохраняет явное назначение скрытого тега тому же намерению',
    (tester) async {
      final h = await _show(tester);
      await tester.tap(_row(h.home));
      await tester.enterText(_search, 'работ');
      await tester.pump();
      expect(_row(h.home), findsNothing);
      expect(_row(h.work), findsOneWidget);
      expect(find.text('Дом'), findsOneWidget);
      expect(h.repository.commands, isEmpty);
      expect(h.repository.reads, hasLength(1));

      await tester.tap(_assign);
      await tester.pump();
      final command = h.repository.commands.single as AssignTag;
      expect(command.tagId, h.home.id);
      expect(command.intentionId, h.intention.value);
      h.repository.command.complete(
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: const TagCatalogTestRevision(2),
            value: testTagAssignmentChanged(
              TagAssignmentChangedChange(
                revision: const TagCatalogTestRevision(2),
                assignment: command.assignment,
                state: TagAssignmentState.assigned,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      h.repository.complete(
        [h.home, h.work],
        revision: 2,
        assignedIds: {h.home.id},
      );
      await tester.pump();
      expect(tester.widget<TextField>(_search).controller!.text, 'работ');
      expect(_row(h.home), findsNothing);
      expect(find.text('Дом'), findsOneWidget);
      expect(find.text('Назначен'), findsOneWidget);
      expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
      expect(h.repository.commands, hasLength(1));
    },
  );

  testWidgets('отказ назначения сохраняет скрытый выбор для явного повтора', (
    tester,
  ) async {
    final h = await _show(tester);
    await tester.tap(_row(h.home));
    await tester.enterText(_search, 'нет совпадений');
    await tester.pump();
    expect(find.text('Теги не найдены'), findsOneWidget);
    await tester.tap(_assign);
    await tester.pump();
    h.repository.command.complete(
      const TagCommandFailed(TagUnavailableFailure()),
    );
    await tester.pump();
    expect(find.text('Дом'), findsOneWidget);
    expect(
      tester.widget<TextField>(_search).controller!.text,
      'нет совпадений',
    );
    expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);
    expect(h.repository.commands, hasLength(1));
    expect(h.repository.reads, hasLength(1));

    await tester.tap(find.byTooltip('Очистить поиск тегов'));
    await tester.pump();
    expect(tester.widget<Semantics>(_row(h.home)).properties.selected, isTrue);
    expect(h.repository.commands, hasLength(1));
  });

  testWidgets('выбор из редактора подтверждает пару до явного назначения', (
    tester,
  ) async {
    final editor = Completer<Tag?>();
    final h = await _show(tester, onOpenEditor: (_) => editor.future);
    final created = _tag(52, 'Из редактора');
    await tester.enterText(_search, 'работ');
    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    editor.complete(created);
    await tester.pump();
    h.repository.observe(created);
    h.repository.statusReads.single.complete(
      const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
    );
    await tester.pump();
    expect(h.repository.statusQueries.single, (created.id, h.intention.value));
    expect(find.text('Из редактора'), findsOneWidget);
    expect(_row(created), findsNothing);
    expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
    expect(h.repository.commands, isEmpty);
    expect(tester.widget<TextField>(_search).controller!.text, 'работ');

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
    h.repository.statusReads.last.complete(
      const TagAssignmentStatusSuccess(
        GraphSnapshot(value: false, revision: TagCatalogTestRevision()),
      ),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);
    expect(h.repository.reads, hasLength(1));
    expect(h.repository.commands, isEmpty);
  });

  testWidgets('возврат редактора прежнего открытия не меняет новый выбор', (
    tester,
  ) async {
    final editor = Completer<Tag?>();
    final h = await _show(tester, onOpenEditor: (_) => editor.future);
    final firstIntention = h.intention.value;
    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    h.intention.value = _intentionId(200);
    await tester.pump();
    h.repository.complete([h.home, h.work], assignedIds: {});
    await tester.pump();
    h.intention.value = firstIntention;
    await tester.pump();
    h.repository.complete([h.home, h.work], assignedIds: {});
    await tester.pump();
    await tester.enterText(_search, 'дом');
    await tester.tap(_row(h.home));
    await tester.pump();

    editor.complete(_tag(52, 'Прежний редактор'));
    await tester.pump();
    expect(tester.widget<Semantics>(_row(h.home)).properties.selected, isTrue);
    expect(h.repository.statusReads, isEmpty);
    expect(h.repository.commands, isEmpty);
    expect(tester.widget<TextField>(_search).controller!.text, 'дом');
  });

  testWidgets('команда прежнего намерения не блокирует выбор нового', (
    tester,
  ) async {
    final h = await _show(tester);
    final firstIntention = h.intention.value;
    await tester.tap(_row(h.home));
    await tester.pump();
    await tester.tap(_assign);
    await tester.pump();
    h.intention.value = _intentionId(200);
    await tester.pump();
    h.repository.complete([h.home, h.work], assignedIds: {});
    await tester.pump();
    await tester.tap(_row(h.work));
    await tester.pump();
    expect(tester.widget<Semantics>(_row(h.work)).properties.selected, isTrue);

    h.repository.command.complete(
      TagCommandFailed(TagIntentionNotFoundFailure(firstIntention)),
    );
    await tester.pump();
    expect(tester.widget<Semantics>(_row(h.work)).properties.selected, isTrue);
    expect(
      find.byKey(const ValueKey('tag-catalog-assign-failure')),
      findsNothing,
    );
    expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);
    expect(h.repository.commands, hasLength(1));
  });

  testWidgets(
    'черновик: поиск скрывает включённый тег и кандидата, не меняя набор и не подмешивая кандидата в совпадения',
    (tester) async {
      final d = await _showDraft(tester);
      final draft = d.tagSet.value;
      await tester.tap(_row(d.home));
      await tester.pump();
      await tester.tap(_add);
      await tester.pump();
      expect(draft.current.tagIds, [d.home.id]);

      await tester.enterText(_search, 'работ');
      await tester.pump();
      expect(_row(d.home), findsNothing);
      expect(_row(d.work), findsOneWidget);
      expect(_hiddenText('Дом'), findsOneWidget);
      expect(_hiddenText('В черновике'), findsOneWidget);
      expect(tester.widget<FilledButton>(_add).onPressed, isNull);
      expect(draft.current.tagIds, [d.home.id]);

      await tester.tap(_row(d.work));
      await tester.pump();
      expect(_hidden, findsNothing);
      expect(draft.current.tagIds, [d.home.id]);

      // Отсутствие совпадений не подмешивает кандидата в список: он виден
      // только у явного действия и добавляется лишь по нему.
      await tester.enterText(_search, 'нет совпадений');
      await tester.pump();
      expect(find.text('Теги не найдены'), findsOneWidget);
      expect(_row(d.work), findsNothing);
      expect(_hiddenText('Работа'), findsOneWidget);
      expect(_hiddenText('Можно добавить'), findsOneWidget);
      expect(draft.current.tagIds, [d.home.id]);

      await tester.tap(_add);
      await tester.pump();
      expect(draft.current.tagIds, [d.home.id, d.work.id]);
      expect(_hiddenText('В черновике'), findsOneWidget);
      expect(find.text('Теги не найдены'), findsOneWidget);
      expect(
        tester.widget<TextField>(_search).controller!.text,
        'нет совпадений',
      );

      await tester.tap(find.byTooltip('Очистить поиск тегов'));
      await tester.pump();
      expect(_status(d.home, 'В черновике'), findsOneWidget);
      expect(_status(d.work, 'В черновике'), findsOneWidget);
      expect(
        tester.widget<Semantics>(_row(d.work)).properties.selected,
        isTrue,
      );
      expect(_hidden, findsNothing);
      expect(draft.current.tagIds, [d.home.id, d.work.id]);
      expect(d.repository.reads, hasLength(1));
      expect(d.repository.commands, isEmpty);
      expect(d.repository.statusQueries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'черновик: отмена редактора ничего не меняет, а возврат созданного тега после локальных правок выбирает его кандидатом без включения в набор',
    (tester) async {
      final editors = <Completer<Tag?>>[];
      final d = await _showDraft(
        tester,
        onOpenEditor: (_) => (editors..add(Completer())).last.future,
      );
      final draft = d.tagSet.value;
      final input = tester.widget<TextField>(_search).controller!;
      await tester.enterText(_search, 'дом');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
      editors.last.complete(null);
      await tester.pump();
      expect(input.text, 'дом');
      expect(_hidden, findsNothing);
      expect(draft.current.tagIds, isEmpty);

      await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
      await tester.pump();
      // Пока редактор открыт, набор меняется локально, а владелец выбора
      // перестраивает его с новым экземпляром контекста той же сессии.
      await tester.tap(_row(d.home));
      await tester.pump();
      await tester.tap(_add);
      await tester.pump();
      d.rebuild();
      await tester.pump();
      expect(draft.current.tagIds, [d.home.id]);
      expect(tester.widget<TextField>(_search).controller, same(input));
      expect(input.text, 'дом');

      final created = _tag(52, 'Домашнее');
      editors.last.complete(created);
      await tester.pump();
      d.repository.observe(created);
      await tester.pump();

      // Созданный тег ещё не вошёл в снимок каталога: он виден у явного
      // действия, но не подмешивается в совпадения поиска.
      expect(_hiddenText('Домашнее'), findsOneWidget);
      expect(_hiddenText('Можно добавить'), findsOneWidget);
      expect(_visibleNames(tester), ['Дом']);
      expect(tester.widget<FilledButton>(_add).onPressed, isNotNull);
      expect(draft.current.tagIds, [d.home.id]);
      expect(input.text, 'дом');
      expect(d.repository.reads, hasLength(1));
      expect(d.repository.commands, isEmpty);
      expect(d.repository.statusQueries, isEmpty);

      await tester.tap(_add);
      await tester.pump();
      expect(draft.current.tagIds, [d.home.id, created.id]);
      expect(_hiddenText('В черновике'), findsOneWidget);
      expect(d.repository.commands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'черновик: поздний возврат редактора прежнего открытия не меняет открытие другой сессии и новое открытие той же сессии',
    (tester) async {
      final editors = <Completer<Tag?>>[];
      final d = await _showDraft(
        tester,
        onOpenEditor: (_) => (editors..add(Completer())).last.future,
      );
      final first = d.tagSet.value;
      await tester.enterText(_search, 'дом');
      await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
      await tester.pump();

      final second = d.openSession();
      d.tagSet.value = second;
      await tester.pump();
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      d.repository.complete([d.home, d.work]);
      await tester.pump();
      await tester.tap(_row(d.work));
      await tester.pump();
      await tester.tap(_add);
      await tester.pump();
      await tester.enterText(_search, 'дом');
      await tester.pump();

      final stale = _tag(52, 'Прежний редактор');
      editors.first.complete(stale);
      await tester.pump();
      expect(_hiddenText('Работа'), findsOneWidget);
      expect(find.text('Прежний редактор'), findsNothing);
      expect(d.repository.observations.containsKey(stale.id), isFalse);
      expect(tester.widget<TextField>(_search).controller!.text, 'дом');
      expect(first.current.tagIds, isEmpty);
      expect(second.current.tagIds, [d.work.id]);

      // Закрытое открытие той же сессии не меняет следующее открытие.
      await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
      await tester.pump();
      d.closeChooser();
      await tester.pumpAndSettle();
      await d.openChooser(tester);
      d.repository.complete([d.home, d.work]);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      editors.last.complete(_tag(53, 'Закрытое открытие'));
      await tester.pump();
      expect(find.text('Закрытое открытие'), findsNothing);
      expect(_hidden, findsNothing);
      expect(
        tester.widget<Semantics>(_row(d.work)).properties.selected,
        isFalse,
      );
      expect(tester.widget<FilledButton>(_add).onPressed, isNull);
      expect(second.current.tagIds, [d.work.id]);
      expect(d.repository.reads, hasLength(3));
      expect(d.repository.commands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _assign = find.byKey(const ValueKey('tag-catalog-assign'));
final _add = find.byKey(const ValueKey('tag-catalog-add-to-draft'));
final _hidden = find.byKey(const ValueKey('tag-catalog-hidden-selection'));
Finder _hiddenText(String text) =>
    find.descendant(of: _hidden, matching: find.text(text));
Finder _status(Tag tag, String status) =>
    find.descendant(of: _row(tag), matching: find.text(status));
List<String> _visibleNames(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(
      of: find.byKey(const ValueKey('tag-catalog-list')),
      matching: find.byType(ListTile),
    ),
  ))
    (tile.title! as Text).data!,
];
Finder _row(Tag tag) =>
    find.byKey(ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'));

Future<_Harness> _show(
  WidgetTester tester, {
  Future<Tag?> Function(TagEditorContext)? onOpenEditor,
}) async {
  final h = _Harness();
  addTearDown(h.repository.dispose);
  addTearDown(h.intention.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(h.repository),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ValueListenableBuilder(
          valueListenable: h.intention,
          builder: (_, intentionId, _) => TagCatalogView(
            selectionContext: TagAssignmentContext(intentionId),
            onOpenEditor: onOpenEditor ?? (_) async => null,
            onOpenNavigation: (_) {},
          ),
        ),
      ),
    ),
  );
  h.repository.complete([h.home, h.work], assignedIds: {});
  await tester.pump();
  return h;
}

final class _Harness {
  final repository = TagCatalogTestRepository();
  final intention = ValueNotifier(_intentionId(100));
  final home = _tag(1, 'Дом');
  final work = _tag(2, 'Работа');
}

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';
IntentionId _intentionId(int number) =>
    (IntentionId.decode(_id(number)) as IntentionIdDecodingSuccess).id;
Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(_id(number)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);

/// Общий выбор в контексте живой сессии черновика, открытый поверх исходной
/// страницы. Сессию можно заменить, а владельца выбора — перестроить с новым
/// экземпляром контекста той же сессии.
Future<_DraftHarness> _showDraft(
  WidgetTester tester, {
  Future<Tag?> Function(TagEditorContext)? onOpenEditor,
}) async {
  final d = _DraftHarness(onOpenEditor ?? (_) async => null);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    d.dispose();
    await d.repository.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: d.container,
      child: MaterialApp(
        navigatorKey: d._navigator,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox.shrink(),
      ),
    ),
  );
  await d.openChooser(tester);
  d.repository.complete([d.home, d.work]);
  await tester.pumpAndSettle();
  return d;
}

final class _DraftHarness {
  _DraftHarness._(this.repository, this.container, this._onOpenEditor) {
    tagSet = ValueNotifier(openSession());
  }

  factory _DraftHarness(Future<Tag?> Function(TagEditorContext) onOpenEditor) {
    final repository = TagCatalogTestRepository();
    return _DraftHarness._(
      repository,
      ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      ),
      onOpenEditor,
    );
  }

  final TagCatalogTestRepository repository;
  final ProviderContainer container;
  final Future<Tag?> Function(TagEditorContext) _onOpenEditor;
  final _navigator = GlobalKey<NavigatorState>();
  final _sessions = <ProviderSubscription<IntentionEditorState>>[];
  final _rebuilds = ValueNotifier(0);
  late final ValueNotifier<IntentionDraftTagSet> tagSet;
  final home = _tag(1, 'Дом');
  final work = _tag(2, 'Работа');

  /// Начинает новую сессию черновика и возвращает контракт её набора.
  IntentionDraftTagSet openSession() {
    final session = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    _sessions.add(container.listen(session, (_, _) {}));
    return container.read(session.notifier).draftTagSet;
  }

  /// Перестраивает выбор с новым экземпляром контекста текущей сессии.
  void rebuild() => _rebuilds.value++;

  Future<void> openChooser(WidgetTester tester) async {
    unawaited(
      _navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => ListenableBuilder(
            listenable: Listenable.merge([tagSet, _rebuilds]),
            builder: (_, _) => TagCatalogView(
              selectionContext: TagDraftContext(tagSet.value),
              onOpenEditor: _onOpenEditor,
              onOpenNavigation: (_) {},
            ),
          ),
        ),
      ),
    );
    // Индикатор загрузки каталога анимируется, поэтому переход завершается
    // явным ожиданием вместо pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  void closeChooser() => _navigator.currentState!.pop();

  void dispose() {
    for (final session in _sessions) {
      session.close();
    }
    container.dispose();
    tagSet.dispose();
    _rebuilds.dispose();
  }
}
