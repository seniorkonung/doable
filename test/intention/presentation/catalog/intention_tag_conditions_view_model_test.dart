import 'dart:async';

import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_support.dart';
import '../../../support/tag_positions.dart';

final _actionSearchPurpose = SelectDailyChoiceAction(
  session: IntentionSearchSession(),
);

const _present = IntentionTagRequirement.mustBePresent;
const _absent = IntentionTagRequirement.mustBeAbsent;

void main() {
  test('три переключения тега требуют его, затем исключают и снимают '
      'условие, каждый раз сразу применяя поиск', () {
    final h = _Harness();
    addTearDown(h.dispose);

    h.cycle(1);
    expect(h.shown, [(_id(1), _present)]);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));

    h.cycle(1);
    expect(h.shown, [(_id(1), _absent)]);
    expect(h.appliedFilter, IntentionTagFilter(excludedTagIds: [_id(1)]));

    h.cycle(1);
    expect(h.conditions, isEmpty);
    expect(h.appliedFilter, IntentionTagFilter.empty);
  });

  test('сброс снимает все условия одним чтением первой порции с сохранённой '
      'подстрокой названия', () async {
    final h = _Harness(filterDebounce: Duration.zero);
    addTearDown(h.dispose);
    h.catalog.changeTitleFilter('ходить');
    await pumpEventQueue();
    h.cycle(1);
    h.cycle(2);
    h.cycle(2);
    h.appliedFilter;
    final queries = h.repository.queries.length;

    h.model.clear();

    expect(h.conditions, isEmpty);
    expect(h.appliedFilter, IntentionTagFilter.empty);
    expect(h.repository.queries, hasLength(queries + 1));
    final query = h.repository.queries.last;
    expect(query.titleFilter?.map((value) => value), 'ходить');
    expect(query.cursor, isNull);
  });

  test('переключение тега, удаление которого модель уже получила, не меняет '
      'условий и выдачи', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.cycle(2);
    h.delete(2, _id(1));
    h.appliedFilter;
    final queries = h.repository.queries.length;

    h.cycle(1);

    expect(h.shown, [(_id(2), _present)]);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(2)]));
    expect(h.repository.queries, hasLength(queries));
  });

  test('контракт условий публикует переключение, сброс и снятие условия при '
      'удалении тега', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final IntentionTagConditionSet conditionSet = h.model;
    final published = <List<(TagId, IntentionTagRequirement)>>[];
    final subscription = conditionSet.changes.listen(
      (state) => published.add(_shown(state)),
    );
    addTearDown(subscription.cancel);

    conditionSet.cycle(_id(1));
    conditionSet.cycle(_id(2));
    h.delete(2, _id(1));
    conditionSet.clear();
    await pumpEventQueue();

    expect(published, [
      [(_id(1), _present)],
      unorderedEquals([(_id(1), _present), (_id(2), _present)]),
      [(_id(2), _present)],
      <(TagId, IntentionTagRequirement)>[],
    ]);
    expect(conditionSet.current.conditions, isEmpty);
  });

  test('подтверждённое удаление снимает обязательное и исключающее условия, '
      'а остальные сохраняют надобности без повторной публикации фильтра', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.cycle(1);
    h.cycle(2);
    h.cycle(2);
    h.cycle(3);
    h.cycle(4);
    h.cycle(4);
    h.appliedFilter;
    final queries = h.repository.queries.length;

    h.delete(2, _id(1));
    h.delete(3, _id(4));

    expect(h.shown, unorderedEquals([(_id(2), _absent), (_id(3), _present)]));
    // Фильтр без снятых тегов применяет модель каталога по тому же пакету.
    h.appliedFilter;
    expect(h.repository.queries, hasLength(queries));
  });

  test('новый тег с прежним названием не восстанавливает снятое условие', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.cycle(1);
    h.delete(2, _id(1));

    h.package(3, [
      TagCreatedChange(
        revision: const _Revision(3),
        after: _tag(7, 'Здоровье'),
      ),
    ]);

    expect(h.conditions, isEmpty);
  });

  test('условия разных назначений поиска независимы', () {
    final h = _Harness();
    addTearDown(h.dispose);
    final action = _actionSearchPurpose;
    final conditions = intentionTagConditionsViewModelProvider(action);
    final subscription = h.container.listen(conditions, (_, _) {});
    addTearDown(subscription.close);

    h.cycle(1);
    expect(h.container.read(conditions).conditions, isEmpty);
    expect(
      h.container
          .read(intentionCatalogViewModelProvider(action).notifier)
          .selection
          .tagFilter,
      IntentionTagFilter.empty,
    );

    h.container.read(conditions.notifier)
      ..cycle(_id(2))
      ..cycle(_id(2));
    expect(h.shown, [(_id(1), _present)]);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));
    expect(
      h.container
          .read(intentionCatalogViewModelProvider(action).notifier)
          .selection
          .tagFilter,
      IntentionTagFilter(excludedTagIds: [_id(2)]),
    );
  });
}

final class _Harness {
  _Harness({Duration filterDebounce = const Duration(minutes: 1)}) {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: 100,
            prefetchRemaining: 30,
            filterDebounce: filterDebounce,
          ),
        ),
        intentionTagConditionsChangesProvider.overrideWithValue(changes.stream),
      ],
      retry: (retryCount, error) => null,
    );
    subscription = container.listen(provider, (_, _) {});
  }

  static const purpose = BrowseIntentionCatalog();

  final provider = intentionTagConditionsViewModelProvider(purpose);
  final repository = ControlledCatalogRepository();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
    sync: true,
  );
  late final ProviderContainer container;
  late final ProviderSubscription<IntentionTagConditionsState> subscription;

  IntentionTagConditionsViewModel get model =>
      container.read(provider.notifier);
  IntentionTagConditionsState get state => container.read(provider);
  List<IntentionTagCondition> get conditions => state.conditions;
  List<(TagId, IntentionTagRequirement)> get shown => _shown(state);

  IntentionCatalogViewModel get catalog =>
      container.read(intentionCatalogViewModelProvider(purpose).notifier);

  /// Условия, с которыми модель каталога того же назначения читает выдачу.
  IntentionTagFilter get appliedFilter {
    final filter = catalog.selection.tagFilter;
    container.read(intentionCatalogViewModelProvider(purpose));
    expect(repository.queries.last.tagFilter, filter);
    return filter;
  }

  void cycle(int number) => model.cycle(_id(number));

  void package(int revision, List<GraphChange> packageChanges) =>
      changes.add(_Package(_Revision(revision), packageChanges));

  void delete(int revision, TagId tagId) => package(revision, [
    TagDeletedChange(revision: _Revision(revision), tagId: tagId),
  ]);

  void dispose() {
    container.dispose();
    unawaited(changes.close());
  }
}

final class _Package implements ConfirmedGraphChangePackage {
  const _Package(this.revision, this.changes);
  @override
  final GraphRevision revision;
  @override
  final List<GraphChange> changes;
}

final class _Revision implements GraphRevision {
  const _Revision(this.number);
  final int number;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(number: final n) when number < n => GraphRevisionOrder.older,
    _Revision(number: final n) when number > n => GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

List<(TagId, IntentionTagRequirement)> _shown(
  IntentionTagConditionsState state,
) => [
  for (final condition in state.conditions)
    (condition.tagId, condition.requirement),
];

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

Tag _tag(int number, String name) => Tag(
  id: _id(number),
  name: TagName.fromInput(name),
  color: null,
  position: tagPositionAt(number),
);
