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
import 'package:doable/src/tag/domain/tag_color.dart';
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

    h.cycle(_tag(1, 'Спорт', color: TagColor.green));
    expect(h.shown, [(_id(1), _present, 'Спорт')]);
    expect(h.colors, {_id(1): TagColor.green});
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));

    h.cycle(_tag(1, 'Спорт', color: TagColor.green));
    expect(h.shown, [(_id(1), _absent, 'Спорт')]);
    expect(h.appliedFilter, IntentionTagFilter(excludedTagIds: [_id(1)]));

    h.cycle(_tag(1, 'Спорт', color: TagColor.green));
    expect(h.conditions, isEmpty);
    expect(h.appliedFilter, IntentionTagFilter.empty);
  });

  test('смена надобности сохраняет место условия среди других, а новое '
      'условие встаёт в конец', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.cycle(_tag(1, 'Здоровье'));
    h.cycle(_tag(2, 'Спорт'));
    h.cycle(_tag(3, 'Отдых'));

    h.cycle(_tag(2, 'Спорт'));
    expect(h.shown, [
      (_id(1), _present, 'Здоровье'),
      (_id(2), _absent, 'Спорт'),
      (_id(3), _present, 'Отдых'),
    ]);

    h.cycle(_tag(2, 'Спорт'));
    h.cycle(_tag(2, 'Спорт'));
    expect(h.shown, [
      (_id(1), _present, 'Здоровье'),
      (_id(3), _present, 'Отдых'),
      (_id(2), _present, 'Спорт'),
    ]);
  });

  test('переключение тегом из более раннего снимка не возвращает '
      'подтверждённые название и цвет', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.cycle(_tag(1, 'Здоровье'));
    h.update(
      2,
      _tag(1, 'Здоровье'),
      _tag(1, 'Самочувствие', color: TagColor.blue),
    );

    h.cycle(_tag(1, 'Здоровье'), revision: 1);

    expect(h.shown, [(_id(1), _absent, 'Самочувствие')]);
    expect(h.colors, {_id(1): TagColor.blue});
  });

  test('сброс снимает все условия одним чтением первой порции с сохранённой '
      'подстрокой названия', () async {
    final h = _Harness(filterDebounce: Duration.zero);
    addTearDown(h.dispose);
    h.catalog.changeTitleFilter('ходить');
    await pumpEventQueue();
    h.cycle(_tag(1, 'Здоровье'));
    h.cycle(_tag(2, 'Спорт'));
    h.cycle(_tag(2, 'Спорт'));
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
    h.cycle(_tag(2, 'Спорт'));
    h.delete(2, _id(1));
    h.appliedFilter;
    final queries = h.repository.queries.length;

    h.cycle(_tag(1, 'Здоровье'), revision: 1);

    expect(h.shown, [(_id(2), _present, 'Спорт')]);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(2)]));
    expect(h.repository.queries, hasLength(queries));
  });

  test('контракт условий публикует переключение, сброс и снятие условия при '
      'удалении тега', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final IntentionTagConditionSet conditionSet = h.model;
    final published = <List<(TagId, IntentionTagRequirement, String)>>[];
    final subscription = conditionSet.changes.listen(
      (state) => published.add(_shown(state)),
    );
    addTearDown(subscription.cancel);

    conditionSet.cycle(
      _tag(1, 'Здоровье'),
      snapshotRevision: const _Revision(1),
    );
    conditionSet.cycle(_tag(2, 'Спорт'), snapshotRevision: const _Revision(1));
    h.delete(2, _id(1));
    conditionSet.clear();
    await pumpEventQueue();

    expect(published, [
      [(_id(1), _present, 'Здоровье')],
      [(_id(1), _present, 'Здоровье'), (_id(2), _present, 'Спорт')],
      [(_id(2), _present, 'Спорт')],
      <(TagId, IntentionTagRequirement, String)>[],
    ]);
    expect(conditionSet.current.conditions, isEmpty);
  });

  test('подтверждённое изменение только цвета обновляет условие без новой '
      'выдачи', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));
    final queries = h.repository.queries.length;

    h.update(2, _tag(1, 'Здоровье'), _tag(1, 'Здоровье', color: TagColor.blue));

    expect(h.shown, [(_id(1), _present, 'Здоровье')]);
    expect(h.colors, {_id(1): TagColor.blue});
    // Идентичность и надобность условия прежние: новая выдача не начинается.
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));
    expect(h.repository.queries, hasLength(queries));
  });

  test('подтверждённое удаление снимает обязательное и исключающее условия, '
      'а остальные сохраняют места и надобности без повторной публикации '
      'фильтра', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.select(_tag(2, 'Спорт'), _absent);
    h.select(_tag(3, 'Отдых'), _present);
    h.select(_tag(4, 'Работа'), _absent);
    h.appliedFilter;
    final queries = h.repository.queries.length;

    h.delete(2, _id(1));
    h.delete(3, _id(4));

    expect(h.shown, [(_id(2), _absent, 'Спорт'), (_id(3), _present, 'Отдых')]);
    // Фильтр без снятых тегов применяет модель каталога по тому же пакету.
    h.appliedFilter;
    expect(h.repository.queries, hasLength(queries));
  });

  test('новый тег с прежним названием не восстанавливает снятое условие', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.delete(2, _id(1));

    h.package(3, [
      TagCreatedChange(
        revision: const _Revision(3),
        after: _tag(7, 'Здоровье'),
      ),
    ]);

    expect(h.conditions, isEmpty);
  });

  test('выбор уже удалённого тега из устаревшего снимка не меняет условий и '
      'выдачи', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(2, 'Спорт'), _present);
    h.delete(2, _id(1));
    h.appliedFilter;
    final queries = h.repository.queries.length;

    h.select(_tag(1, 'Здоровье'), _absent, revision: 1);

    expect(h.shown, [(_id(2), _present, 'Спорт')]);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(2)]));
    expect(h.repository.queries, hasLength(queries));
  });

  test('повторный выбор из более нового снимка обновляет название и '
      'цвет', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.package(2, [
      TagCreatedChange(revision: const _Revision(2), after: _tag(8, 'Быт')),
    ]);

    h.select(
      _tag(1, 'Самочувствие', color: TagColor.blue),
      _absent,
      revision: 2,
    );
    expect(h.shown, [(_id(1), _absent, 'Самочувствие')]);
    expect(h.colors, {_id(1): TagColor.blue});

    // Прежний снимок не возвращает уже подтверждённые название и цвет.
    h.select(_tag(1, 'Здоровье'), _present, revision: 1);
    expect(h.shown, [(_id(1), _present, 'Самочувствие')]);
    expect(h.colors, {_id(1): TagColor.blue});
  });

  test('условия разных назначений поиска независимы', () {
    final h = _Harness();
    addTearDown(h.dispose);
    final action = _actionSearchPurpose;
    final conditions = intentionTagConditionsViewModelProvider(action);
    final subscription = h.container.listen(conditions, (_, _) {});
    addTearDown(subscription.close);

    h.select(_tag(1, 'Здоровье'), _present);
    expect(h.container.read(conditions).conditions, isEmpty);
    expect(
      h.container
          .read(intentionCatalogViewModelProvider(action).notifier)
          .selection
          .tagFilter,
      IntentionTagFilter.empty,
    );

    h.container
        .read(conditions.notifier)
        .applySelection(
          IntentionTagConditionSelection(
            tag: _tag(2, 'Спорт'),
            requirement: _absent,
            snapshotRevision: const _Revision(1),
          ),
        );
    expect(h.shown, [(_id(1), _present, 'Здоровье')]);
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
  List<(TagId, IntentionTagRequirement, String)> get shown => _shown(state);

  /// Предъявляемые цвета условий; `null` — «Без цвета».
  Map<TagId, TagColor?> get colors => {
    for (final condition in conditions) condition.tagId: condition.color,
  };

  IntentionCatalogViewModel get catalog =>
      container.read(intentionCatalogViewModelProvider(purpose).notifier);

  /// Условия, с которыми модель каталога того же назначения читает выдачу.
  IntentionTagFilter get appliedFilter {
    final filter = catalog.selection.tagFilter;
    container.read(intentionCatalogViewModelProvider(purpose));
    expect(repository.queries.last.tagFilter, filter);
    return filter;
  }

  void select(
    Tag tag,
    IntentionTagRequirement requirement, {
    int revision = 1,
  }) {
    model.applySelection(
      IntentionTagConditionSelection(
        tag: tag,
        requirement: requirement,
        snapshotRevision: _Revision(revision),
      ),
    );
  }

  void cycle(Tag tag, {int revision = 1}) =>
      model.cycle(tag, snapshotRevision: _Revision(revision));

  void package(int revision, List<GraphChange> packageChanges) =>
      changes.add(_Package(_Revision(revision), packageChanges));

  void update(int revision, Tag before, Tag after) => package(revision, [
    TagUpdatedChange(
      revision: _Revision(revision),
      before: before,
      after: after,
    ),
  ]);

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

List<(TagId, IntentionTagRequirement, String)> _shown(
  IntentionTagConditionsState state,
) => [
  for (final condition in state.conditions)
    (condition.tagId, condition.requirement, condition.name.value),
];

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

Tag _tag(int number, String name, {TagColor? color}) => Tag(
  id: _id(number),
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(number),
);
