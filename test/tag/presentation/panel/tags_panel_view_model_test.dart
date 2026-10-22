import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_context.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_state.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_assignment_changed.dart';
import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_positions.dart';

void main() {
  test('Фоновое обновление сохраняет список', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete(
      [_tag(1, 'Дом'), _tag(2, 'Работа')],
      assignedIds: {_id(1)},
    );
    await pumpEventQueue();

    h.changes.add(ConfirmedGraphReplacement(const TagCatalogTestRevision(2)));
    await pumpEventQueue();
    expect(h.repository.reads, hasLength(2));
    expect(_names(panel.loaded), ['Дом', 'Работа']);
    expect(panel.loaded.rows.map((row) => row.isMarked), [true, false]);
    expect(panel.loaded.rowsAreCurrent, isTrue);

    h.repository.fail(const TagCatalogUnavailableFailure());
    await pumpEventQueue();
    expect(_names(panel.loaded), ['Дом', 'Работа']);
    expect(panel.loaded.rowsAreCurrent, isFalse);
    expect(panel.loaded.refreshFailure, isA<TagCatalogUnavailableFailure>());

    panel.model.retryRefresh();
    await pumpEventQueue();
    expect(h.repository.reads, hasLength(3));
    expect(_names(panel.loaded), ['Дом', 'Работа']);
    expect(panel.loaded.rowsAreCurrent, isFalse);

    h.repository.complete(
      [_tag(1, 'Дом'), _tag(2, 'Работа')],
      revision: 2,
      assignedIds: {_id(1)},
    );
    await pumpEventQueue();
    expect(_names(panel.loaded), ['Дом', 'Работа']);
    expect(panel.loaded.rowsAreCurrent, isTrue);
  });

  test('Запоздалое чтение после изменения тега', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    h.changes.add(ConfirmedGraphReplacement(const TagCatalogTestRevision(2)));
    await pumpEventQueue();

    final renamed = _tag(1, 'Быт', color: TagColor.blue);
    h.changes.add(
      _package(
        3,
        TagUpdated(
          TagUpdatedChange(
            revision: const TagCatalogTestRevision(3),
            before: _tag(1, 'Дом'),
            after: renamed,
          ),
        ),
      ),
    );
    await pumpEventQueue();
    h.repository.complete([_tag(1, 'Дом')], revision: 2, assignedIds: {});
    await pumpEventQueue();

    expect(_names(panel.loaded), ['Быт']);
    expect(panel.loaded.rows.single.tag.color, TagColor.blue);
    expect(h.repository.reads, hasLength(3));
  });

  test('Неизвестный отказ получения каталога', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.reads.last.completeError(StateError('сбой драйвера'));
    await pumpEventQueue();

    final failure = panel.state.catalog as TagsPanelLoadFailure;
    expect(failure.failure, isA<TagCatalogUnexpectedFailure>());
    expect(failure.canRetry, isFalse);
    panel.model.retryLoad();
    await pumpEventQueue();
    expect(h.repository.reads, hasLength(1));
  });

  test(
    'устранимый отказ первоначального чтения повторяется с поиском',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final panel = h.open();
      panel.model.search('дом');
      h.repository.fail(const TagCatalogUnavailableFailure());
      await pumpEventQueue();
      expect((panel.state.catalog as TagsPanelLoadFailure).canRetry, isTrue);

      panel.model.retryLoad();
      expect(panel.state.catalog, isA<TagsPanelLoading>());
      h.repository.complete([
        _tag(1, 'Работа'),
        _tag(2, 'Дом'),
      ], assignedIds: {});
      await pumpEventQueue();
      expect(_visibleNames(panel), ['Дом']);
    },
  );

  test(
    'Обновление сохраняет поиск и применяет его к актуальному каталогу',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final panel = h.open();
      h.repository.complete([
        _tag(1, 'Дом'),
        _tag(2, 'Для дома'),
        _tag(3, 'Работа'),
      ], assignedIds: {});
      await pumpEventQueue();
      panel.model.search('дом');
      expect(_visibleNames(panel), ['Дом', 'Для дома']);

      h.changes.add(
        _package(
          2,
          TagUpdated(
            TagUpdatedChange(
              revision: const TagCatalogTestRevision(2),
              before: _tag(1, 'Дом'),
              after: _tag(1, 'Спорт'),
            ),
          ),
        ),
      );
      await pumpEventQueue();

      expect(_visibleNames(panel), ['Для дома']);
      expect(panel.state.search.inputIsInvalid, isFalse);
      expect(h.repository.reads, hasLength(1));
    },
  );

  test('Повтор чтения сохраняет запрос', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Дом'), _tag(3, 'Работа')], assignedIds: {});
    await pumpEventQueue();
    panel.model.search('дом');
    h.changes.add(ConfirmedGraphReplacement(const TagCatalogTestRevision(2)));
    await pumpEventQueue();
    h.repository.fail(const TagCatalogUnavailableFailure());
    await pumpEventQueue();

    panel.model.retryRefresh();
    h.repository.complete(
      [_tag(1, 'Дом'), _tag(2, 'Для дома'), _tag(3, 'Работа')],
      revision: 2,
      assignedIds: {},
    );
    await pumpEventQueue();

    expect(_visibleNames(panel), ['Дом', 'Для дома']);
    expect(panel.loaded.rowsAreCurrent, isTrue);
  });

  test('Некорректный ввод сохраняет последний корректный фильтр', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([
      _tag(1, 'Работа'),
      _tag(2, 'Дом'),
      _tag(3, 'Для дома'),
    ], assignedIds: {});
    await pumpEventQueue();
    panel.model.search('дом');

    panel.model.search('до\u0000м');

    expect(panel.state.search.inputIsInvalid, isTrue);
    expect(_visibleNames(panel), ['Дом', 'Для дома']);
  });

  test('Запрос из одних пробелов не сужает список', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')], assignedIds: {});
    await pumpEventQueue();

    panel.model.search('   ');

    expect(panel.state.search.inputIsInvalid, isFalse);
    expect(_visibleNames(panel), ['Работа', 'Дом']);
  });

  test(
    'подтверждённые изменения тегов и назначений применяются без чтения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final panel = h.open();
      h.repository.complete([
        _tag(5, 'Дом'),
        _tag(7, 'Работа'),
      ], assignedIds: {});
      await pumpEventQueue();

      h.changes.add(
        _package(
          2,
          TagCreated(
            TagCreatedChange(
              revision: const TagCatalogTestRevision(2),
              after: _tag(1, 'Спорт'),
            ),
          ),
        ),
      );
      await pumpEventQueue();
      expect(_names(panel.loaded), ['Спорт', 'Дом', 'Работа']);
      expect(panel.loaded.rows.first.isMarked, isFalse);

      h.changes
        ..add(_assignment(3, _id(7), _intentionId))
        ..add(_assignment(4, _id(5), _otherIntentionId))
        ..add(
          _package(
            5,
            TagDeleted(
              TagDeletedChange(
                revision: const TagCatalogTestRevision(5),
                tagId: _id(5),
              ),
            ),
          ),
        );
      await pumpEventQueue();
      expect(_names(panel.loaded), ['Спорт', 'Работа']);
      expect(panel.loaded.rows.map((row) => row.isMarked), [false, true]);
      expect(panel.loaded.rowsAreCurrent, isTrue);
      expect(h.repository.reads, hasLength(1));
    },
  );

  test('отсутствие намерения отличается от пустого каталога', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.fail(const TagCatalogIntentionNotFound());
    await pumpEventQueue();
    expect(panel.state.catalog, isA<TagsPanelIntentionMissing>());

    h.changes.add(ConfirmedGraphReplacement(const TagCatalogTestRevision(2)));
    await pumpEventQueue();
    expect(panel.state.catalog, isA<TagsPanelIntentionMissing>());
    expect(h.repository.reads, hasLength(1));
  });

  test('Новое открытие начинает поиск заново', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final first = h.open();
    h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    first.model.search('дом');
    first.model.search('\u0000');
    first.close();
    await pumpEventQueue();

    final second = h.open();
    h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')], assignedIds: {});
    await pumpEventQueue();

    expect(second.state.search.filter.isEmpty, isTrue);
    expect(second.state.search.inputIsInvalid, isFalse);
    expect(_visibleNames(second), ['Работа', 'Дом']);
  });
}

final _intentionId = _intention(1);
final _otherIntentionId = _intention(2);

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        tagsPanelChangesProvider.overrideWithValue(changes.stream),
      ],
    );
  }

  final repository = TagCatalogTestRepository();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast();
  late final ProviderContainer container;

  _Panel open() => _Panel(
    container,
    TagsPanelOpening(TagsPanelAssignmentContext(_intentionId)),
  );

  Future<void> dispose() async {
    container.dispose();
    await changes.close();
  }
}

final class _Panel {
  _Panel(this.container, TagsPanelOpening opening)
    : provider = tagsPanelViewModelProvider(opening) {
    subscription = container.listen(provider, (_, _) {});
  }

  final ProviderContainer container;
  final TagsPanelViewModelProvider provider;
  late final ProviderSubscription<TagsPanelState> subscription;

  TagsPanelViewModel get model => container.read(provider.notifier);
  TagsPanelState get state => container.read(provider);
  TagsPanelLoaded get loaded => state.catalog as TagsPanelLoaded;

  void close() => subscription.close();
}

List<String> _names(TagsPanelLoaded loaded) => [
  for (final row in loaded.rows) row.tag.name.value,
];

List<String> _visibleNames(_Panel panel) => [
  for (final row in panel.loaded.rowsMatching(panel.state.search.filter))
    row.tag.name.value,
];

ConfirmedGraphResult<TagCommandSuccess> _package(
  int revision,
  TagCommandSuccess success,
) => ConfirmedGraphResult(
  revision: TagCatalogTestRevision(revision),
  value: success,
);

ConfirmedGraphResult<TagCommandSuccess> _assignment(
  int revision,
  TagId tagId,
  IntentionId intentionId,
) => _package(
  revision,
  testTagAssignmentChanged(
    TagAssignmentChangedChange(
      revision: TagCatalogTestRevision(revision),
      assignment: TagAssignment(tagId: tagId, intentionId: intentionId),
      state: TagAssignmentState.assigned,
    ),
  ),
);

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) => (IntentionId.decode(
  '00000000-0000-4000-9000-${number.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

/// Номер задаёт и идентичность, и место тега в ручном порядке.
Tag _tag(int number, String name, {TagColor? color}) => Tag(
  id: _id(number),
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(number),
);
