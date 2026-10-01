import 'dart:async';

import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_support.dart';

const _present = IntentionTagRequirement.mustBePresent;
const _absent = IntentionTagRequirement.mustBeAbsent;

void main() {
  test('условия хранятся в порядке добавления и сразу применяют поиск', () {
    final h = _Harness();
    addTearDown(h.dispose);
    expect(h.conditions, isEmpty);
    expect(h.state.tagFilter, IntentionTagFilter.empty);
    final queriesBefore = h.repository.queries.length;

    h.select(_tag(1, 'Здоровье'), _present);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));
    h.select(_tag(2, 'Спорт'), _absent);

    expect(h.shown, [
      (_id(1), _present, 'Здоровье', false),
      (_id(2), _absent, 'Спорт', false),
    ]);
    final filter = IntentionTagFilter(
      requiredTagIds: [_id(1)],
      excludedTagIds: [_id(2)],
    );
    expect(h.state.tagFilter, filter);
    // Фильтр передан без ожидания debounce и отдельного подтверждения.
    expect(h.appliedFilter, filter);
    expect(h.repository.queries.length, greaterThan(queriesBefore));
    expect(() => h.conditions.clear(), throwsUnsupportedError);
  });

  test('повторный выбор тега меняет надобность существующего условия', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.select(_tag(2, 'Спорт'), _absent);

    h.select(_tag(1, 'Здоровье'), _absent);

    expect(h.shown, [
      (_id(1), _absent, 'Здоровье', false),
      (_id(2), _absent, 'Спорт', false),
    ]);
    expect(
      h.appliedFilter,
      IntentionTagFilter(excludedTagIds: [_id(1), _id(2)]),
    );
  });

  test('переключение сохраняет место условия и сразу применяет поиск', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.select(_tag(2, 'Спорт'), _absent);

    h.model.toggleRequirement(_id(2));
    expect(h.shown, [
      (_id(1), _present, 'Здоровье', false),
      (_id(2), _present, 'Спорт', false),
    ]);
    expect(
      h.appliedFilter,
      IntentionTagFilter(requiredTagIds: [_id(1), _id(2)]),
    );

    h.model.toggleRequirement(_id(2));
    expect(h.shown.last, (_id(2), _absent, 'Спорт', false));
    h.model.toggleRequirement(_id(9));
    expect(h.shown, hasLength(2));
  });

  test('снятие убирает условие и не выполняет команд и чтений тегов', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.select(_tag(2, 'Спорт'), _absent);

    h.model.remove(_id(2));
    expect(h.shown, [(_id(1), _present, 'Здоровье', false)]);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));

    h.model.remove(_id(2));
    h.model.remove(_id(1));
    expect(h.conditions, isEmpty);
    expect(h.appliedFilter, IntentionTagFilter.empty);
    expect(h.repository.tagCommands, isEmpty);
    expect(h.repository.commands, isEmpty);
    // Выбор из актуального снимка не требует чтения тега.
    expect(h.reads.queries, isEmpty);
  });

  test('подтверждённое переименование обновляет название условия', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));
    final queries = h.repository.queries.length;

    h.rename(2, _tag(1, 'Здоровье'), 'Самочувствие');

    expect(h.shown, [(_id(1), _present, 'Самочувствие', false)]);
    // Идентичность условия прежняя: новая выдача не начинается.
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));
    expect(h.repository.queries, hasLength(queries));
  });

  test('подтверждённое удаление сохраняет условие с последним названием '
      'до явного снятия', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.select(_tag(2, 'Спорт'), _absent);
    h.rename(2, _tag(1, 'Здоровье'), 'Самочувствие');

    h.delete(3, _id(1));

    expect(h.shown, [
      (_id(1), _present, 'Самочувствие', true),
      (_id(2), _absent, 'Спорт', false),
    ]);
    expect(
      h.appliedFilter,
      IntentionTagFilter(requiredTagIds: [_id(1)], excludedTagIds: [_id(2)]),
    );

    // Удалённое условие по-прежнему переключается и снимается.
    h.model.toggleRequirement(_id(1));
    expect(h.shown.first, (_id(1), _absent, 'Самочувствие', true));
    h.model.remove(_id(1));
    expect(h.shown, [(_id(2), _absent, 'Спорт', false)]);
    expect(h.appliedFilter, IntentionTagFilter(excludedTagIds: [_id(2)]));
  });

  test('новый тег с прежним названием не снимает признак удаления', () {
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

    expect(h.shown, [(_id(1), _present, 'Здоровье', true)]);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));

    // Одноимённый тег — отдельное условие по собственному идентификатору.
    h.select(_tag(7, 'Здоровье'), _present, revision: 3);
    expect(h.shown, [
      (_id(1), _present, 'Здоровье', true),
      (_id(7), _present, 'Здоровье', false),
    ]);
  });

  test('устаревший выбор предъявляется с актуальным названием', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    // Переименование подтверждено до выбора: тег ещё не был условием.
    h.rename(2, _tag(1, 'Здоровье'), 'Самочувствие');

    h.select(_tag(1, 'Здоровье'), _present, revision: 1);

    // Поиск применяется сразу, не дожидаясь уточнения предъявления.
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));
    expect(h.shown, [(_id(1), _present, 'Здоровье', false)]);
    expect(h.reads.queries, [_id(1)]);

    h.reads.tag(0, _tag(1, 'Самочувствие'), revision: 2);
    await pumpEventQueue();
    expect(h.shown, [(_id(1), _present, 'Самочувствие', false)]);

    // Следующий выбор из снимка актуальной ревизии чтения не требует.
    h.select(_tag(2, 'Спорт'), _absent, revision: 2);
    expect(h.reads.queries, hasLength(1));
  });

  test('устаревший выбор удалённого тега получает признак удаления', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.delete(2, _id(1));

    h.select(_tag(1, 'Здоровье'), _absent, revision: 1);
    h.reads.tag(0, null, revision: 2);
    await pumpEventQueue();

    expect(h.shown, [(_id(1), _absent, 'Здоровье', true)]);
    expect(h.appliedFilter, IntentionTagFilter(excludedTagIds: [_id(1)]));
  });

  test('выбор без известной ревизии графа уточняется чтением', () async {
    final h = _Harness(knownRevision: null);
    addTearDown(h.dispose);

    h.select(_tag(1, 'Здоровье'), _present, revision: 1);
    expect(h.reads.queries, [_id(1)]);
    h.reads.tag(0, _tag(1, 'Самочувствие'), revision: 4);
    await pumpEventQueue();

    expect(h.shown, [(_id(1), _present, 'Самочувствие', false)]);
  });

  test('ошибка чтения тегов не ставит признак удаления, а следующий '
      'подтверждённый пакет повторяет уточнение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.delete(2, _id(1));
    h.select(_tag(1, 'Здоровье'), _present, revision: 1);

    h.reads.fail(0, const TagReadUnavailableFailure());
    await pumpEventQueue();
    expect(h.shown, [(_id(1), _present, 'Здоровье', false)]);
    expect(h.reads.queries, hasLength(1));

    h.package(3, [
      TagCreatedChange(revision: const _Revision(3), after: _tag(7, 'Дом')),
    ]);
    expect(h.reads.queries, [_id(1), _id(1)]);
    h.reads.throwError(1);
    await pumpEventQueue();
    expect(h.shown, [(_id(1), _present, 'Здоровье', false)]);

    h.package(4, [
      TagCreatedChange(revision: const _Revision(4), after: _tag(8, 'Быт')),
    ]);
    h.reads.tag(2, null, revision: 4);
    await pumpEventQueue();
    expect(h.shown, [(_id(1), _present, 'Здоровье', true)]);

    // Подтверждённое предъявление больше не перечитывается.
    h.package(5, [
      TagCreatedChange(revision: const _Revision(5), after: _tag(9, 'Сад')),
    ]);
    expect(h.reads.queries, hasLength(3));
  });

  test('чтение чужого тега не подменяет условие', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.rename(2, _tag(1, 'Здоровье'), 'Самочувствие');
    h.select(_tag(1, 'Здоровье'), _present, revision: 1);

    h.reads.tag(0, _tag(2, 'Спорт'), revision: 2);
    await pumpEventQueue();

    expect(h.shown, [(_id(1), _present, 'Здоровье', false)]);
  });

  test(
    'позднее чтение не возвращает название до более нового пакета',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.rename(2, _tag(1, 'Здоровье'), 'Самочувствие');
      h.select(_tag(1, 'Здоровье'), _present, revision: 1);

      h.rename(3, _tag(1, 'Самочувствие'), 'Тонус');
      expect(h.shown, [(_id(1), _present, 'Тонус', false)]);
      h.reads.tag(0, _tag(1, 'Самочувствие'), revision: 2);
      await pumpEventQueue();

      expect(h.shown, [(_id(1), _present, 'Тонус', false)]);
      // Пакет о самом теге подтвердил предъявление: повтор чтения не нужен.
      h.package(4, [
        TagCreatedChange(revision: const _Revision(4), after: _tag(8, 'Быт')),
      ]);
      expect(h.reads.queries, hasLength(1));
    },
  );

  test(
    'пакет не новее подтверждённого чтения не откатывает название',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.rename(2, _tag(1, 'Здоровье'), 'Самочувствие');
      h.select(_tag(1, 'Здоровье'), _present, revision: 1);
      h.reads.tag(0, _tag(1, 'Тонус'), revision: 4);
      await pumpEventQueue();

      h.rename(3, _tag(1, 'Самочувствие'), 'Бодрость');

      expect(h.shown, [(_id(1), _present, 'Тонус', false)]);
    },
  );

  test('ответ чтения снятого условия не восстанавливает его', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.rename(2, _tag(1, 'Здоровье'), 'Самочувствие');
    h.select(_tag(1, 'Здоровье'), _present, revision: 1);
    h.model.remove(_id(1));

    h.reads.tag(0, _tag(1, 'Самочувствие'), revision: 2);
    await pumpEventQueue();
    expect(h.conditions, isEmpty);
    expect(h.appliedFilter, IntentionTagFilter.empty);

    // Условие, выбранное заново, не получает ответ прежнего чтения.
    h.rename(3, _tag(1, 'Самочувствие'), 'Тонус');
    h.select(_tag(1, 'Самочувствие'), _absent, revision: 2);
    h.model.remove(_id(1));
    h.select(_tag(1, 'Тонус'), _absent, revision: 3);
    h.reads.tag(1, _tag(1, 'Самочувствие'), revision: 3);
    await pumpEventQueue();
    expect(h.shown, [(_id(1), _absent, 'Тонус', false)]);
    expect(h.reads.queries, hasLength(2));
  });

  test('повторный выбор из более нового снимка обновляет название', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.package(2, [
      TagCreatedChange(revision: const _Revision(2), after: _tag(8, 'Быт')),
    ]);

    h.select(_tag(1, 'Самочувствие'), _absent, revision: 2);
    expect(h.shown, [(_id(1), _absent, 'Самочувствие', false)]);

    // Прежний снимок не возвращает уже подтверждённое название.
    h.select(_tag(1, 'Здоровье'), _present, revision: 1);
    expect(h.shown, [(_id(1), _present, 'Самочувствие', false)]);
    expect(h.reads.queries, isEmpty);
  });

  test('смена охвата и порядка каталога не меняет условия', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);
    h.select(_tag(2, 'Спорт'), _absent);
    final shown = h.shown;
    final filter = h.state.tagFilter;

    h.catalog.changeScope(IntentionScope.archived);
    h.catalog.changeOrder(IntentionCatalogOrder.createdAtAscending);

    expect(h.shown, shown);
    expect(h.catalog.selection.scope, IntentionScope.archived);
    expect(h.catalog.selection.tagFilter, filter);
  });

  test('условия разных назначений поиска независимы', () {
    final h = _Harness();
    addTearDown(h.dispose);
    const action = SelectDailyChoiceAction();
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
    expect(h.shown, [(_id(1), _present, 'Здоровье', false)]);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [_id(1)]));
    expect(
      h.container
          .read(intentionCatalogViewModelProvider(action).notifier)
          .selection
          .tagFilter,
      IntentionTagFilter(excludedTagIds: [_id(2)]),
    );
  });

  test('условия не сохраняются после закрытия своего поиска', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.select(_tag(1, 'Здоровье'), _present);

    h.subscription.close();
    await h.container.pump();
    final reopened = h.container.listen(h.provider, (_, _) {});
    addTearDown(reopened.close);

    expect(reopened.read().conditions, isEmpty);
    expect(h.appliedFilter, IntentionTagFilter.empty);
  });
}

final class _Harness {
  _Harness({int? knownRevision = 1}) {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: 100,
            prefetchRemaining: 30,
            filterDebounce: const Duration(minutes: 1),
          ),
        ),
        intentionTagConditionsReaderProvider.overrideWithValue(reads),
        intentionTagConditionsChangesProvider.overrideWithValue(changes.stream),
      ],
      retry: (retryCount, error) => null,
    );
    subscription = container.listen(provider, (_, _) {});
    if (knownRevision != null) {
      // Модель знает подтверждённую ревизию графа из постороннего пакета.
      package(knownRevision, [
        TagCreatedChange(
          revision: _Revision(knownRevision),
          after: _tag(99, 'Посторонний'),
        ),
      ]);
    }
  }

  static const purpose = BrowseIntentionCatalog();

  final provider = intentionTagConditionsViewModelProvider(purpose);
  final repository = ControlledCatalogRepository();
  final reads = _TagReads();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
    sync: true,
  );
  late final ProviderContainer container;
  late final ProviderSubscription<IntentionTagConditionsState> subscription;

  IntentionTagConditionsViewModel get model =>
      container.read(provider.notifier);
  IntentionTagConditionsState get state => container.read(provider);
  List<IntentionTagCondition> get conditions => state.conditions;
  List<(TagId, IntentionTagRequirement, String, bool)> get shown => [
    for (final condition in conditions)
      (
        condition.tagId,
        condition.requirement,
        condition.name.value,
        condition.isDeleted,
      ),
  ];

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

  void package(int revision, List<GraphChange> packageChanges) =>
      changes.add(_Package(_Revision(revision), packageChanges));

  void rename(int revision, Tag before, String name) => package(revision, [
    TagRenamedChange(
      revision: _Revision(revision),
      before: before,
      after: Tag(id: before.id, name: TagName.fromInput(name)),
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

final class _TagReads extends Fake implements TagReadContract {
  final queries = <TagId>[];
  final _results = <Completer<TagReadResult>>[];

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    queries.add(id);
    final result = Completer<TagReadResult>();
    _results.add(result);
    return Stream.fromFuture(result.future);
  }

  void tag(int index, Tag? tag, {required int revision}) =>
      _results[index].complete(
        TagReadSuccess(
          GraphSnapshot(value: tag, revision: _Revision(revision)),
        ),
      );

  void fail(int index, TagReadFailure failure) =>
      _results[index].complete(TagReadError(failure));

  void throwError(int index) =>
      _results[index].completeError(StateError('Контролируемый сбой чтения.'));
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

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
