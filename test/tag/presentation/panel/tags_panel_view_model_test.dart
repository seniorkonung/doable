import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/editor/intention_draft_tag_set.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_view_model.dart';
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
    expect(_marks(panel), [true, false]);
    expect(panel.loaded.rowsAreCurrent, isTrue);

    h.repository.fail(const TagCatalogUnavailableFailure());
    await pumpEventQueue();
    expect(_names(panel.loaded), ['Дом', 'Работа']);
    expect(panel.loaded.rowsAreCurrent, isFalse);
    expect(panel.loaded.refreshFailure, TagsPanelReadFailure.unavailable);

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
    h.repository.fail(const TagCatalogUnexpectedFailure());
    await pumpEventQueue();

    final failure = panel.state.catalog as TagsPanelLoadFailure;
    expect(failure.failure, TagsPanelReadFailure.unexpected);
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
      expect(_marks(panel).first, isFalse);

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
      expect(_marks(panel), [false, true]);
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

  test('Нажатие сразу назначает и снимает тег', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete(
      [_tag(1, 'Дом'), _tag(2, 'Работа')],
      assignedIds: {_id(1)},
    );
    await pumpEventQueue();

    expect(panel.model.toggle(_id(2)), isA<TagCommandAccepted>());
    await pumpEventQueue();
    final assign = h.repository.commands.single as AssignTag;
    expect((assign.tagId, assign.intentionId), (_id(2), _intentionId));
    expect(_marks(panel), [true, false]);
    h.repository.command.complete(
      TagCommandSucceeded(_assignment(2, _id(2), _intentionId)),
    );
    await pumpEventQueue();
    expect(_marks(panel), [true, true]);

    expect(panel.model.toggle(_id(1)), isA<TagCommandAccepted>());
    await pumpEventQueue();
    final remove = h.repository.commands.last as RemoveTagAssignment;
    expect((remove.tagId, remove.intentionId), (_id(1), _intentionId));
    h.repository.command.complete(
      TagCommandSucceeded(
        _assignment(3, _id(1), _intentionId, state: TagAssignmentState.absent),
      ),
    );
    await pumpEventQueue();

    expect(_marks(panel), [false, true]);
    expect(h.repository.reads, hasLength(1));
  });

  test('Отказ записи оставляет прежнюю отметку', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete(
      [_tag(1, 'Дом'), _tag(2, 'Работа')],
      assignedIds: {_id(1)},
    );
    await pumpEventQueue();

    final accepted = panel.model.toggle(_id(2)) as TagCommandAccepted;
    await pumpEventQueue();
    h.repository.command.complete(
      const TagCommandFailed(TagUnavailableFailure()),
    );
    await accepted.future;
    await pumpEventQueue();

    expect(_marks(panel), [true, false]);
    expect(panel.loaded.rowsAreCurrent, isTrue);
    expect(h.repository.reads, hasLength(1));
  });

  test(
    'нажатие во время изменения назначений намерения отклоняется без очереди',
    () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final panel = h.open();
      h.repository.complete(
        [_tag(1, 'Дом'), _tag(2, 'Работа')],
        assignedIds: {_id(1)},
      );
      await pumpEventQueue();
      expect(panel.model.toggle(_id(2)), isA<TagCommandAccepted>());
      await pumpEventQueue();

      expect(panel.model.toggle(_id(1)), isA<TagCommandAlreadyRunning>());
      expect(_marks(panel), [true, false]);

      h.repository.command.complete(
        TagCommandSucceeded(_assignment(2, _id(2), _intentionId)),
      );
      await pumpEventQueue();
      expect(_marks(panel), [true, true]);
      expect(h.repository.commands, hasLength(1));
    },
  );

  test('нажатие недоступно на неактуальных строках и без намерения', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    h.changes.add(ConfirmedGraphReplacement(const TagCatalogTestRevision(2)));
    await pumpEventQueue();
    h.repository.fail(const TagCatalogUnavailableFailure());
    await pumpEventQueue();
    expect(panel.loaded.rowsAreCurrent, isFalse);

    expect(panel.model.toggle(_id(1)), isNull);

    panel.model.retryRefresh();
    h.repository.fail(const TagCatalogIntentionNotFound());
    await pumpEventQueue();
    expect(panel.state.catalog, isA<TagsPanelIntentionMissing>());
    expect(panel.model.toggle(_id(1)), isNull);
    await pumpEventQueue();
    expect(h.repository.commands, isEmpty);
  });

  test('принятое назначение завершается после закрытия панели', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    final accepted = panel.model.toggle(_id(1)) as TagCommandAccepted;
    await pumpEventQueue();

    panel.close();
    await pumpEventQueue();
    h.repository.command.complete(
      TagCommandSucceeded(_assignment(2, _id(1), _intentionId)),
    );

    expect(await accepted.future, isA<TagCommandSucceededCompletion>());
    expect(h.coordinator.isRunning(_intentionId), isFalse);
  });

  test('Строка создания предлагает название из поиска', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    expect(_proposedName(panel), isNull);

    panel.model.search('  Парк ');
    expect(_proposedName(panel), 'Парк');
    expect(_visibleNames(panel), isEmpty);

    panel.model.search('Па\u0000рк');
    expect(_proposedName(panel), 'Парк');
  });

  test('Совпадающее название не предлагает создание', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Дом'), _tag(2, 'Домик')], assignedIds: {});
    await pumpEventQueue();

    panel.model.search('  дом  ');

    expect(_visibleNames(panel), ['Дом', 'Домик']);
    expect(_proposedName(panel), isNull);
  });

  test(
    'Новый тег встаёт первым и очищает поиск; Созданный тег сразу назначен',
    () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final panel = h.open();
      h.repository.complete([
        _tag(5, 'Дом'),
        _tag(7, 'Работа'),
      ], assignedIds: {});
      await pumpEventQueue();
      panel.model.search('парк');

      panel.model.acceptCreation(h.acceptCreation('парк'));
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(_created(2, 1, 'парк')),
      );
      await pumpEventQueue();

      expect(panel.state.search.filter.isEmpty, isTrue);
      expect(_visibleNames(panel), ['парк', 'Дом', 'Работа']);
      final assign = h.repository.commands.last as AssignTag;
      expect((assign.tagId, assign.intentionId), (_id(1), _intentionId));
      expect(_marks(panel), [false, false, false]);

      h.repository.command.complete(
        TagCommandSucceeded(_assignment(3, _id(1), _intentionId)),
      );
      await pumpEventQueue();
      expect(_marks(panel), [true, false, false]);
      expect(h.repository.reads, hasLength(1));
    },
  );

  test('Закрытие листа до подтверждения создания', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(5, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    panel.model.search('Спорт');
    final sheet = tagEditorViewModelProvider(
      TagEditorCreating(
        TagCreationFormKey(),
        initialName: 'Спорт',
        initialColor: null,
        placement: TagPlacement.first,
        existingNames: [for (final row in panel.loaded.rows) row.tag.name],
        onCreationAccepted: panel.model.acceptCreation,
      ),
    );
    final sheetSubscription = h.container.listen(sheet, (_, _) {});
    unawaited(h.container.read(sheet.notifier).submit());
    await pumpEventQueue();

    h.container.read(sheet.notifier).closeSession();
    sheetSubscription.close();
    await pumpEventQueue();
    h.repository.command.complete(TagCommandSucceeded(_created(2, 1, 'Спорт')));
    await pumpEventQueue();
    h.repository.command.complete(
      TagCommandSucceeded(_assignment(3, _id(1), _intentionId)),
    );
    await pumpEventQueue();

    expect(h.repository.commands.whereType<AssignTag>(), hasLength(1));
    expect(_names(panel.loaded), ['Спорт', 'Дом']);
    expect(_marks(panel), [true, false]);
    expect(panel.state.search.filter.isEmpty, isTrue);
  });

  test('Занятое название пропускается', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([
      _tag(1, 'Работа'),
      _tag(2, 'Дом', color: TagColor.blue),
      _tag(3, 'Дом 2'),
      _tag(4, 'дом 3'),
    ], assignedIds: {});
    await pumpEventQueue();

    final copy = panel.loaded.duplicationOf(_id(2))!;
    expect(copy.name, 'Дом 4');
    expect(copy.color, TagColor.blue);
    expect((copy.placement as AfterTagPlacement).tagId, _id(2));

    final first = panel.loaded.duplicationOf(_id(1))!;
    expect((first.name, first.color), ('Работа 2', null));
  });

  test('Копия встаёт после оригинала без его назначений', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([
      _tag(5, 'Работа'),
      _tag(7, 'Дом', color: TagColor.blue),
      _tag(9, 'Спорт'),
    ], assignedIds: {});
    await pumpEventQueue();
    panel.model.search('дом');
    final copy = panel.loaded.duplicationOf(_id(7))!;
    final sheet = tagEditorViewModelProvider(
      TagEditorCreating(
        TagCreationFormKey(),
        initialName: copy.name,
        initialColor: copy.color,
        placement: copy.placement,
        existingNames: [for (final row in panel.loaded.rows) row.tag.name],
        onCreationAccepted: panel.model.acceptCreation,
      ),
    );
    final sheetSubscription = h.container.listen(sheet, (_, _) {});
    addTearDown(sheetSubscription.close);
    unawaited(h.container.read(sheet.notifier).submit());
    await pumpEventQueue();

    final create = h.repository.commands.single as CreateTag;
    expect((create.name.value, create.color), ('Дом 2', TagColor.blue));
    expect((create.placement as AfterTagPlacement).tagId, _id(7));
    h.repository.command.complete(
      TagCommandSucceeded(_created(2, 1, 'Дом 2', color: TagColor.blue, at: 8)),
    );
    await pumpEventQueue();
    h.repository.command.complete(
      TagCommandSucceeded(_assignment(3, _id(1), _intentionId)),
    );
    await pumpEventQueue();

    expect(panel.state.search.filter.isEmpty, isTrue);
    expect(_names(panel.loaded), ['Работа', 'Дом', 'Дом 2', 'Спорт']);
    expect(_marks(panel), [false, false, true, false]);
    final assign = h.repository.commands.whereType<AssignTag>().single;
    expect((assign.tagId, assign.intentionId), (_id(1), _intentionId));
  });

  test('Подтверждённая запись и ошибка обновления', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(5, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    panel.model.search('парк');
    panel.model.acceptCreation(h.acceptCreation('парк'));
    await pumpEventQueue();
    final created = _created(2, 1, 'парк');
    h.repository.command.complete(TagCommandSucceeded(created));
    h.changes.add(created);
    await pumpEventQueue();

    h.changes.add(ConfirmedGraphReplacement(const TagCatalogTestRevision(3)));
    await pumpEventQueue();
    h.repository.fail(const TagCatalogUnavailableFailure());
    await pumpEventQueue();

    expect(panel.loaded.refreshFailure, TagsPanelReadFailure.unavailable);
    expect(_names(panel.loaded), ['парк', 'Дом']);
    panel.model.search('парк');
    expect(_proposedName(panel), isNull);
    expect(h.repository.commands.whereType<CreateTag>(), hasLength(1));
  });

  test(
    'закрытие панели до подтверждения создания оставляет тег неотмеченным',
    () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final first = h.open();
      h.repository.complete([_tag(5, 'Дом')], assignedIds: {});
      await pumpEventQueue();
      first.model.search('парк');
      first.model.acceptCreation(h.acceptCreation('парк'));
      await pumpEventQueue();

      first.close();
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(_created(2, 1, 'парк')),
      );
      await pumpEventQueue();
      expect(h.repository.commands.single, isA<CreateTag>());

      final second = h.open();
      h.repository.complete(
        [_tag(1, 'парк'), _tag(5, 'Дом')],
        revision: 2,
        assignedIds: {},
      );
      await pumpEventQueue();
      expect(second.state.search.filter.isEmpty, isTrue);
      expect(_marks(second), [false, false]);
      expect(h.repository.commands, hasLength(1));
    },
  );

  test('отказ или отклонение назначения созданного тега', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(5, 'Дом')], assignedIds: {});
    await pumpEventQueue();

    panel.model.acceptCreation(h.acceptCreation('парк'));
    await pumpEventQueue();
    h.repository.command.complete(TagCommandSucceeded(_created(2, 1, 'парк')));
    await pumpEventQueue();
    h.repository.command.complete(
      const TagCommandFailed(TagUnavailableFailure()),
    );
    await pumpEventQueue();
    expect(_marks(panel), [false, false]);

    // Назначение намерения, принятое до подтверждения создания, занимает
    // ключ намерения, и координатор отклоняет назначение созданного тега.
    panel.model.acceptCreation(h.acceptCreation('сад'));
    await pumpEventQueue();
    final creation = h.repository.commandResults.last;
    expect(panel.model.toggle(_id(5)), isA<TagCommandAccepted>());
    await pumpEventQueue();
    creation.complete(TagCommandSucceeded(_created(3, 2, 'сад')));
    await pumpEventQueue();

    expect(h.repository.commands.whereType<AssignTag>(), hasLength(2));
    expect(_names(panel.loaded), ['парк', 'сад', 'Дом']);
    expect(_marks(panel), [false, false, false]);
  });

  test(
    'перестановка в начало, в конец и между соседями сохраняет отметки',
    () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final panel = h.open();
      h.repository.complete(
        [_tag(2, 'Работа'), _tag(4, 'Дом'), _tag(6, 'Спорт')],
        assignedIds: {_id(2)},
      );
      await pumpEventQueue();

      expect(panel.model.move(_id(6), 0), isA<TagCommandAccepted>());
      expect(_names(panel.loaded), ['Спорт', 'Работа', 'Дом']);
      expect(_marks(panel), [false, true, false]);
      await pumpEventQueue();
      final first = h.repository.commands.last as MoveTag;
      expect((first.tagId, first.placement), (_id(6), TagPlacement.first));
      h.repository.command.complete(
        TagCommandSucceeded(_moved(2, _tag(6, 'Спорт'), at: 0)),
      );
      await pumpEventQueue();
      expect(_names(panel.loaded), ['Спорт', 'Работа', 'Дом']);

      expect(panel.model.move(_id(6), 2), isA<TagCommandAccepted>());
      expect(_names(panel.loaded), ['Работа', 'Дом', 'Спорт']);
      await pumpEventQueue();
      final last = h.repository.commands.last as MoveTag;
      expect(last.tagId, _id(6));
      expect((last.placement as AfterTagPlacement).tagId, _id(4));
      h.repository.command.complete(
        TagCommandSucceeded(_moved(3, _tag(6, 'Спорт', at: 0), at: 8)),
      );
      await pumpEventQueue();

      expect(panel.model.move(_id(2), 1), isA<TagCommandAccepted>());
      expect(_names(panel.loaded), ['Дом', 'Работа', 'Спорт']);
      await pumpEventQueue();
      final between = h.repository.commands.last as MoveTag;
      expect(between.tagId, _id(2));
      expect((between.placement as AfterTagPlacement).tagId, _id(4));
      h.repository.command.complete(
        TagCommandSucceeded(_moved(4, _tag(2, 'Работа'), at: 5)),
      );
      await pumpEventQueue();

      expect(_names(panel.loaded), ['Дом', 'Работа', 'Спорт']);
      expect(_marks(panel), [false, true, false]);
      expect(panel.loaded.pendingMove, isNull);
      expect(panel.state.canReorder, isTrue);
      expect(h.repository.commands, hasLength(3));
      expect(h.repository.reads, hasLength(1));
    },
  );

  test('Отказ записи перестановки возвращает прежний порядок', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete(
      [_tag(1, 'Работа'), _tag(2, 'Дом'), _tag(3, 'Спорт')],
      assignedIds: {_id(3)},
    );
    await pumpEventQueue();

    final accepted = panel.model.move(_id(3), 0) as TagCommandAccepted;
    expect(_names(panel.loaded), ['Спорт', 'Работа', 'Дом']);
    await pumpEventQueue();
    h.repository.command.complete(
      const TagCommandFailed(TagUnavailableFailure()),
    );
    expect(await accepted.future, isA<TagCommandFailedCompletion>());
    await pumpEventQueue();

    expect(_names(panel.loaded), ['Работа', 'Дом', 'Спорт']);
    expect(_marks(panel), [false, false, true]);
    expect(panel.state.canReorder, isTrue);
    expect(h.repository.reads, hasLength(1));
  });

  test('непринятая перестановка не меняет порядок', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    h.coordinator.acceptTagUpdate(
      UpdateTag(tagId: _id(2), name: TagName.fromInput('Быт'), color: null),
    );
    await pumpEventQueue();

    expect(panel.model.move(_id(2), 0), isA<TagCommandAlreadyRunning>());

    expect(_names(panel.loaded), ['Работа', 'Дом']);
    expect(panel.state.canReorder, isTrue);
    expect(h.repository.commands.whereType<MoveTag>(), isEmpty);
  });

  test('Поиск отключает перестановку', () async {
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

    expect(panel.state.canReorder, isFalse);
    expect(panel.model.move(_id(3), 0), isNull);

    expect(_names(panel.loaded), ['Работа', 'Дом', 'Для дома']);
    expect(_visibleNames(panel), ['Дом', 'Для дома']);
    await pumpEventQueue();
    expect(h.repository.commands, isEmpty);
  });

  test('перестановка недоступна, пока выполняется предыдущая', () async {
    final h = _Harness.confirmedByCoordinator();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([
      _tag(1, 'Работа'),
      _tag(2, 'Дом'),
      _tag(3, 'Спорт'),
    ], assignedIds: {});
    await pumpEventQueue();

    expect(panel.model.move(_id(3), 0), isA<TagCommandAccepted>());
    expect(panel.state.canReorder, isFalse);
    expect(panel.model.move(_id(2), 0), isNull);
    expect(_names(panel.loaded), ['Спорт', 'Работа', 'Дом']);
    await pumpEventQueue();
    expect(h.repository.commands, hasLength(1));

    h.repository.command.complete(
      TagCommandSucceeded(_moved(2, _tag(3, 'Спорт'), at: 0)),
    );
    await pumpEventQueue();
    expect(panel.state.canReorder, isTrue);
  });

  test('перестановка недоступна на неактуальных строках', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final panel = h.open();
    h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')], assignedIds: {});
    await pumpEventQueue();
    h.changes.add(ConfirmedGraphReplacement(const TagCatalogTestRevision(2)));
    await pumpEventQueue();
    h.repository.fail(const TagCatalogUnavailableFailure());
    await pumpEventQueue();

    expect(panel.state.canReorder, isFalse);
    expect(panel.model.move(_id(2), 0), isNull);
    expect(_names(panel.loaded), ['Работа', 'Дом']);
    await pumpEventQueue();
    expect(h.repository.commands, isEmpty);
  });

  group('черновик создания намерения', () {
    test(
      'отметки показывают набор черновика и следуют за его изменениями',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        final draft = h.openDraft()..tagSet.add(_tag(1, 'Дом'));
        final panel = draft.open();
        expect(h.repository.readModes.single, isA<TagCatalogBrowseMode>());
        h.repository.complete([
          _tag(1, 'Дом'),
          _tag(2, 'Работа'),
          _tag(3, 'Выходные'),
        ]);
        await pumpEventQueue();
        expect(_marks(panel), [true, false, false]);

        draft.tagSet
          ..add(_tag(3, 'Выходные'))
          ..remove(_id(1));
        await pumpEventQueue();

        expect(_marks(panel), [false, false, true]);
        expect(h.repository.reads, hasLength(1));
      },
    );

    test('нажатие включает и исключает тег без команд графа, а повторное '
        'включение оставляет одно включение', () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final draft = h.openDraft()..tagSet.add(_tag(1, 'Дом'));
      final panel = draft.open();
      h.repository.complete([_tag(1, 'Дом'), _tag(2, 'Работа')]);
      await pumpEventQueue();

      expect(panel.model.toggle(_id(2)), isNull);
      await pumpEventQueue();
      expect(draft.tagSet.current, [_id(1), _id(2)]);
      expect(_marks(panel), [true, true]);

      panel.model.toggle(_id(1));
      await pumpEventQueue();
      expect(draft.tagSet.current, [_id(2)]);
      expect(_marks(panel), [false, true]);

      // Второе нажатие раньше обновления отметки приходится на неотмеченную
      // строку и снова включает тот же тег.
      panel.model
        ..toggle(_id(1))
        ..toggle(_id(1));
      await pumpEventQueue();
      expect(draft.tagSet.current, [_id(2), _id(1)]);
      expect(_marks(panel), [true, true]);
      expect(h.repository.commands, isEmpty);
    });

    test('Поиск скрывает включённый тег без снятия выбора', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = h.openDraft()..tagSet.add(_tag(1, 'Дом'));
      final panel = draft.open();
      h.repository.complete([_tag(1, 'Дом'), _tag(2, 'Работа')]);
      await pumpEventQueue();

      panel.model.search('работ');
      expect(_visibleNames(panel), ['Работа']);
      panel.model.search('парк');
      expect(_visibleNames(panel), isEmpty);
      panel.model.search('');
      await pumpEventQueue();

      expect(draft.tagSet.current, [_id(1)]);
      expect(_marks(panel), [true, false]);
    });

    test('Возврат из редактора сохраняет поиск черновика', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final draft = h.openDraft()..tagSet.add(_tag(2, 'Для дома'));
      final panel = draft.open();
      h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Для дома')]);
      await pumpEventQueue();
      panel.model.search('дом');

      h.changes.add(
        _package(
          2,
          TagUpdated(
            TagUpdatedChange(
              revision: const TagCatalogTestRevision(2),
              before: _tag(2, 'Для дома'),
              after: _tag(2, 'Для дома', color: TagColor.blue),
            ),
          ),
        ),
      );
      await pumpEventQueue();

      expect(panel.state.search.filter.query, 'дом');
      final row = panel.loaded.rowsMatching(panel.state.search.filter).single;
      expect((row.tag.name.value, row.tag.color), ('Для дома', TagColor.blue));
      expect(row.mark, TagsPanelSelectionMark.marked);
      expect(draft.tagSet.current, [_id(2)]);
    });

    test('созданный и продублированный тег включается в набор один раз, в том '
        'числе после закрытия листа', () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final draft = h.openDraft();
      final panel = draft.open();
      h.repository.complete([_tag(5, 'Дом')]);
      await pumpEventQueue();
      panel.model.search('парк');

      panel.model.acceptCreation(h.acceptCreation('парк'));
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(_created(2, 1, 'парк')),
      );
      await pumpEventQueue();
      expect(panel.state.search.filter.isEmpty, isTrue);
      expect(draft.tagSet.current, [_id(1)]);
      expect(_names(panel.loaded), ['парк', 'Дом']);
      expect(_marks(panel), [true, false]);

      final copy = panel.loaded.duplicationOf(_id(5))!;
      final sheet = tagEditorViewModelProvider(
        TagEditorCreating(
          TagCreationFormKey(),
          initialName: copy.name,
          initialColor: copy.color,
          placement: copy.placement,
          existingNames: [for (final row in panel.loaded.rows) row.tag.name],
          onCreationAccepted: panel.model.acceptCreation,
        ),
      );
      final sheetSubscription = h.container.listen(sheet, (_, _) {});
      unawaited(h.container.read(sheet.notifier).submit());
      await pumpEventQueue();
      h.container.read(sheet.notifier).closeSession();
      sheetSubscription.close();
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(_created(3, 2, 'Дом 2', at: 6)),
      );
      await pumpEventQueue();

      expect(draft.tagSet.current, [_id(1), _id(2)]);
      expect(_names(panel.loaded), ['парк', 'Дом', 'Дом 2']);
      expect(_marks(panel), [true, false, true]);
      expect(h.repository.commands, everyElement(isA<CreateTag>()));
    });

    test('закрытие панели до подтверждения создания не включает тег', () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final draft = h.openDraft();
      final panel = draft.open();
      h.repository.complete([_tag(5, 'Дом')]);
      await pumpEventQueue();
      panel.model.acceptCreation(h.acceptCreation('парк'));
      await pumpEventQueue();

      panel.close();
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(_created(2, 1, 'парк')),
      );
      await pumpEventQueue();

      expect(draft.tagSet.current, isEmpty);
    });

    test('Удалённый тег уходит из черновика', () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final draft = h.openDraft()
        ..tagSet.add(_tag(1, 'Дом'))
        ..tagSet.add(_tag(2, 'Работа'));
      final panel = draft.open();
      h.repository.complete([_tag(1, 'Дом'), _tag(2, 'Работа')]);
      await pumpEventQueue();

      panel.model.delete(_id(1));
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(
          _package(
            2,
            TagDeleted(
              TagDeletedChange(
                revision: const TagCatalogTestRevision(2),
                tagId: _id(1),
              ),
            ),
          ),
        ),
      );
      await pumpEventQueue();

      expect(_names(panel.loaded), ['Работа']);
      expect(_marks(panel), [true]);
      expect(draft.tagSet.current, [_id(2)]);
      expect(h.repository.reads, hasLength(1));
    });
  });

  group('фильтр поиска намерений', () {
    test('Открытая панель показывает текущие условия и следует за их '
        'изменениями', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final search = h.openFilter()
        ..cycle(_tag(1, 'Здоровье'))
        ..cycle(_tag(2, 'Спорт'))
        ..cycle(_tag(2, 'Спорт'));
      final panel = search.open();
      expect(h.repository.readModes.single, isA<TagCatalogBrowseMode>());
      // «Сбросить» видна по условиям, а не по загруженному каталогу.
      expect(panel.state.canClearConditions, isTrue);

      h.repository.complete([
        _tag(1, 'Здоровье'),
        _tag(2, 'Спорт'),
        _tag(3, 'Отдых'),
      ]);
      await pumpEventQueue();
      expect(_filterMarks(panel), [
        _present,
        _absent,
        TagsPanelFilterMark.none,
      ]);

      search.conditions.clear();
      await pumpEventQueue();
      expect(_filterMarks(panel), [
        TagsPanelFilterMark.none,
        TagsPanelFilterMark.none,
        TagsPanelFilterMark.none,
      ]);
      expect(panel.state.canClearConditions, isFalse);
      expect(h.repository.reads, hasLength(1));
    });

    test('созданный и продублированный тег становится условием «должен быть» '
        'один раз, в том числе после закрытия листа, без назначений', () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final search = h.openFilter();
      final panel = search.open();
      h.repository.complete([_tag(5, 'Дом')]);
      await pumpEventQueue();
      panel.model.search('парк');

      panel.model.acceptCreation(h.acceptCreation('парк'));
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(_created(2, 1, 'парк')),
      );
      await pumpEventQueue();
      expect(panel.state.search.filter.isEmpty, isTrue);
      expect(search.requirements, [
        (_id(1), IntentionTagRequirement.mustBePresent),
      ]);
      expect(_names(panel.loaded), ['парк', 'Дом']);
      expect(_filterMarks(panel), [_present, TagsPanelFilterMark.none]);

      final copy = panel.loaded.duplicationOf(_id(5))!;
      final sheet = tagEditorViewModelProvider(
        TagEditorCreating(
          TagCreationFormKey(),
          initialName: copy.name,
          initialColor: copy.color,
          placement: copy.placement,
          existingNames: [for (final row in panel.loaded.rows) row.tag.name],
          onCreationAccepted: panel.model.acceptCreation,
        ),
      );
      final sheetSubscription = h.container.listen(sheet, (_, _) {});
      unawaited(h.container.read(sheet.notifier).submit());
      await pumpEventQueue();
      h.container.read(sheet.notifier).closeSession();
      sheetSubscription.close();
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(_created(3, 2, 'Дом 2', at: 6)),
      );
      await pumpEventQueue();

      expect(search.requirements, [
        (_id(1), IntentionTagRequirement.mustBePresent),
        (_id(2), IntentionTagRequirement.mustBePresent),
      ]);
      expect(_names(panel.loaded), ['парк', 'Дом', 'Дом 2']);
      expect(_filterMarks(panel), [
        _present,
        TagsPanelFilterMark.none,
        _present,
      ]);
      expect(h.repository.commands, everyElement(isA<CreateTag>()));
    });

    test('снятие условия при удалении тега убирает его отметку, а остальные '
        'условия сохраняются', () async {
      final h = _Harness.confirmedByCoordinator();
      addTearDown(h.dispose);
      final search = h.openFilter()
        ..cycle(_tag(1, 'Здоровье'))
        ..cycle(_tag(2, 'Спорт'))
        ..cycle(_tag(2, 'Спорт'));
      final panel = search.open();
      h.repository.complete([_tag(1, 'Здоровье'), _tag(2, 'Спорт')]);
      await pumpEventQueue();

      panel.model.delete(_id(1));
      await pumpEventQueue();
      h.repository.command.complete(
        TagCommandSucceeded(
          _package(
            2,
            TagDeleted(
              TagDeletedChange(
                revision: const TagCatalogTestRevision(2),
                tagId: _id(1),
              ),
            ),
          ),
        ),
      );
      await pumpEventQueue();

      expect(search.requirements, [
        (_id(2), IntentionTagRequirement.mustBeAbsent),
      ]);
      expect(_names(panel.loaded), ['Спорт']);
      expect(_filterMarks(panel), [_absent]);
      expect(panel.state.canClearConditions, isTrue);
      expect(h.repository.reads, hasLength(1));
    });
  });
}

const _present = TagsPanelFilterMark.mustBePresent;
const _absent = TagsPanelFilterMark.mustBeAbsent;

final _intentionId = _intention(1);
final _otherIntentionId = _intention(2);

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        tagsPanelChangesProvider.overrideWithValue(changes.stream),
        intentionTagConditionsChangesProvider.overrideWithValue(changes.stream),
      ],
    );
  }

  /// Подтверждённые пакеты приходят от координатора графа, исполнившего
  /// команды панели.
  _Harness.confirmedByCoordinator() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }

  final repository = TagCatalogTestRepository();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast();
  late final ProviderContainer container;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  TagCommandAccepted acceptCreation(String name) =>
      coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(
          name: TagName.fromInput(name),
          color: null,
          placement: TagPlacement.first,
        ),
      ) as TagCommandAccepted;

  _Panel open() => _Panel(
    container,
    TagsPanelOpening(TagsPanelAssignmentContext(_intentionId)),
  );

  /// Сессия создания намерения в том же контейнере, из которой открывается
  /// панель в контексте её черновика.
  _DraftSession openDraft() {
    final session = intentionEditorViewModelProvider(
      IntentionCreationFormKey(),
    );
    container.listen(session, (_, _) {});
    return _DraftSession(
      container,
      container.read(session.notifier).draftTagSet,
    );
  }

  /// Условия поиска каталога намерений в том же контейнере, над которыми
  /// открывается панель фильтра.
  _FilterSearch openFilter() {
    final provider = intentionTagConditionsViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    container.listen(provider, (_, _) {});
    return _FilterSearch(container, container.read(provider.notifier));
  }

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

final class _DraftSession {
  _DraftSession(this.container, this.tagSet);

  final ProviderContainer container;
  final IntentionDraftTagSet tagSet;

  _Panel open() =>
      _Panel(container, TagsPanelOpening(TagsPanelDraftContext(tagSet)));
}

final class _FilterSearch {
  _FilterSearch(this.container, this.conditions);

  final ProviderContainer container;
  final IntentionTagConditionSet conditions;

  _Panel open() =>
      _Panel(container, TagsPanelOpening(TagsPanelFilterContext(conditions)));

  void cycle(Tag tag) =>
      conditions.cycle(tag, snapshotRevision: const TagCatalogTestRevision());

  List<(TagId, IntentionTagRequirement)> get requirements => [
    for (final condition in conditions.current.conditions)
      (condition.tagId, condition.requirement),
  ];
}

List<TagsPanelMark> _filterMarks(_Panel panel) => [
  for (final row in panel.loaded.rows) row.mark,
];

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
  IntentionId intentionId, {
  TagAssignmentState state = TagAssignmentState.assigned,
}) => _package(
  revision,
  testTagAssignmentChanged(
    TagAssignmentChangedChange(
      revision: TagCatalogTestRevision(revision),
      assignment: TagAssignment(tagId: tagId, intentionId: intentionId),
      state: state,
    ),
  ),
);

String? _proposedName(_Panel panel) =>
    panel.loaded.proposedTagName(panel.state.search.filter);

ConfirmedGraphResult<TagCommandSuccess> _created(
  int revision,
  int number,
  String name, {
  TagColor? color,
  int? at,
}) => _package(
  revision,
  TagCreated(
    TagCreatedChange(
      revision: TagCatalogTestRevision(revision),
      after: _tag(number, name, color: color, at: at),
    ),
  ),
);

/// Подтверждённая перестановка [before] на место [at].
ConfirmedGraphResult<TagCommandSuccess> _moved(
  int revision,
  Tag before, {
  required int at,
}) => _package(
  revision,
  TagUpdated(
    TagUpdatedChange(
      revision: TagCatalogTestRevision(revision),
      before: before,
      after: Tag(
        id: before.id,
        name: before.name,
        color: before.color,
        position: tagPositionAt(at),
      ),
    ),
  ),
);

List<bool> _marks(_Panel panel) => [
  for (final row in panel.loaded.rows)
    row.mark == TagsPanelSelectionMark.marked,
];

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) => (IntentionId.decode(
  '00000000-0000-4000-9000-${number.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

/// Номер задаёт идентичность и, если не задано [at], место тега в ручном
/// порядке.
Tag _tag(int number, String name, {TagColor? color, int? at}) => Tag(
  id: _id(number),
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(at ?? number),
);
