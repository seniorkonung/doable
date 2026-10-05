import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/intention/presentation/operation/operation_state.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show
        TestCatalogEntrySnapshot,
        TestCatalogRevision,
        testIntention,
        testSummary;

/// Контрольная точка независимых жизненных циклов фазы 2.
///
/// Сессию черновика удерживает её владелец, открытие общего выбора живёт
/// в своём маршруте, а редактор тега выполняет самостоятельную постоянную
/// операцию. Поиск и редактор не теряют ввод сессии, закрытие выбора её не
/// завершает, решение о закрытии принимает сама сессия, а поздний результат
/// и запоздалый ответ на подтверждение закрытой сессии не меняют новое
/// открытие сессии и его выбора.
void main() {
  for (final outcome in _ClosedSessionOutcome.values) {
    testWidgets(
      'черновик, открытие выбора и редактор тега независимы: ${outcome.description} закрытой во время отправки сессии и запоздалый ответ на её подтверждение не меняют новое открытие',
      (tester) async {
        final repository = _Repository([_home, _work]);
        final host = _Host(repository);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          host.dispose();
          repository.dispose();
        });
        final presenter = host.coordinator.registerAppPresentation();
        addTearDown(presenter.release);
        await host.pump(tester);

        // Поиск и настоящий редактор тега не теряют ввод первой сессии.
        final first = host.openSession();
        first.editor
          ..changeTitle(_rawTitle)
          ..changeDescription(_rawDescription)
          ..markFavorite()
          ..confirmReadiness();
        await host.openChooser(tester, first);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TagCatalogView)),
        );
        await tester.enterText(_search, 'дом');
        await tester.pump();
        await tester.tap(_row(_home));
        await tester.pump();
        await tester.tap(_addToDraft);
        await tester.pump();
        expect(first.tagSet.current.tagIds, [_home.id]);

        await tester.tap(_create);
        await tester.pumpAndSettle();
        expect(host.router.current.name, TagEditorRoute.name);
        await tester.enterText(_editorName, 'Домашнее');
        await tester.tap(_editorSubmit);
        await tester.pumpAndSettle();
        final tagClaim = await presenter.nextClaim();
        expect(tagClaim!.completion, isA<TagCommandCompletion>());
        host.coordinator.confirmPresentation(tagClaim);
        final created = repository.tagNamed('Домашнее');

        expect(host.router.current.name, TagCatalogRoute.name);
        expect(_searchText(tester), 'дом');
        expect(_isCandidate(tester, created), isTrue);
        expect(
          _status(created, l10n.tagCatalogAvailableForDraft),
          findsOneWidget,
        );
        _expectFirstDraft(first.state, tagIds: [_home.id]);
        await tester.tap(_addToDraft);
        await tester.pump();
        expect(first.tagSet.current.tagIds, [_home.id, created.id]);

        // Закрытие только выбора не завершает сессию и не запрашивает решение
        // о закрытии.
        await host.closeChooser(tester);
        expect(find.byType(TagCatalogView), findsNothing);
        final returned = first.state;
        expect(returned.closing, isA<IntentionCreationCloseNotRequested>());
        expect(returned.draftAvailability, IntentionDraftAvailability.editable);
        _expectFirstDraft(returned, tagIds: [_home.id, created.id]);

        // Решение о закрытии во время принятой отправки принимает сессия:
        // сохранение продолжается, а владелец освобождает закрытую сессию.
        first.editor.submit();
        final command = repository.creations.single;
        expect(
          command,
          isA<CreateIntention>()
              .having((command) => command.title, 'название', _rawTitle)
              .having(
                (command) => command.description,
                'описание',
                _rawDescription,
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
                _home.id,
                created.id,
              }),
        );
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
        first.release();
        await tester.pump();
        expect(repository.activeObservations, 0);

        // Новое открытие начинает с начального черновика и собственного
        // выбора; самостоятельный тег прежней сессии в него не входит.
        final second = host.openSession();
        final published = <IntentionDraftTagSetSnapshot>[];
        final changes = second.tagSet.changes.listen(published.add);
        addTearDown(changes.cancel);
        expect(second.state.draft.isChanged, isFalse);
        second.editor.changeTitle('Позвонить маме');
        await host.openChooser(tester, second);
        expect(_searchText(tester), isEmpty);
        for (final tag in [_home, _work, created]) {
          expect(
            _status(tag, l10n.tagCatalogAvailableForDraft),
            findsOneWidget,
          );
        }
        await tester.tap(_row(_home));
        await tester.pump();
        await tester.tap(_addToDraft);
        await tester.pump();
        await tester.enterText(_search, 'раб');
        await tester.pump();
        await tester.tap(_row(_work));
        await tester.pump();
        final searchInput = tester.widget<TextField>(_search).controller!;
        expect(second.tagSet.current.tagIds, [_home.id]);

        await tester.tap(_create);
        await tester.pumpAndSettle();
        await tester.enterText(_editorName, 'Дача');
        await tester.pump();
        final beforeOutcome = second.state;
        final publishedBeforeOutcome = published.length;

        // Поздний результат закрытой сессии предъявляется общей поверхностью
        // и не меняет ни новую сессию, ни её открытие выбора, ни редактор.
        outcome.complete(repository);
        await tester.pumpAndSettle();
        final claim = await presenter.nextClaim();
        expect(
          claim!.completion,
          isA<IntentionCommandCompletion>().having(
            (completion) => completion.result,
            'результат',
            outcome.matcher,
          ),
        );
        host.coordinator.confirmPresentation(claim);

        final afterOutcome = second.state;
        expect(afterOutcome, same(beforeOutcome));
        expect(afterOutcome.operation, isA<OperationIdle<Intention>>());
        expect(afterOutcome.event, isNull);
        expect(afterOutcome.failurePresentation, isNull);
        expect(afterOutcome.missingTagIds, isEmpty);
        expect(
          afterOutcome.selectedTags[_home.id]?.status,
          isA<IntentionDraftTagAvailable>(),
        );
        expect(published, hasLength(publishedBeforeOutcome));
        expect(second.tagSet.current.tagIds, [_home.id]);
        expect(
          second.tagSet.current.availability,
          IntentionDraftAvailability.editable,
        );
        expect(host.router.current.name, TagEditorRoute.name);
        expect(
          find.descendant(of: _editorName, matching: find.text('Дача')),
          findsOneWidget,
        );

        // Отмена редактора возвращает то же открытие с прежними поиском и
        // кандидатом; набор меняется только явным добавлением.
        await tester.tap(_editorCancel);
        await tester.pumpAndSettle();
        expect(host.router.current.name, TagCatalogRoute.name);
        expect(tester.widget<TextField>(_search).controller, same(searchInput));
        expect(searchInput.text, 'раб');
        expect(_row(_home), findsNothing);
        expect(_isCandidate(tester, _work), isTrue);
        expect(
          _status(_work, l10n.tagCatalogAvailableForDraft),
          findsOneWidget,
        );
        expect(repository.tagNames, isNot(contains('Дача')));
        await tester.tap(_addToDraft);
        await tester.pump();
        expect(second.tagSet.current.tagIds, [_home.id, _work.id]);
        await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
        await tester.pump();
        expect(_status(_home, l10n.tagCatalogInDraft), findsOneWidget);
        expect(_status(_work, l10n.tagCatalogInDraft), findsOneWidget);
        expect(
          _status(created, l10n.tagCatalogAvailableForDraft),
          findsOneWidget,
        );
        await host.closeChooser(tester);

        // Запоздалый ответ на подтверждение закрытой сессии не решает
        // подтверждение новой сессии и не закрывает её.
        final pending = _confirmationOf(second.editor.requestClose());
        expect(
          pending.savingOnClose,
          IntentionCreationSavingOnClose.notStarted,
        );
        for (final choice in IntentionCreationCloseChoice.values) {
          expect(
            first.editor.resolveClose(confirmation, choice),
            IntentionCreationCloseResolution.outdated,
          );
          expect(
            second.editor.resolveClose(confirmation, choice),
            IntentionCreationCloseResolution.outdated,
          );
        }
        final awaiting = second.state;
        expect(
          awaiting.closing,
          isA<IntentionCreationCloseConfirming>().having(
            (closing) => closing.confirmation,
            'подтверждение',
            same(pending),
          ),
        );
        expect(awaiting.draftAvailability, IntentionDraftAvailability.editable);
        expect(
          second.editor.resolveClose(
            pending,
            IntentionCreationCloseChoice.continueEditing,
          ),
          IntentionCreationCloseResolution.continued,
        );

        final kept = second.state;
        expect(kept.closing, isA<IntentionCreationCloseNotRequested>());
        expect(kept.draftAvailability, IntentionDraftAvailability.editable);
        expect(kept.draft.title, 'Позвонить маме');
        expect(kept.draft.description, isEmpty);
        expect(kept.draft.readiness, IntentionReadiness.notReady);
        expect(kept.draft.favoriteMark, FavoriteMark.notFavorite);
        expect(kept.draft.tagIds, [_home.id, _work.id]);
        expect(repository.creations, [same(command)]);
        expect(repository.tagCommands, [
          isA<CreateTag>().having(
            (command) => command.name,
            'название',
            created.name,
          ),
        ]);
        expect(repository.catalogModes.toSet(), {const TagCatalogBrowseMode()});
        expect(tester.takeException(), isNull);
      },
    );
  }
}

/// Окончательный результат отправки сессии, закрытой до его получения.
enum _ClosedSessionOutcome {
  success('успех'),
  unavailable('устранимый отказ'),
  tagsMissing('отказ отсутствующего тега, выбранного и в новом открытии');

  const _ClosedSessionOutcome(this.description);

  final String description;

  void complete(_Repository repository) => switch (this) {
    _ClosedSessionOutcome.success => repository.confirmCreation(),
    _ClosedSessionOutcome.unavailable => repository.failCreation(
      const IntentionUnavailableFailure(),
    ),
    _ClosedSessionOutcome.tagsMissing => repository.failCreation(
      IntentionCreationTagsMissingFailure([_home.id]),
    ),
  };

  Matcher get matcher => switch (this) {
    _ClosedSessionOutcome.success =>
      isA<ResultSuccess<IntentionCommandSuccess>>(),
    _ClosedSessionOutcome.unavailable =>
      isA<ResultFailure<IntentionCommandSuccess>>().having(
        (result) => result.failure,
        'отказ',
        isA<IntentionUnavailableFailure>(),
      ),
    _ClosedSessionOutcome.tagsMissing =>
      isA<ResultFailure<IntentionCommandSuccess>>().having(
        (result) => result.failure,
        'отказ',
        isA<IntentionCreationTagsMissingFailure>().having(
          (failure) => failure.missingTagIds,
          'отсутствующие теги',
          {_home.id},
        ),
      ),
  };
}

const _rawTitle = '  Купить хлеб  ';
const _rawDescription = '  К ужину\n';

final _home = _tag(1, 'Дом');
final _work = _tag(2, 'Работа');

final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _addToDraft = find.byKey(const ValueKey('tag-catalog-add-to-draft'));
final _create = find.byKey(const ValueKey('tag-catalog-create'));
final _editorName = find.byKey(const ValueKey('tag-editor-name'));
final _editorSubmit = find.byKey(const ValueKey('tag-editor-submit'));
final _editorCancel = find.byKey(const ValueKey('tag-editor-cancel'));

void _expectFirstDraft(
  IntentionEditorState state, {
  required List<TagId> tagIds,
}) {
  expect(state.draft.title, _rawTitle);
  expect(state.draft.description, _rawDescription);
  expect(state.draft.readiness, IntentionReadiness.ready);
  expect(state.draft.favoriteMark, FavoriteMark.favorite);
  expect(state.draft.tagIds, tagIds);
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

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(_search).controller!.text;

Finder _row(Tag tag) =>
    find.byKey(ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'));

Finder _status(Tag tag, String status) =>
    find.descendant(of: _row(tag), matching: find.text(status));

bool _isCandidate(WidgetTester tester, Tag tag) =>
    tester.widget<Semantics>(_row(tag)).properties.selected ?? false;

TagId _tagId(int number) => switch (TagId.decode(
  '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный UUID тега.'),
};

Tag _tag(int number, String name) =>
    Tag(id: _tagId(number), name: TagName.fromInput(name));

/// Сессии черновика, общий выбор через существующую страницу и настоящий
/// редактор тега в одном маршрутном стеке и одном контейнере.
final class _Host {
  _Host(PersonalGraphRepository repository)
    : container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      );

  final ProviderContainer container;
  final router = _LifecycleRouter();

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  _Session openSession() => _Session(container);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openChooser(WidgetTester tester, _Session session) async {
    unawaited(
      router.push<void>(
        TagCatalogRoute(selectionContext: TagDraftContext(session.tagSet)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeChooser(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  void dispose() {
    router.dispose();
    container.dispose();
  }
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

  IntentionEditorState get state => _container.read(provider);

  /// Владелец уходит, и сессия освобождается.
  void release() => _owner.close();
}

/// Владелец сессии, существующая страница выбора тегов и настоящий
/// редактор тега.
final class _LifecycleRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: 'CreationOwnerRoute',
      path: '/',
      builder: (_, _) => const Scaffold(),
    ),
    AutoRoute(page: TagCatalogRoute.page),
    AutoRoute(page: TagEditorRoute.page),
  ];
}

/// Управляемое хранилище: чтения каталога и наблюдения тегов отвечают
/// текущим снимком, создание тега подтверждается сразу, а создание
/// намерения ждёт явного исхода от теста.
final class _Repository extends Fake implements PersonalGraphRepository {
  _Repository(List<Tag> tags) : _tags = [...tags];

  final List<Tag> _tags;
  var _revision = 1;
  var _nextTagNumber = 100;
  final catalogModes = <TagCatalogMode>[];
  final tagCommands = <TagCommand>[];
  final creations = <CreateIntention>[];
  final _creationResults =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  final _observations = <StreamController<TagReadResult>>[];

  List<String> get tagNames => [for (final tag in _tags) tag.name.value];

  Tag tagNamed(String name) =>
      _tags.singleWhere((tag) => tag.name.value == name);

  /// Число наблюдений тегов, подписка на которые ещё не освобождена.
  int get activeObservations =>
      _observations.where((observation) => observation.hasListener).length;

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) async {
    catalogModes.add(mode);
    return TagCatalogSuccess(
      TagCatalogSnapshot(
        items: [..._tags],
        revision: TestCatalogRevision(_revision),
      ),
    );
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    late final StreamController<TagReadResult> observation;
    observation = StreamController<TagReadResult>(
      onListen: () => observation.add(
        TagReadSuccess(
          GraphSnapshot(
            value: _tags.where((tag) => tag.id == id).firstOrNull,
            revision: TestCatalogRevision(_revision),
          ),
        ),
      ),
    );
    _observations.add(observation);
    return observation.stream;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final Object result = switch (command) {
      final CreateTag create => _createTag(create),
      final CreateIntention create => await _createIntention(create),
      _ => throw UnsupportedError('Команда не используется в этой проверке.'),
    };
    return result as GraphCommandResult<TSuccess, TFailure>;
  }

  /// Подтверждает создание намерения с назначениями всех выбранных тегов на
  /// одной новой ревизии.
  void confirmCreation() {
    final command = creations.single;
    final revision = TestCatalogRevision(++_revision);
    final intention = testIntention(title: 'Купить хлеб');
    _creationResults.single.complete(
      ResultSuccess(
        ConfirmedGraphResult(
          revision: revision,
          value: IntentionSaved(
            intention,
            catalogMutation: IntentionCatalogCreated(
              revision: revision,
              entry: TestCatalogEntrySnapshot(
                testSummary(
                  title: 'Купить хлеб',
                  readiness: command.readiness,
                  favoriteMark: command.favoriteMark,
                ),
              ),
            ),
            additionalChanges: [
              for (final tagId in command.tagIds)
                TagAssignmentChangedChange(
                  revision: revision,
                  assignment: TagAssignment(
                    tagId: tagId,
                    intentionId: intention.id,
                  ),
                  state: TagAssignmentState.assigned,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void failCreation(IntentionFailure failure) =>
      _creationResults.single.complete(ResultFailure(failure));

  TagCommandResult _createTag(CreateTag command) {
    tagCommands.add(command);
    final tag = Tag(id: _tagId(_nextTagNumber++), name: command.name);
    _tags.add(tag);
    final revision = TestCatalogRevision(++_revision);
    return TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: revision,
        value: TagCreated(TagCreatedChange(revision: revision, after: tag)),
      ),
    );
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _createIntention(CreateIntention command) {
    creations.add(command);
    final result =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _creationResults.add(result);
    return result.future;
  }

  void dispose() {
    for (final observation in _observations) {
      unawaited(observation.close());
    }
  }
}
