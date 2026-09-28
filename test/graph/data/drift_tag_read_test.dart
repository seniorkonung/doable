import 'dart:async';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

TagId _tagId(int number) =>
    (TagId.decode(_uuid(number)) as TagIdDecodingSuccess).id;

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  final statements = <String>[];
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    statements.add(statement.statements.single);
    if (failure case final error?) throw error;
  }
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadProbe probe;

  setUp(() async {
    probe = _ReadProbe();
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      diagnostics,
    );
    probe.statements.clear();
  });
  tearDown(() => database.close());

  void addTag(int number, String name) {
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _uuid(number),
      name,
    ]);
  }

  TagCatalogSnapshot snapshot(TagCatalogResult result) =>
      (result as TagCatalogSuccess).value;

  test('каталог возвращает все 137 тегов за одно чтение', () async {
    for (var number = 1; number <= 137; number++) {
      addTag(number, 'Тег $number');
    }

    final loaded = snapshot(
      await repository.getTagCatalog(const TagCatalogBrowseMode()),
    );

    expect(loaded.items, hasLength(137));
    expect(loaded.items.map((tag) => tag.id), [
      for (var number = 1; number <= 137; number++) _tagId(number),
    ]);
    expect(
      probe.statements.where((sql) => sql.contains('FROM tags')),
      hasLength(1),
    );
    expect(
      probe.statements.any((sql) => sql.contains('tag_assignments')),
      isFalse,
    );
    expect(() => loaded.items.clear(), throwsUnsupportedError);
  });

  test('пустой каталог и полный снимок сохраняют порядок создания', () async {
    final empty = snapshot(
      await repository.getTagCatalog(const TagCatalogBrowseMode()),
    );
    expect(empty.items, isEmpty);

    for (var number = 1; number <= 7; number++) {
      addTag(number, 'Тег $number');
    }
    probe.statements.clear();
    final loaded = snapshot(
      await repository.getTagCatalog(const TagCatalogBrowseMode()),
    );
    expect(loaded.items.map((tag) => tag.name.value), [
      for (var number = 1; number <= 7; number++) 'Тег $number',
    ]);
    expect(
      probe.statements.where((sql) => sql.contains('FROM tags')),
      hasLength(1),
    );
    expect(
      diagnostics.events.whereType<TagCatalogReadDiagnosticsEvent>().where(
        (event) => event.status is DiagnosticsSucceeded,
      ),
      hasLength(2),
    );
  });

  test(
    'повторное чтение получает новую ревизию и не меняет прежний снимок',
    () async {
      for (var number = 1; number <= 3; number++) {
        addTag(number, 'Тег $number');
      }
      final first = snapshot(
        await repository.getTagCatalog(const TagCatalogBrowseMode()),
      );
      final other = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 25),
        diagnostics,
      );
      final sameCatalog = snapshot(
        await other.getTagCatalog(const TagCatalogBrowseMode()),
      );
      expect(
        sameCatalog.items.map((tag) => tag.id),
        first.items.map((tag) => tag.id),
      );
      expect(
        await repository.execute(
          const CreateIntention(title: 'Новое намерение', description: null),
        ),
        isA<GraphCommandSucceeded>(),
      );
      addTag(4, 'Тег 4');
      final updated = snapshot(
        await repository.getTagCatalog(const TagCatalogBrowseMode()),
      );
      expect(updated.items.map((tag) => tag.id), [
        for (var number = 1; number <= 4; number++) _tagId(number),
      ]);
      expect(
        updated.revision.compareTo(first.revision),
        GraphRevisionOrder.newer,
      );
      expect(first.items.map((tag) => tag.id), [
        for (var number = 1; number <= 3; number++) _tagId(number),
      ]);
    },
  );

  test('повреждение 138-й строки отклоняет весь снимок', () async {
    for (var number = 1; number <= 137; number++) {
      addTag(number, 'Тег $number');
    }
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      'некорректный UUID',
      'Повреждённый',
    ]);
    final result = await repository.getTagCatalog(const TagCatalogBrowseMode());
    expect(
      result,
      isA<TagCatalogError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogCorruptionFailure>(),
      ),
    );
    expect(
      (diagnostics.events
                  .whereType<TagCatalogReadDiagnosticsEvent>()
                  .last
                  .status
              as DiagnosticsFailed)
          .code,
      DiagnosticsFailureCode.corruption,
    );
  });

  test('неверный тип порядка и неканоничное название не скрываются', () async {
    raw.execute('PRAGMA ignore_check_constraints = ON');
    raw.execute(
      'INSERT INTO tags (creation_sequence, id, name) VALUES (-1, ?, ?)',
      [_uuid(1), 'Первый'],
    );
    expect(
      await repository.getTagCatalog(const TagCatalogBrowseMode()),
      isA<TagCatalogError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogCorruptionFailure>(),
      ),
    );
    raw.execute('DELETE FROM tags');
    addTag(2, 'Второй');
    raw.createFunction(
      functionName: tagNameKeyFunctionName,
      argumentCount: const sqlite.AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (_) => 'повреждённый ключ',
    );
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
      ' Второй ',
      _uuid(2),
    ]);
    expect(
      await repository.getTagCatalog(const TagCatalogBrowseMode()),
      isA<TagCatalogError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogCorruptionFailure>(),
      ),
    );
    expect(
      await repository.watchTag(_tagId(2)).first,
      isA<TagReadError>().having(
        (result) => result.failure,
        'причина',
        isA<TagReadCorruptionFailure>(),
      ),
    );
  });

  test('наблюдение различает отсутствие, появление и удаление тега', () async {
    final events = StreamIterator(repository.watchTag(_tagId(1)));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    final absent = (events.current as TagReadSuccess).value;
    expect(absent.value, isNull);

    await database.customUpdate(
      'INSERT INTO tags (id, name) VALUES (?, ?)',
      variables: [Variable<String>(_uuid(1)), const Variable<String>('Дом')],
      updates: {database.tags},
    );
    expect(await events.moveNext(), isTrue);
    expect((events.current as TagReadSuccess).value.value!.name.value, 'Дом');

    await database.customUpdate(
      'DELETE FROM tags WHERE id = ?',
      variables: [Variable<String>(_uuid(1))],
      updates: {database.tags},
    );
    expect(await events.moveNext(), isTrue);
    expect((events.current as TagReadSuccess).value.value, isNull);
  });

  test('ошибки чтения отличаются от пустого успеха', () async {
    probe.failure = sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'занято',
    );
    expect(
      await repository.getTagCatalog(const TagCatalogBrowseMode()),
      isA<TagCatalogError>().having(
        (result) => result.failure.category,
        'категория',
        GraphFailureCategory.unavailable,
      ),
    );
    final watch = await repository.watchTag(_tagId(1)).first;
    expect(
      (watch as TagReadError).failure.category,
      GraphFailureCategory.unavailable,
    );
    probe.failure = StateError('неизвестная причина');
    expect(
      await repository.getTagCatalog(const TagCatalogBrowseMode()),
      isA<TagCatalogError>().having(
        (result) => result.failure.category,
        'категория',
        GraphFailureCategory.unexpected,
      ),
    );
  });

  for (final loaded in [false, true]) {
    for (final (name, error, failure) in [
      (
        'временной недоступности',
        sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
          message: 'занято',
        ),
        isA<TagReadUnavailableFailure>(),
      ),
      (
        'повреждения',
        sqlite.SqliteException(
          extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
          message: 'повреждение',
        ),
        isA<TagReadCorruptionFailure>(),
      ),
      (
        'неизвестной причины',
        StateError('неизвестная причина'),
        isA<TagReadUnexpectedFailure>(),
      ),
    ]) {
      test(
        'отказ наблюдения $name ${loaded ? 'после загрузки' : 'до первого снимка'} заканчивает поток и допускает новое подключение',
        () async {
          addTag(1, 'Дом');
          if (!loaded) probe.failure = error;
          final events = StreamIterator(repository.watchTag(_tagId(1)));
          addTearDown(events.cancel);
          if (loaded) {
            expect(await events.moveNext(), isTrue);
            expect(events.current, isA<TagReadSuccess>());
            probe.failure = error;
            database.markTablesUpdated({database.tags});
          }

          expect(await events.moveNext(), isTrue);
          expect(
            events.current,
            isA<TagReadError>().having(
              (result) => result.failure,
              'причина',
              failure,
            ),
          );
          expect(await events.moveNext(), isFalse);

          probe.failure = null;
          final restored = StreamIterator(repository.watchTag(_tagId(1)));
          addTearDown(restored.cancel);
          expect(await restored.moveNext(), isTrue);
          expect(
            (restored.current as TagReadSuccess).value.value!.name.value,
            'Дом',
          );
          await database.customUpdate(
            'UPDATE tags SET name = ? WHERE id = ?',
            variables: [
              const Variable<String>('Быт'),
              Variable<String>(_uuid(1)),
            ],
            updates: {database.tags},
          );
          expect(await restored.moveNext(), isTrue);
          expect(
            (restored.current as TagReadSuccess).value.value!.name.value,
            'Быт',
          );
        },
      );
    }
  }
}
