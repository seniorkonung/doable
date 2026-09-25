import 'dart:async';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
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

  TagCatalogPage page(TagCatalogPageResult result) =>
      (result as TagCatalogPageSuccess).value;

  test('пустой каталог и последовательный обход ограниченных порций', () async {
    final empty = page(await repository.getTagCatalogPage(TagCatalogQuery()));
    expect(empty.items, isEmpty);
    expect(empty.nextCursor, isNull);

    for (var number = 1; number <= 7; number++) {
      addTag(number, 'Тег $number');
    }
    final names = <String>[];
    TagCatalogCursor? cursor;
    do {
      final next = page(
        await repository.getTagCatalogPage(
          TagCatalogQuery(pageSize: 2, cursor: cursor),
        ),
      );
      expect(next.items.length, lessThanOrEqualTo(2));
      names.addAll(next.items.map((tag) => tag.name.value));
      cursor = next.nextCursor;
    } while (cursor != null);
    expect(names, [for (var n = 1; n <= 7; n++) 'Тег $n']);
    expect(
      probe.statements.where((sql) => sql.contains('FROM tags')),
      isNotEmpty,
    );
    expect(
      probe.statements
          .where((sql) => sql.contains('FROM tags'))
          .every((sql) => sql.contains('LIMIT ?') && !sql.contains('OFFSET')),
      isTrue,
    );
    expect(
      probe.statements.any((sql) => sql.contains('tag_assignments')),
      isFalse,
    );
    expect(
      diagnostics.events.whereType<TagCatalogPageReadDiagnosticsEvent>().where(
        (event) => event.status is DiagnosticsSucceeded,
      ),
      isNotEmpty,
    );
  });

  test('чужой курсор и новая ревизия различаются', () async {
    for (var number = 1; number <= 3; number++) {
      addTag(number, 'Тег $number');
    }
    final first = page(
      await repository.getTagCatalogPage(TagCatalogQuery(pageSize: 1)),
    );
    final cursor = first.nextCursor!;

    expect(
      await repository.getTagCatalogPage(
        TagCatalogQuery(pageSize: 2, cursor: cursor),
      ),
      isA<TagCatalogPageError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogInvalidCursor>(),
      ),
    );
    final other = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      diagnostics,
    );
    expect(
      await other.getTagCatalogPage(
        TagCatalogQuery(pageSize: 1, cursor: cursor),
      ),
      isA<TagCatalogPageError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogInvalidCursor>(),
      ),
    );
    expect(
      await repository.execute(
        const CreateIntention(title: 'Новое намерение', description: null),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(
      await repository.getTagCatalogPage(
        TagCatalogQuery(pageSize: 1, cursor: cursor),
      ),
      isA<TagCatalogPageError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogSnapshotExpired>(),
      ),
    );
  });

  test('повреждение дополнительной строки отклоняет всю порцию', () async {
    addTag(1, 'Допустимый');
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      'некорректный UUID',
      'Повреждённый',
    ]);
    final result = await repository.getTagCatalogPage(
      TagCatalogQuery(pageSize: 1),
    );
    expect(
      result,
      isA<TagCatalogPageError>().having(
        (result) => result.failure,
        'причина',
        isA<TagCatalogCorruptionFailure>(),
      ),
    );
    expect(
      (diagnostics.events
                  .whereType<TagCatalogPageReadDiagnosticsEvent>()
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
      await repository.getTagCatalogPage(TagCatalogQuery()),
      isA<TagCatalogPageError>().having(
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
      await repository.getTagCatalogPage(TagCatalogQuery()),
      isA<TagCatalogPageError>().having(
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
      await repository.getTagCatalogPage(TagCatalogQuery()),
      isA<TagCatalogPageError>().having(
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
      await repository.getTagCatalogPage(TagCatalogQuery()),
      isA<TagCatalogPageError>().having(
        (result) => result.failure.category,
        'категория',
        GraphFailureCategory.unexpected,
      ),
    );
  });
}
