import 'dart:convert';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late _RecordingDiagnostics diagnostics;
  late _FavoriteStorageFaults faults;
  late DriftPersonalGraphRepository repository;

  DriftPersonalGraphRepository repositoryWith(DiagnosticsSink sink) =>
      DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 10, 2, 12),
        sink,
      );

  setUp(() async {
    diagnostics = _RecordingDiagnostics();
    faults = _FavoriteStorageFaults();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        faults,
      ),
    );
    await database.open();
    repository = repositoryWith(diagnostics);
  });

  tearDown(() => database.close());

  /// Три намерения, из которых первое и архивированное второе избранные.
  void seedGraph() {
    _insertIntention(raw, number: 1, title: 'CANARY-первое');
    _insertIntention(raw, number: 2, title: 'CANARY-второе', isArchived: true);
    _insertIntention(
      raw,
      number: 3,
      title: 'CANARY-третье',
      description: 'CANARY-описание',
    );
    storeFavoriteMark(raw, intentionId: _uuid(1), position: 4);
    storeFavoriteMark(raw, intentionId: _uuid(2), position: 9);
  }

  group('Откат команды при отказе', () {
    for (final command in _commands) {
      for (final fault in _storageFaults) {
        for (final point in _FaultPoint.values) {
          test('${command.name}: ${fault.name} ${point.description} не '
              'оставляет изменения', () async {
            seedGraph();
            final marksBefore = _storedMarks(raw);
            final intentionsBefore = _storedIntentions(raw);
            final revisionBefore = await _revision(repository);
            diagnostics.clear();
            faults.arm(point, fault.error);

            final result = await repository.execute(command.build());

            expect(result, _failure(fault.failure));
            expect(faults.failures, 1);
            faults.disarm();
            expect(_storedMarks(raw), marksBefore);
            expect(_storedIntentions(raw), intentionsBefore);
            expect(
              (await _revision(repository)).compareTo(revisionBefore),
              GraphRevisionOrder.same,
            );
            expect(
              (await _details(repository, command.number)).favoriteMark,
              command.markBefore,
            );
            expect(diagnostics.commandEvents, [
              _failedCommand(command.type, point.stage, fault.code),
            ]);
          });
        }
      }
    }

    test('отклонение записи ограничением схемы не оставляет отметку и '
        'остаётся неизвестным отказом', () async {
      seedGraph();
      final marksBefore = _storedMarks(raw);
      faults.arm(
        _FaultPoint.beforeWrite,
        sqlite.SqliteException(
          extendedResultCode: sqlite.SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
          message: 'CANARY-уникальность',
        ),
      );

      final result = await repository.execute(MarkIntentionFavorite(_id(3)));

      expect(result, _failure(isA<IntentionUnexpectedFailure>()));
      expect(_storedMarks(raw), marksBefore);
    });
  });

  group('Повтор после устранимой недоступности', () {
    test('отметка выполняется как новая команда и занимает место в '
        'конце', () async {
      seedGraph();
      final revisionBefore = await _revision(repository);
      faults.arm(_FaultPoint.afterWrite, _busy);
      expect(
        await repository.execute(MarkIntentionFavorite(_id(3))),
        _failure(isA<IntentionUnavailableFailure>()),
      );
      faults.disarm();
      diagnostics.clear();

      final confirmed = await _confirmed(
        repository,
        MarkIntentionFavorite(_id(3)),
      );

      final saved = confirmed.value as IntentionSaved;
      final mutation = saved.catalogMutation as IntentionCatalogUpdated;
      expect(mutation.before.summary.favoriteMark, FavoriteMark.notFavorite);
      expect(mutation.after.summary.favoriteMark, FavoriteMark.favorite);
      expect(
        confirmed.revision.compareTo(revisionBefore),
        GraphRevisionOrder.newer,
      );
      expect(_storedMarks(raw), [(_uuid(1), 4), (_uuid(2), 9), (_uuid(3), 10)]);
      expect(diagnostics.commandEvents, [
        _succeededCommand(
          IntentionCommandDiagnosticsType.markFavorite,
          FavoriteMarkCommandDiagnosticsStage.write,
        ),
      ]);
    });

    test('снятие отметки выполняется как новая команда', () async {
      seedGraph();
      final revisionBefore = await _revision(repository);
      faults.arm(_FaultPoint.afterWrite, _busy);
      expect(
        await repository.execute(UnmarkIntentionFavorite(_id(1))),
        _failure(isA<IntentionUnavailableFailure>()),
      );
      faults.disarm();

      final confirmed = await _confirmed(
        repository,
        UnmarkIntentionFavorite(_id(1)),
      );

      expect(
        (confirmed.value as IntentionSaved).catalogMutation,
        isA<IntentionCatalogUpdated>(),
      );
      expect(
        confirmed.revision.compareTo(revisionBefore),
        GraphRevisionOrder.newer,
      );
      expect(_storedMarks(raw), [(_uuid(2), 9)]);
    });
  });

  group('Диагностика этапа и исхода', () {
    for (final command in _commands) {
      test('${command.name}: успех с записью относится к этапу записи и несёт '
          'длительность', () async {
        seedGraph();

        await _confirmed(repository, command.build());

        expect(diagnostics.commandEvents, [
          _succeededCommand(
            command.type,
            FavoriteMarkCommandDiagnosticsStage.write,
          ),
        ]);
        expect(
          (diagnostics.commandEvents.single.status as DiagnosticsSucceeded)
              .duration,
          greaterThanOrEqualTo(Duration.zero),
        );
      });

      test('${command.name}: отсутствие намерения относится к этапу '
          'проверки', () async {
        seedGraph();

        final result = await repository.execute(command.buildFor(_id(7)));

        expect(result, _failure(isA<IntentionNotFoundFailure>()));
        expect(diagnostics.commandEvents, [
          _failedCommand(
            command.type,
            FavoriteMarkCommandDiagnosticsStage.validation,
            DiagnosticsFailureCode.notFound,
          ),
        ]);
      });
    }

    test(
      'повтор без изменения завершается успехом на этапе проверки',
      () async {
        seedGraph();

        await _confirmed(repository, MarkIntentionFavorite(_id(1)));
        await _confirmed(repository, UnmarkIntentionFavorite(_id(3)));

        expect(diagnostics.commandEvents, [
          _succeededCommand(
            IntentionCommandDiagnosticsType.markFavorite,
            FavoriteMarkCommandDiagnosticsStage.validation,
          ),
          _succeededCommand(
            IntentionCommandDiagnosticsType.unmarkFavorite,
            FavoriteMarkCommandDiagnosticsStage.validation,
          ),
        ]);
      },
    );

    test('недопустимое место сохранённой отметки — повреждение на этапе '
        'проверки без записи', () async {
      _insertIntention(raw, number: 1, title: 'CANARY-первое');
      storeFavoriteMarkWithInvalidPosition(
        raw,
        intentionId: _uuid(1),
        position: 0,
      );

      final result = await repository.execute(UnmarkIntentionFavorite(_id(1)));

      expect(result, _failure(isA<IntentionCorruptionFailure>()));
      expect(_storedMarks(raw), [(_uuid(1), 0)]);
      expect(diagnostics.commandEvents, [
        _failedCommand(
          IntentionCommandDiagnosticsType.unmarkFavorite,
          FavoriteMarkCommandDiagnosticsStage.validation,
          DiagnosticsFailureCode.corruption,
        ),
      ]);
    });

    test('этап избранного не получают остальные команды намерения, а '
        'создание несёт собственный этап', () async {
      seedGraph();

      await _confirmed(
        repository,
        const CreateIntention(title: 'CANARY-новое', description: null),
      );
      await _confirmed(repository, EnableIntentionReadiness(_id(1)));
      await _confirmed(repository, ArchiveIntention(_id(3)));
      await repository.execute(DeleteIntention(_id(7)));

      expect(diagnostics.commandEvents.map((event) => event.commandType), [
        IntentionCommandDiagnosticsType.create,
        IntentionCommandDiagnosticsType.enableReadiness,
        IntentionCommandDiagnosticsType.archive,
        IntentionCommandDiagnosticsType.delete,
      ]);
      expect(diagnostics.commandEvents.map((event) => event.stage), [
        IntentionCreationCommandDiagnosticsStage.resultRead,
        null,
        null,
        null,
      ]);
      expect(diagnostics.messages.map((message) => message['stage']), [
        'resultRead',
        null,
        null,
        null,
      ]);
      for (final message in diagnostics.messages.skip(1)) {
        expect(message.keys, isNot(contains('stage')));
      }
    });
  });

  group('Безопасность диагностики', () {
    test('события и запись получателя разработчика несут только безопасные '
        'поля', () async {
      seedGraph();

      await _confirmed(repository, MarkIntentionFavorite(_id(3)));
      await _confirmed(repository, UnmarkIntentionFavorite(_id(1)));
      await _confirmed(repository, UnmarkIntentionFavorite(_id(1)));
      await repository.execute(MarkIntentionFavorite(_id(7)));
      for (final (point, error) in [
        (_FaultPoint.validationRead, _busy),
        (_FaultPoint.beforeWrite, _corrupt),
        (_FaultPoint.afterWrite, StateError('CANARY-исключение')),
        (_FaultPoint.resultRead, _readOnly),
      ]) {
        faults.arm(point, error);
        await repository.execute(MarkIntentionFavorite(_id(1)));
        faults.disarm();
      }

      expect(diagnostics.messages, hasLength(8));
      const succeededKeys = {
        'operation',
        'outcome',
        'durationMicros',
        'commandType',
        'stage',
      };
      for (final message in diagnostics.messages) {
        expect(message['operation'], 'intentionCommand');
        expect(message['commandType'], anyOf('markFavorite', 'unmarkFavorite'));
        expect(message['stage'], anyOf('validation', 'write'));
        expect(message['durationMicros'], isA<int>());
        expect(
          message.keys.toSet(),
          message['outcome'] == 'succeeded'
              ? succeededKeys
              : {...succeededKeys, 'failureCode'},
        );
      }
      expect(
        [
          for (final message in diagnostics.messages)
            (message['outcome'], message['stage'], message['failureCode']),
        ],
        [
          ('succeeded', 'write', null),
          ('succeeded', 'write', null),
          ('succeeded', 'validation', null),
          ('failed', 'validation', 'notFound'),
          ('failed', 'validation', 'unavailable'),
          ('failed', 'write', 'corruption'),
          ('failed', 'write', 'unexpected'),
          ('failed', 'write', 'unexpected'),
        ],
      );
      final written = diagnostics.rawMessages.join('\n');
      for (final secret in [
        'CANARY',
        for (var number = 1; number <= 7; number++) _uuid(number),
        'favorite_intentions',
        'position',
        'INSERT',
        'DELETE',
        'SELECT',
        'Exception',
        'StateError',
      ]) {
        expect(written, isNot(contains(secret)));
      }
      // Значения событий — только перечисления и длительность: мест, состава
      // избранных и идентификаторов в них нет по построению типа.
      for (final value in [
        for (final message in diagnostics.messages) ...message.values,
      ]) {
        expect(
          value,
          anyOf(
            isA<int>(),
            isIn([
              'intentionCommand',
              'markFavorite',
              'unmarkFavorite',
              'validation',
              'write',
              'succeeded',
              'failed',
              'notFound',
              'unavailable',
              'corruption',
              'unexpected',
            ]),
          ),
        );
      }
    });
  });

  group('Независимость от получателя диагностики', () {
    test('отказ получателя не откатывает подтверждённую отметку и не '
        'повторяет запись', () async {
      seedGraph();
      final failing = _ThrowingDiagnosticsSink();
      repository = repositoryWith(failing);
      final revisionBefore = await _revision(repository);
      failing.attemptedEvents.clear();
      faults.writes.clear();

      final confirmed = await _confirmed(
        repository,
        MarkIntentionFavorite(_id(3)),
      );

      expect(
        (confirmed.value as IntentionSaved).catalogMutation,
        isA<IntentionCatalogUpdated>(),
      );
      expect(
        confirmed.revision.compareTo(revisionBefore),
        GraphRevisionOrder.newer,
      );
      expect(faults.writes, hasLength(1));
      expect(_storedMarks(raw), [(_uuid(1), 4), (_uuid(2), 9), (_uuid(3), 10)]);
      expect(failing.attemptedEvents, [
        _succeededCommand(
          IntentionCommandDiagnosticsType.markFavorite,
          FavoriteMarkCommandDiagnosticsStage.write,
        ),
      ]);
    });

    test('отказ получателя не откатывает подтверждённое снятие и не '
        'повторяет запись', () async {
      seedGraph();
      final failing = _ThrowingDiagnosticsSink();
      repository = repositoryWith(failing);
      faults.writes.clear();

      final confirmed = await _confirmed(
        repository,
        UnmarkIntentionFavorite(_id(1)),
      );

      expect(
        (confirmed.value as IntentionSaved).catalogMutation,
        isA<IntentionCatalogUpdated>(),
      );
      expect(faults.writes, hasLength(1));
      expect(_storedMarks(raw), [(_uuid(2), 9)]);
      expect(failing.attemptedEvents, hasLength(1));
    });

    test('отказ получателя не меняет результат команды без записи', () async {
      seedGraph();
      final failing = _ThrowingDiagnosticsSink();
      repository = repositoryWith(failing);
      faults.writes.clear();

      final unchanged = await _confirmed(
        repository,
        MarkIntentionFavorite(_id(1)),
      );
      final notFound = await repository.execute(MarkIntentionFavorite(_id(7)));

      expect(
        (unchanged.value as IntentionSaved).catalogMutation,
        isA<IntentionCatalogUnchanged>(),
      );
      expect(notFound, _failure(isA<IntentionNotFoundFailure>()));
      expect(faults.writes, isEmpty);
      expect(_storedMarks(raw), [(_uuid(1), 4), (_uuid(2), 9)]);
      expect(failing.attemptedEvents, hasLength(2));
    });

    for (final point in _FaultPoint.values) {
      test('отказ получателя не меняет категорию отказа и откат '
          '${point.description}', () async {
        seedGraph();
        final marksBefore = _storedMarks(raw);
        final failing = _ThrowingDiagnosticsSink();
        repository = repositoryWith(failing);
        faults.arm(point, _busy);

        final result = await repository.execute(MarkIntentionFavorite(_id(3)));

        expect(result, _failure(isA<IntentionUnavailableFailure>()));
        expect(faults.failures, 1);
        expect(_storedMarks(raw), marksBefore);
        expect(failing.attemptedEvents, [
          _failedCommand(
            IntentionCommandDiagnosticsType.markFavorite,
            point.stage,
            DiagnosticsFailureCode.unavailable,
          ),
        ]);
      });
    }

    test('отказ записи получателя разработчика не меняет результат и не '
        'повторяет запись', () async {
      seedGraph();
      var writeAttempts = 0;
      repository = repositoryWith(
        DeveloperDiagnosticsSink((_) {
          writeAttempts++;
          throw StateError('CANARY-отказ-записи-диагностики');
        }),
      );
      faults.writes.clear();

      await _confirmed(repository, MarkIntentionFavorite(_id(3)));
      await _confirmed(repository, UnmarkIntentionFavorite(_id(1)));

      expect(writeAttempts, 2);
      expect(faults.writes, hasLength(2));
      expect(_storedMarks(raw), [(_uuid(2), 9), (_uuid(3), 10)]);
    });
  });
}

final _busy = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
  message: 'CANARY-недоступность',
);

final _corrupt = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
  message: 'CANARY-повреждение',
);

final _readOnly = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_READONLY,
  message: 'CANARY-неизвестный-SQLite-отказ',
);

/// Отказы хранилища трёх различимых категорий.
final _storageFaults =
    <
      ({
        String name,
        Object error,
        Matcher failure,
        DiagnosticsFailureCode code,
      })
    >[
      (
        name: 'недоступность',
        error: _busy,
        failure: isA<IntentionUnavailableFailure>(),
        code: DiagnosticsFailureCode.unavailable,
      ),
      (
        name: 'повреждение',
        error: _corrupt,
        failure: isA<IntentionCorruptionFailure>(),
        code: DiagnosticsFailureCode.corruption,
      ),
      (
        name: 'неизвестный отказ',
        error: StateError('CANARY-неизвестный-отказ'),
        failure: isA<IntentionUnexpectedFailure>(),
        code: DiagnosticsFailureCode.unexpected,
      ),
    ];

/// Отметка неизбранного третьего намерения и снятие отметки первого.
final _commands =
    <
      ({
        String name,
        int number,
        IntentionCommand Function() build,
        IntentionCommand Function(IntentionId) buildFor,
        IntentionCommandDiagnosticsType type,
        FavoriteMark markBefore,
      })
    >[
      (
        name: 'отметка',
        number: 3,
        build: () => MarkIntentionFavorite(_id(3)),
        buildFor: MarkIntentionFavorite.new,
        type: IntentionCommandDiagnosticsType.markFavorite,
        markBefore: FavoriteMark.notFavorite,
      ),
      (
        name: 'снятие отметки',
        number: 1,
        build: () => UnmarkIntentionFavorite(_id(1)),
        buildFor: UnmarkIntentionFavorite.new,
        type: IntentionCommandDiagnosticsType.unmarkFavorite,
        markBefore: FavoriteMark.favorite,
      ),
    ];

/// Момент команды отметки, в который хранилище отказывает.
enum _FaultPoint {
  /// Чтение текущей отметки до записи.
  validationRead(
    'при чтении отметки до записи',
    FavoriteMarkCommandDiagnosticsStage.validation,
  ),

  /// Запись строки отметки отклонена до выполнения.
  beforeWrite('до записи отметки', FavoriteMarkCommandDiagnosticsStage.write),

  /// Запись строки отметки выполнена, но не подтверждена.
  afterWrite('после записи отметки', FavoriteMarkCommandDiagnosticsStage.write),

  /// Чтение отметки после выполненной записи.
  resultRead(
    'при чтении отметки после записи',
    FavoriteMarkCommandDiagnosticsStage.write,
  );

  const _FaultPoint(this.description, this.stage);

  final String description;
  final FavoriteMarkCommandDiagnosticsStage stage;
}

/// Однократный отказ хранилища отметок в заданный момент команды.
final class _FavoriteStorageFaults extends LocalDatabaseConnectionObserver {
  _FaultPoint? _point;
  Object? _error;
  var _wroteMark = false;

  /// Число сработавших отказов с последнего [arm].
  var failures = 0;

  /// Записи в таблицу отметок в порядке выполнения.
  final writes = <String>[];

  void arm(_FaultPoint point, Object error) {
    _point = point;
    _error = error;
    _wroteMark = false;
    failures = 0;
  }

  void disarm() {
    _point = null;
    _error = null;
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (!_isMarkWrite(statement)) return;
    writes.addAll(statement.statements);
    _failAt(_FaultPoint.beforeWrite);
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_isMarkWrite(statement)) return;
    _wroteMark = true;
    _failAt(_FaultPoint.afterWrite);
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (statement.statements.single.contains('FROM favorite_intentions')) {
      _failAt(_wroteMark ? _FaultPoint.resultRead : _FaultPoint.validationRead);
    }
    return rows;
  }

  bool _isMarkWrite(LocalDatabaseSqlStatement statement) =>
      statement.operation != LocalDatabaseSqlOperation.select &&
      statement.statements.any((sql) => sql.contains('favorite_intentions'));

  void _failAt(_FaultPoint point) {
    final error = _error;
    if (_point != point || error == null || failures > 0) return;
    failures++;
    throw error;
  }
}

/// Сохраняет события и то, что получатель разработчика записал бы в журнал.
final class _RecordingDiagnostics implements DiagnosticsSink {
  final _events = <DiagnosticsEvent>[];
  final rawMessages = <String>[];
  late final _developer = DeveloperDiagnosticsSink(rawMessages.add);

  List<IntentionCommandDiagnosticsEvent> get commandEvents =>
      _events.whereType<IntentionCommandDiagnosticsEvent>().toList();

  /// Записи получателя разработчика о командах намерения.
  List<Map<String, Object?>> get messages => [
    for (final message in rawMessages)
      if (jsonDecode(message) case final Map<String, Object?> decoded
          when decoded['operation'] == 'intentionCommand')
        decoded,
  ];

  void clear() {
    _events.clear();
    rawMessages.clear();
  }

  @override
  void record(DiagnosticsEvent event) {
    _events.add(event);
    _developer.record(event);
  }
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('CANARY-отказ-получателя-диагностики');
  }
}

Matcher _failure(Matcher failure) =>
    isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>().having(
      (result) => result.failure,
      'причина',
      failure,
    );

Matcher _succeededCommand(
  IntentionCommandDiagnosticsType commandType,
  FavoriteMarkCommandDiagnosticsStage stage,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having((event) => event.commandType, 'вид команды', commandType)
    .having((event) => event.stage, 'этап', stage)
    .having((event) => event.status, 'исход', isA<DiagnosticsSucceeded>());

Matcher _failedCommand(
  IntentionCommandDiagnosticsType commandType,
  FavoriteMarkCommandDiagnosticsStage stage,
  DiagnosticsFailureCode code,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having((event) => event.commandType, 'вид команды', commandType)
    .having((event) => event.stage, 'этап', stage)
    .having(
      (event) => event.status,
      'исход',
      isA<DiagnosticsFailed>()
          .having((status) => status.code, 'категория', code)
          .having(
            (status) => status.duration,
            'длительность',
            greaterThanOrEqualTo(Duration.zero),
          ),
    );

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _id(int number) => switch (IntentionId.decode(_uuid(number))) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(number, 'number'),
};

/// Намерение фикстуры: время создания растёт с номером.
void _insertIntention(
  sqlite.Database database, {
  required int number,
  required String title,
  String? description,
  bool isArchived = false,
}) {
  final timestamp = DateTime.utc(
    2026,
    10,
    1,
    10,
    number,
  ).microsecondsSinceEpoch;
  database.execute(
    'INSERT INTO intentions (id, title, description, is_action_ready, '
    'is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      _uuid(number),
      title,
      description,
      0,
      isArchived ? 1 : 0,
      timestamp,
      timestamp,
    ],
  );
}

List<Map<String, Object?>> _storedIntentions(sqlite.Database database) => [
  for (final row in database.select('SELECT * FROM intentions ORDER BY id'))
    {...row},
];

/// Отметки с их местами в порядке идентификаторов намерений.
List<(String, int)> _storedMarks(sqlite.Database database) => [
  for (final row in database.select(
    'SELECT intention_id, position FROM favorite_intentions '
    'ORDER BY intention_id',
  ))
    (row['intention_id'] as String, row['position'] as int),
];

Future<ConfirmedGraphResult<IntentionCommandSuccess>> _confirmed(
  DriftPersonalGraphRepository repository,
  IntentionCommand command,
) async {
  final result = await repository.execute(command);
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
  );
  return (result
          as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
      .value;
}

Future<GraphRevision> _revision(DriftPersonalGraphRepository repository) async {
  final result = await repository.getCatalogPage(
    IntentionCatalogQuery(
      scope: IntentionScope.all,
      titleFilter: null,
      order: IntentionCatalogOrder.createdAtAscending,
      pageSize: 10,
    ),
  );
  return (result as ResultSuccess<IntentionCatalogPage>).value.revision;
}

Future<IntentionDetails> _details(
  DriftPersonalGraphRepository repository,
  int number,
) async {
  final result = await repository.watchIntention(_id(number)).first;
  expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
  return (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
      .value
      .value!;
}
