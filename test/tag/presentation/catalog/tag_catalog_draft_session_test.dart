import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
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

import '../../../support/tag_assignment_changed.dart';
import '../../../support/tag_catalog_test_repository.dart'
    show TagCatalogTestRevision;

/// Совместные проверки общего выбора тегов и проекции сессии черновика:
/// локальное включение отличается от постоянного назначения, выбранные
/// идентичности не теряются и не подменяются, а одно явное действие даёт
/// один эффект.
void main() {
  final home = _tag(1, 'Дом');
  final work = _tag(2, 'Работа');

  testWidgets(
    'одно явное добавление даёт одно включение и одно наблюдение проекции, а переименование, удаление и одноимённый тег не меняют идентичность в наборе',
    (tester) async {
      final repository = _Repository();
      final draft = _DraftSession(repository);
      addTearDown(draft.dispose);
      final published = <Set<TagId>>[];
      final changes = draft.tagSet.changes.listen(
        (snapshot) => published.add(snapshot.tagIds),
      );
      addTearDown(changes.cancel);
      await tester.pumpWidget(
        draft.app(
          home: TagCatalogView(
            selectionContext: TagDraftContext(draft.tagSet),
            onOpenEditor: (_) async => null,
            onOpenNavigation: (_) {},
          ),
        ),
      );
      repository.completeRead([home, work]);
      await tester.pump();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TagCatalogView)),
      );
      final search = find.byKey(const ValueKey('tag-catalog-search'));
      final add = find.byKey(const ValueKey('tag-catalog-add-to-draft'));
      await tester.enterText(search, 'дом');
      await tester.pump();

      // Нажатия строки выбирают кандидата, а не меняют набор.
      await tester.tap(_row(home));
      await tester.pump();
      await tester.tap(_row(home));
      await tester.pump();
      expect(published, isEmpty);
      expect(draft.tagSet.current.tagIds, isEmpty);
      expect(draft.state.selectedTags, isEmpty);
      expect(repository.observationCount(home.id), 1);

      // Повторные нажатия до перестроения дают одно включение.
      await tester.tap(add);
      await tester.tap(add, warnIfMissed: false);
      await tester.tap(add, warnIfMissed: false);
      await tester.pump();

      expect(published, [
        {home.id},
      ]);
      expect(draft.tagSet.current.tagIds, [home.id]);
      expect(draft.state.selectedTags.keys, [home.id]);
      expect(draft.state.selectedTags[home.id]?.name, home.name);
      expect(
        draft.state.selectedTags[home.id]?.status,
        isA<IntentionDraftTagLoading>(),
      );
      expect(repository.observationCount(home.id), 2);
      expect(_status(home, l10n.tagCatalogInDraft), findsOneWidget);
      expect(tester.widget<FilledButton>(add).onPressed, isNull);

      repository.observe(home.id, home, revision: 1);
      await tester.pump();
      expect(
        draft.state.selectedTags[home.id]?.status,
        isA<IntentionDraftTagAvailable>(),
      );

      // Переименование меняет название проекции и строки, но не набор.
      final renamed = _tag(1, 'Дом и сад');
      draft.coordinator.acceptTagRename(
        RenameTag(tagId: home.id, name: renamed.name),
      );
      repository.completeCommand(
        TagRenamed(
          TagRenamedChange(
            revision: const TagCatalogTestRevision(2),
            before: home,
            after: renamed,
          ),
        ),
        revision: 2,
      );
      await tester.pump();
      repository.observe(home.id, renamed, revision: 2);
      repository.completeRead([renamed, work], revision: 2);
      await tester.pump();
      await tester.pump();

      expect(find.text('Дом и сад'), findsOneWidget);
      expect(_status(renamed, l10n.tagCatalogInDraft), findsOneWidget);
      expect(tester.widget<FilledButton>(add).onPressed, isNull);
      expect(draft.tagSet.current.tagIds, [home.id]);
      expect(published, hasLength(1));
      expect(draft.state.selectedTags[home.id]?.name, renamed.name);
      expect(
        draft.state.selectedTags[home.id]?.status,
        isA<IntentionDraftTagAvailable>(),
      );

      // Удаление убирает строку выбора, но не снимает тег из черновика.
      draft.coordinator.acceptTagDelete(DeleteTag(home.id));
      repository.completeCommand(
        TagDeleted(
          TagDeletedChange(
            revision: const TagCatalogTestRevision(3),
            tagId: home.id,
          ),
        ),
        revision: 3,
      );
      await tester.pump();
      repository.observe(home.id, null, revision: 3);
      repository.completeRead([work], revision: 3);
      await tester.pump();
      await tester.pump();

      expect(_row(home), findsNothing);
      expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
      expect(tester.widget<FilledButton>(add).onPressed, isNull);
      expect(draft.tagSet.current.tagIds, [home.id]);
      expect(published, hasLength(1));
      expect(draft.state.selectedTags[home.id]?.name, renamed.name);
      expect(
        draft.state.selectedTags[home.id]?.status,
        isA<IntentionDraftTagMissing>(),
      );

      // Новый тег с последним известным названием удалённого — другая
      // идентичность: он доступен для добавления, а не включён.
      final namesake = _tag(3, 'Дом и сад');
      draft.coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(namesake.name),
      );
      repository.completeCommand(
        TagCreated(
          TagCreatedChange(
            revision: const TagCatalogTestRevision(4),
            after: namesake,
          ),
        ),
        revision: 4,
      );
      await tester.pump();
      repository.completeRead([work, namesake], revision: 4);
      await tester.pump();
      await tester.pump();

      expect(
        _status(namesake, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      expect(find.text(l10n.tagCatalogInDraft), findsNothing);
      expect(draft.tagSet.current.tagIds, [home.id]);
      expect(draft.state.selectedTags.keys, [home.id]);

      await tester.tap(_row(namesake));
      await tester.pump();
      expect(draft.tagSet.current.tagIds, [home.id]);
      await tester.tap(add);
      await tester.pump();

      expect(published, [
        {home.id},
        {home.id, namesake.id},
      ]);
      expect(draft.tagSet.current.tagIds, [home.id, namesake.id]);
      expect(draft.state.selectedTags.keys, [home.id, namesake.id]);
      expect(
        draft.state.selectedTags[home.id]?.status,
        isA<IntentionDraftTagMissing>(),
      );
      expect(draft.state.selectedTags[namesake.id]?.name, namesake.name);
      expect(_status(namesake, l10n.tagCatalogInDraft), findsOneWidget);
      expect(repository.observationCount(namesake.id), 2);

      // Перечитывания вызывают только постоянные команды тегов; локальные
      // включения не пишут назначений, не проверяют пар и не сбрасывают поиск.
      expect(repository.commands, [
        isA<RenameTag>(),
        isA<DeleteTag>(),
        isA<CreateTag>(),
      ]);
      expect(
        repository.readModes,
        List.filled(4, const TagCatalogBrowseMode()),
      );
      expect(repository.statusQueries, isEmpty);
      expect(tester.widget<TextField>(search).controller!.text, 'дом');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'локальное включение в черновик и постоянное назначение существующему намерению не влияют друг на друга',
    (tester) async {
      final repository = _Repository();
      final draft = _DraftSession(repository);
      addTearDown(draft.dispose);
      final intentionId =
          (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id;
      final published = <Set<TagId>>[];
      final changes = draft.tagSet.changes.listen(
        (snapshot) => published.add(snapshot.tagIds),
      );
      addTearDown(changes.cancel);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        draft.app(
          navigatorKey: navigator,
          home: TagCatalogView(
            selectionContext: TagAssignmentContext(intentionId),
            onOpenEditor: (_) async => null,
            onOpenNavigation: (_) {},
          ),
        ),
      );
      repository.completeRead([home, work], assignedIds: {home.id});
      await tester.pump();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TagCatalogView)),
      );
      final assign = find.byKey(const ValueKey('tag-catalog-assign'));
      final add = find.byKey(const ValueKey('tag-catalog-add-to-draft'));

      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => TagCatalogView(
              selectionContext: TagDraftContext(draft.tagSet),
              onOpenEditor: (_) async => null,
              onOpenNavigation: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      repository.completeRead([home, work]);
      await tester.pumpAndSettle();

      // Назначение «Дома» существующему намерению не включает его в черновик
      // и не мешает явному локальному добавлению без проверки пары.
      expect(find.text(l10n.tagCatalogAssigned), findsNothing);
      expect(find.text(l10n.tagCatalogAvailable), findsNothing);
      expect(_status(home, l10n.tagCatalogAvailableForDraft), findsOneWidget);
      expect(_status(work, l10n.tagCatalogAvailableForDraft), findsOneWidget);
      await tester.tap(_row(home));
      await tester.pump();
      await tester.tap(add);
      await tester.pump();

      expect(draft.tagSet.current.tagIds, [home.id]);
      expect(published, [
        {home.id},
      ]);
      expect(_status(home, l10n.tagCatalogInDraft), findsOneWidget);
      expect(repository.commands, isEmpty);
      expect(repository.statusQueries, isEmpty);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();

      // Локальное включение не стало назначением, а явное назначение
      // отправляет одну постоянную команду и не меняет набор черновика.
      expect(_status(home, l10n.tagCatalogAssigned), findsOneWidget);
      expect(_status(work, l10n.tagCatalogAvailable), findsOneWidget);
      await tester.tap(_row(work));
      await tester.pump();
      expect(tester.widget<FilledButton>(assign).onPressed, isNotNull);
      await tester.tap(assign);
      await tester.tap(assign, warnIfMissed: false);
      await tester.pump();

      expect(
        repository.commands.single,
        isA<AssignTag>()
            .having((command) => command.tagId, 'tagId', work.id)
            .having(
              (command) => command.intentionId,
              'intentionId',
              intentionId,
            ),
      );
      repository.completeCommand(
        testTagAssignmentChanged(
          TagAssignmentChangedChange(
            revision: const TagCatalogTestRevision(2),
            assignment: TagAssignment(tagId: work.id, intentionId: intentionId),
            state: TagAssignmentState.assigned,
          ),
        ),
        revision: 2,
      );
      await tester.pump();
      repository.completeRead(
        [home, work],
        revision: 2,
        assignedIds: {home.id, work.id},
      );
      await tester.pump();
      await tester.pump();

      expect(_status(work, l10n.tagCatalogAssigned), findsOneWidget);
      expect(draft.tagSet.current.tagIds, [home.id]);
      expect(draft.state.selectedTags.keys, [home.id]);
      expect(published, hasLength(1));
      expect(repository.commands, hasLength(1));
      expect(repository.readModes, [
        TagCatalogSelectionMode(intentionId),
        const TagCatalogBrowseMode(),
        TagCatalogSelectionMode(intentionId),
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _row(Tag tag) =>
    find.byKey(ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'));

Finder _status(Tag tag, String status) =>
    find.descendant(of: _row(tag), matching: find.text(status));

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(_id(number)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);

/// Живая сессия черновика и координатор в одном контейнере с общим выбором.
final class _DraftSession {
  _DraftSession(_Repository repository)
    : container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      ) {
    _subscription = container.listen(_session, (_, _) {});
    tagSet = container.read(_session.notifier).draftTagSet;
  }

  final ProviderContainer container;
  final _session = intentionEditorViewModelProvider(IntentionCreationFormKey());
  late final ProviderSubscription<IntentionEditorState> _subscription;
  late final IntentionDraftTagSet tagSet;

  IntentionEditorState get state => container.read(_session);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  Widget app({required Widget home, GlobalKey<NavigatorState>? navigatorKey}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      );

  void dispose() {
    _subscription.close();
    container.dispose();
  }
}

/// Управляемое хранилище: каждое чтение каталога и каждая команда ждут
/// явного ответа теста, а каждое наблюдение тега учитывается отдельно,
/// чтобы различать наблюдение кандидата выбора и проекции черновика.
final class _Repository extends Fake implements PersonalGraphRepository {
  final _reads = <Completer<TagCatalogResult>>[];
  final readModes = <TagCatalogMode>[];
  final _commandResults = <Completer<TagCommandResult>>[];
  final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[];
  final statusQueries = <(TagId, IntentionId)>[];
  final _observations = <_Observation>[];

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) {
    final read = Completer<TagCatalogResult>();
    _reads.add(read);
    readModes.add(mode);
    return read.future;
  }

  void completeRead(
    List<Tag> tags, {
    int revision = 1,
    Set<TagId> assignedIds = const {},
  }) => _reads.last.complete(
    TagCatalogSuccess(switch (readModes.last) {
      TagCatalogBrowseMode() => TagCatalogSnapshot(
        items: tags,
        revision: TagCatalogTestRevision(revision),
      ),
      TagCatalogSelectionMode(:final intentionId) =>
        TagCatalogSnapshot.selection(
          intentionId: intentionId,
          rows: [
            for (final tag in tags)
              TagSelectionRow(
                tag: tag,
                isAssigned: assignedIds.contains(tag.id),
              ),
          ],
          revision: TagCatalogTestRevision(revision),
        ),
    }),
  );

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId id,
    IntentionId intentionId,
  ) {
    statusQueries.add((id, intentionId));
    return Completer<TagAssignmentStatusResult>().future;
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    final observation = _Observation(id);
    _observations.add(observation);
    return observation.controller.stream;
  }

  /// Число начатых наблюдений тега [id] за всё время теста.
  int observationCount(TagId id) =>
      _observations.where((observation) => observation.id == id).length;

  /// Передаёт снимок тега всем его действующим наблюдениям.
  void observe(TagId id, Tag? tag, {required int revision}) {
    for (final observation in _observations) {
      if (observation.id == id && observation.isListened) {
        observation.controller.add(
          TagReadSuccess(
            GraphSnapshot(
              value: tag,
              revision: TagCatalogTestRevision(revision),
            ),
          ),
        );
      }
    }
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command);
    final result = Completer<TagCommandResult>();
    _commandResults.add(result);
    return await result.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void completeCommand(TagCommandSuccess success, {required int revision}) =>
      _commandResults.last.complete(
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: TagCatalogTestRevision(revision),
            value: success,
          ),
        ),
      );
}

final class _Observation {
  _Observation(this.id);

  final TagId id;
  late final controller = StreamController<TagReadResult>(
    onCancel: () => _cancelled = true,
  );
  bool _cancelled = false;

  bool get isListened => controller.hasListener && !_cancelled;
}
