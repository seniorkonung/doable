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
    // Три отказа покрывают вид команды (вставка и удаление строки), этап
    // (проверка и запись) и каждую категорию отказа хранилища: ветки
    // отката и классификации общие, поэтому полное произведение не нужно.
    for (final (command, fault, point) in [
      (_commands[0], _storageFaults[0], _FaultPoint.afterWrite),
      (_commands[1], _storageFaults[1], _FaultPoint.afterWrite),
      (_commands[0], _storageFaults[2], _FaultPoint.validationRead),
    ]) {
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
        IntentionCommandDiagnosticsType type,
        FavoriteMark markBefore,
      })
    >[
      (
        name: 'отметка',
        number: 3,
        build: () => MarkIntentionFavorite(_id(3)),
        type: IntentionCommandDiagnosticsType.markFavorite,
        markBefore: FavoriteMark.notFavorite,
      ),
      (
        name: 'снятие отметки',
        number: 1,
        build: () => UnmarkIntentionFavorite(_id(1)),
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

  /// Запись строки отметки выполнена, но не подтверждена.
  afterWrite('после записи отметки', FavoriteMarkCommandDiagnosticsStage.write);

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
    if (!_wroteMark &&
        statement.statements.single.contains('FROM favorite_intentions')) {
      _failAt(_FaultPoint.validationRead);
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

/// Сохраняет события диагностики команд намерения.
final class _RecordingDiagnostics implements DiagnosticsSink {
  final _events = <DiagnosticsEvent>[];

  List<IntentionCommandDiagnosticsEvent> get commandEvents =>
      _events.whereType<IntentionCommandDiagnosticsEvent>().toList();

  void clear() {
    _events.clear();
  }

  @override
  void record(DiagnosticsEvent event) {
    _events.add(event);
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
