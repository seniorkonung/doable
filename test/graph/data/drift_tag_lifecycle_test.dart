import 'dart:async';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_positions.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

TagName _name(String value) => TagName.fromInput(value);

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      diagnostics,
    );
  });
  tearDown(() => database.close());

  Future<GraphRevision> currentRevision() async =>
      (await repository.getTagCatalog(
        const TagCatalogBrowseMode(),
      ) as TagCatalogSuccess).value.revision;

  Map<String, List<List<Object?>>> graphState() => {
    for (final table in [
      'intentions',
      'intention_titles_fts',
      'long_term_relations',
      'daily_choices',
      'daily_choice_path_steps',
      'tag_assignments',
    ])
      table: raw
          .select('SELECT * FROM $table')
          .map((row) => row.values.toList())
          .toList(),
  };

  test('создание и редактирование названия и цвета сохраняют граф и все '
      'назначения', () async {
    seedRawGraph(raw, () {
      raw.execute(
        'INSERT INTO intentions (id, title, description, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [_uuid(1), 'Исходное', 'Описание', 1, 0, 100, 200],
      );
      raw.execute(
        'INSERT INTO intentions (id, title, description, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [_uuid(2), 'Выбранное', null, 1, 0, 300, 400],
      );
      raw.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, description) VALUES (?, ?, ?, ?, ?, ?)',
        [_uuid(3), _uuid(1), _uuid(2), 'need', 1, 'Связь'],
      );
      raw.execute(
        'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
        [_uuid(4), _uuid(1), _uuid(2), '2026-09-25', 1],
      );
      raw.execute(
        'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
        [_uuid(5), _uuid(4), _uuid(3)],
      );
      raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
        _uuid(6),
        'Дом',
        tagPositionKey(6),
      ]);
      for (final intention in [1, 2]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(6), _uuid(intention)],
        );
      }
    });
    final before = graphState();
    final initialRevision = await currentRevision();

    final created = await repository.execute(
      CreateTag(
        name: _name('Работа'),
        color: TagColor.green,
        placement: TagPlacement.first,
      ),
    );
    expect(created, isA<TagCommandSucceeded>());
    final newTag = (created as TagCommandSucceeded).value.value as TagCreated;
    expect(newTag.tag.name.value, 'Работа');
    expect(newTag.tag.color, TagColor.green);
    expect(
      raw.select('SELECT color FROM tags WHERE id = ?', [
        newTag.tag.id.toCanonicalString(),
      ]).single['color'],
      'green',
    );
    expect(newTag.tag.id.toCanonicalString(), isNot(_uuid(6)));
    expect(
      raw.select('SELECT creation_sequence FROM tags WHERE id = ?', [
            newTag.tag.id.toCanonicalString(),
          ]).single['creation_sequence']
          as int,
      greaterThan(
        raw.select('SELECT creation_sequence FROM tags WHERE id = ?', [
              _uuid(6),
            ]).single['creation_sequence']
            as int,
      ),
    );
    expect(
      created.value.revision.compareTo(initialRevision),
      GraphRevisionOrder.newer,
    );
    expect(graphState(), before);

    final tagId = (TagId.decode(_uuid(6)) as TagIdDecodingSuccess).id;
    final renamed = await repository.execute(
      UpdateTag(tagId: tagId, name: _name('Быт'), color: null),
    );
    expect(renamed, isA<TagCommandSucceeded>());
    final outcome = (renamed as TagCommandSucceeded).value.value as TagUpdated;
    expect(outcome.before.id, tagId);
    expect(outcome.before.name.value, 'Дом');
    expect(outcome.after.id, tagId);
    expect(outcome.after.name.value, 'Быт');
    expect(
      renamed.value.revision.compareTo(created.value.revision),
      GraphRevisionOrder.newer,
    );
    expect(graphState(), before);
    expect(
      raw.select('SELECT name FROM tags WHERE id = ?', [
        _uuid(6),
      ]).single['name'],
      'Быт',
    );

    final recolored = await repository.execute(
      UpdateTag(tagId: tagId, name: _name('Быт'), color: TagColor.blue),
    );
    final recoloredOutcome =
        (recolored as TagCommandSucceeded).value.value as TagUpdated;
    expect(
      [recoloredOutcome.before.color, recoloredOutcome.after.color],
      [null, TagColor.blue],
    );
    expect(recoloredOutcome.after.name.value, 'Быт');
    expect(
      recolored.value.revision.compareTo(renamed.value.revision),
      GraphRevisionOrder.newer,
    );
    expect(graphState(), before);

    final cleared = await repository.execute(
      UpdateTag(tagId: tagId, name: _name('Быт'), color: null),
    );
    expect(
      ((cleared as TagCommandSucceeded).value.value as TagUpdated).after.color,
      isNull,
    );
    expect(
      raw
          .select('SELECT name, color FROM tags WHERE id = ?', [_uuid(6)])
          .single
          .values,
      ['Быт', null],
    );
    expect(graphState(), before);
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
  });

  test('новый тег встаёт перед первым по месту, а не по созданию', () async {
    Future<String> createdPosition(String name) async {
      final result = await repository.execute(
        CreateTag(
          name: _name(name),
          color: null,
          placement: TagPlacement.first,
        ),
      );
      final tag =
          ((result as TagCommandSucceeded).value.value as TagCreated).tag;
      expect(
        raw.select('SELECT position FROM tags WHERE id = ?', [
          tag.id.toCanonicalString(),
        ]).single['position'],
        tag.position.value,
      );
      return tag.position.value;
    }

    expect(await createdPosition('Дом'), 'a0');
    // Первый по месту тег — не первый и не последний по созданию.
    seedRawGraph(raw, () {
      for (final (number, name, position) in [
        (7, 'Работа', 'Zz0V'),
        (8, 'Отдых', 'a1'),
      ]) {
        raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
          _uuid(number),
          name,
          position,
        ]);
      }
    });

    expect(await createdPosition('Спорт'), 'Zz');
    final catalog = await repository.getTagCatalog(
      const TagCatalogBrowseMode(),
    );
    expect(
      (catalog as TagCatalogSuccess).value.items.map((tag) => tag.name.value),
      ['Спорт', 'Работа', 'Дом', 'Отдых'],
    );
  });

  test('тег с размещением после исходного встаёт сразу за ним и не меняет '
      'места остальных тегов', () async {
    seedRawGraph(raw, () {
      for (final (number, name, position) in [
        (6, 'Дом', 'a0'),
        (7, 'Работа', 'a1'),
        (8, 'Отдых', 'a2'),
      ]) {
        raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
          _uuid(number),
          name,
          position,
        ]);
      }
    });
    TagId id(int number) =>
        (TagId.decode(_uuid(number)) as TagIdDecodingSuccess).id;
    Future<void> createAfter(String name, int source) async {
      final result = await repository.execute(
        CreateTag(
          name: _name(name),
          color: null,
          placement: AfterTagPlacement(id(source)),
        ),
      );
      expect(result, isA<TagCommandSucceeded>());
    }

    Future<List<String>> catalogNames() async =>
        ((await repository.getTagCatalog(const TagCatalogBrowseMode()))
                as TagCatalogSuccess)
            .value
            .items
            .map((tag) => tag.name.value)
            .toList();
    List<List<Object?>> seededPositions() => raw
        .select(
          'SELECT id, position FROM tags WHERE id IN (?, ?, ?) ORDER BY id',
          [_uuid(6), _uuid(7), _uuid(8)],
        )
        .map((row) => row.values)
        .toList();
    final positionsBefore = seededPositions();

    await createAfter('Спорт', 6);
    expect(await catalogNames(), ['Дом', 'Спорт', 'Работа', 'Отдых']);
    await createAfter('Сад', 8);
    expect(await catalogNames(), ['Дом', 'Спорт', 'Работа', 'Отдых', 'Сад']);
    expect(seededPositions(), positionsBefore);
  });

  test('отсутствующий исходный тег отклоняет создание без записи', () async {
    await repository.execute(
      CreateTag(name: _name('Дом'), color: null, placement: TagPlacement.first),
    );
    final missing = (TagId.decode(_uuid(8)) as TagIdDecodingSuccess).id;
    final before = await currentRevision();

    final result = await repository.execute(
      CreateTag(
        name: _name('Работа'),
        color: null,
        placement: AfterTagPlacement(missing),
      ),
    );

    expect(
      (result as TagCommandFailed).failure,
      isA<TagNotFoundFailure>().having(
        (failure) => failure.tagId,
        'исходный тег',
        missing,
      ),
    );
    expect(
      (await currentRevision()).compareTo(before),
      GraphRevisionOrder.same,
    );
    expect(raw.select('SELECT name FROM tags').single['name'], 'Дом');
  });

  test('повтор названия и цвета не меняет ревизию, смена регистра разрешена, чужое имя занято', () async {
    final first = await repository.execute(
      CreateTag(
        name: _name('Straße'),
        color: TagColor.blue,
        placement: TagPlacement.first,
      ),
    );
    final id =
        ((first as TagCommandSucceeded).value.value as TagCreated).tag.id;
    final sequence = raw
        .select('SELECT creation_sequence FROM tags')
        .single['creation_sequence'];
    final before = await currentRevision();

    final unchanged = await repository.execute(
      UpdateTag(tagId: id, name: _name('Straße'), color: TagColor.blue),
    );
    expect((unchanged as TagCommandSucceeded).value.value, isA<TagUnchanged>());
    expect(unchanged.value.revision.compareTo(before), GraphRevisionOrder.same);

    final renamed = await repository.execute(
      UpdateTag(tagId: id, name: _name('STRASSE'), color: TagColor.blue),
    );
    expect((renamed as TagCommandSucceeded).value.value, isA<TagUpdated>());
    expect(
      raw
          .select('SELECT creation_sequence FROM tags')
          .single['creation_sequence'],
      sequence,
    );

    final revisionBeforeConflict = await currentRevision();
    final duplicate = await repository.execute(
      CreateTag(
        name: _name('straße'),
        color: null,
        placement: TagPlacement.first,
      ),
    );
    expect(duplicate, isA<TagCommandFailed>());
    expect(
      (duplicate as TagCommandFailed).failure,
      isA<TagNameOccupiedFailure>().having(
        (failure) => failure.existingTagId,
        'существующий id',
        id,
      ),
    );
    expect(raw.select('SELECT id FROM tags').length, 1);
    expect(
      (await currentRevision()).compareTo(revisionBeforeConflict),
      GraphRevisionOrder.same,
    );
  });

  test(
    'конкурирующие команды сохраняют единственность и исходную идентичность',
    () async {
      final results = await Future.wait([
        repository.execute(
          CreateTag(
            name: _name('Дом'),
            color: null,
            placement: TagPlacement.first,
          ),
        ),
        repository.execute(
          CreateTag(
            name: _name('ДОМ'),
            color: null,
            placement: TagPlacement.first,
          ),
        ),
      ]);
      expect(results.whereType<TagCommandSucceeded>().length, 1);
      expect(results.whereType<TagCommandFailed>().length, 1);
      final created =
          (results.whereType<TagCommandSucceeded>().single.value.value
                  as TagCreated)
              .tag;
      expect(
        (results.whereType<TagCommandFailed>().single.failure
                as TagNameOccupiedFailure)
            .existingTagId,
        created.id,
      );

      final other = await repository.execute(
        CreateTag(
          name: _name('Работа'),
          color: TagColor.blue,
          placement: TagPlacement.first,
        ),
      );
      final otherId =
          ((other as TagCommandSucceeded).value.value as TagCreated).tag.id;
      final renamed = await repository.execute(
        UpdateTag(tagId: otherId, name: _name('дом'), color: TagColor.green),
      );
      expect(
        (renamed as TagCommandFailed).failure,
        isA<TagNameOccupiedFailure>().having(
          (failure) => failure.existingTagId,
          'существующий id',
          created.id,
        ),
      );
      // Конфликт названия откатывает и цвет из той же правки.
      expect(
        raw
            .select('SELECT name, color FROM tags WHERE id = ?', [
              otherId.toCanonicalString(),
            ])
            .single
            .values,
        ['Работа', 'blue'],
      );
      expect(raw.select('SELECT id FROM tags').length, 2);
    },
  );

  test('наблюдатель получает переименование подтверждённого тега', () async {
    final created = await repository.execute(
      CreateTag(name: _name('Дом'), color: null, placement: TagPlacement.first),
    );
    final id =
        ((created as TagCommandSucceeded).value.value as TagCreated).tag.id;
    final events = StreamIterator(repository.watchTag(id));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    expect((events.current as TagReadSuccess).value.value!.name.value, 'Дом');

    final renamed = await repository.execute(
      UpdateTag(tagId: id, name: _name('Быт'), color: null),
    );
    expect(renamed, isA<TagCommandSucceeded>());
    expect(await events.moveNext(), isTrue);
    expect((events.current as TagReadSuccess).value.value!.name.value, 'Быт');
    expect(
      (events.current as TagReadSuccess).value.revision.compareTo(
        (renamed as TagCommandSucceeded).value.revision,
      ),
      GraphRevisionOrder.same,
    );
  });

  test('отсутствующий тег не заменяется новым одноимённым', () async {
    final missing = (TagId.decode(_uuid(8)) as TagIdDecodingSuccess).id;
    await repository.execute(
      CreateTag(name: _name('Дом'), color: null, placement: TagPlacement.first),
    );
    final before = await currentRevision();
    final result = await repository.execute(
      UpdateTag(tagId: missing, name: _name('Дом'), color: null),
    );
    expect((result as TagCommandFailed).failure, isA<TagNotFoundFailure>());
    expect(
      (await currentRevision()).compareTo(before),
      GraphRevisionOrder.same,
    );
    expect(raw.select('SELECT id FROM tags').length, 1);
  });
}
