import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/data/drift_intention_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late _DeterministicIntentionIdGenerator idGenerator;
  late _DeterministicClock clock;
  late DriftIntentionRepository repository;
  late _WriteTrace writeTrace;

  setUp(() async {
    writeTrace = _WriteTrace();
    database = AppDatabase(NativeDatabase.memory().interceptWith(writeTrace));
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    idGenerator = _DeterministicIntentionIdGenerator([_id(_firstUuid)]);
    clock = _DeterministicClock([DateTime.utc(2026, 9, 3, 12)]);
    repository = DriftIntentionRepository(
      database,
      idGenerator,
      clock.call,
      diagnostics,
    );
  });

  tearDown(() => database.close());

  group('DriftIntentionRepository.execute', () {
    test('создаёт active not-ready намерение с нормализованными данными и единым UTC-временем', () async {
      final result = await repository.execute(
        const CreateIntention(
          title: '  Купить  молоко  ',
          description: '  В фермерском магазине\n',
        ),
      );

      final saved = _saved(result);
      expect(saved.id, _id(_firstUuid));
      expect(saved.title, 'Купить  молоко');
      expect(saved.description, '  В фермерском магазине\n');
      expect(saved.readiness, IntentionReadiness.notReady);
      expect(saved.archiveState, IntentionArchiveState.active);
      expect(saved.createdAt.value, DateTime.utc(2026, 9, 3, 12));
      expect(saved.createdAt.value.isUtc, isTrue);
      expect(saved.updatedAt, saved.createdAt);
      expect(idGenerator.generated, [_id(_firstUuid)]);
      expect(clock.calls, 1);
      expect(diagnostics.events, [
        _successfulCommand(IntentionCommandDiagnosticsType.create),
      ]);
    });

    test('допускает два намерения с одинаковым названием и разными идентификаторами', () async {
      final secondId = _id(_secondUuid);
      idGenerator = _DeterministicIntentionIdGenerator([
        _id(_firstUuid),
        secondId,
      ]);
      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftIntentionRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );

      final first = _saved(
        await repository.execute(
          const CreateIntention(title: 'Быть здоровым', description: null),
        ),
      );
      final second = _saved(
        await repository.execute(
          const CreateIntention(title: 'Быть здоровым', description: null),
        ),
      );

      expect(first.id, _id(_firstUuid));
      expect(second.id, secondId);
      expect(first.id, isNot(second.id));
      expect(await database.select(database.intentions).get(), hasLength(2));
    });

    test(
      'отклоняет недопустимый Unicode title до генерации ID и записи',
      () async {
        final title = List.filled(256, '👩🏽‍💻').join();

        final result = await repository.execute(
          CreateIntention(title: title, description: null),
        );

        expect(result, _failure<IntentionValidationFailure>());
        expect(idGenerator.generated, isEmpty);
        expect(clock.calls, 0);
        expect(await database.select(database.intentions).get(), isEmpty);
        expect(diagnostics.events, [
          _failedCommand(
            IntentionCommandDiagnosticsType.create,
            DiagnosticsFailureCode.validation,
          ),
        ]);
      },
    );

    test('принимает title из 255 Unicode-графем', () async {
      final title = List.filled(255, '👩🏽‍💻').join();

      final result = await repository.execute(
        CreateIntention(title: title, description: '  \n\t  '),
      );

      final saved = _saved(result);
      expect(saved.title, title);
      expect(saved.description, isNull);
    });

    test('возвращает conflict при collision нового первичного ключа и не перезаписывает строку', () async {
      await _insertIntention(
        database,
        id: _firstUuid,
        title: 'Существующее намерение',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );

      final result = await repository.execute(
        const CreateIntention(title: 'Новое намерение', description: null),
      );

      expect(result, _failure<IntentionConflictFailure>());
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(_firstUuid))).getSingle();
      expect(row.title, 'Существующее намерение');
      expect(
        row.createdAt,
        DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch,
      );
      expect(diagnostics.events, [
        _failedCommand(
          IntentionCommandDiagnosticsType.create,
          DiagnosticsFailureCode.conflict,
        ),
      ]);
    });

    test('изменяет active и archived намерения, сохраняя их остальные подтверждённые данные', () async {
      final fixtures = [
        (
          id: _id(_firstUuid),
          isActionReady: false,
          isArchived: false,
          createdAt: DateTime.utc(2026, 9, 2, 10),
        ),
        (
          id: _id(_secondUuid),
          isActionReady: true,
          isArchived: true,
          createdAt: DateTime.utc(2026, 9, 2, 11),
        ),
      ];
      for (final fixture in fixtures) {
        await _insertIntention(
          database,
          id: fixture.id.toCanonicalString(),
          title: 'Исходное название',
          description: 'Исходное описание',
          isActionReady: fixture.isActionReady,
          isArchived: fixture.isArchived,
          createdAt: fixture.createdAt,
        );
      }

      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftIntentionRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );

      for (var index = 0; index < fixtures.length; index++) {
        final fixture = fixtures[index];
        final result = await repository.execute(
          UpdateIntention(
            id: fixture.id,
            title: '  Обновлённое  название  ',
            description: '  Новое описание\n',
          ),
        );

        final saved = _saved(result);
        expect(saved.id, fixture.id);
        expect(saved.title, 'Обновлённое  название');
        expect(saved.description, '  Новое описание\n');
        expect(
          saved.readiness,
          fixture.isActionReady
              ? IntentionReadiness.ready
              : IntentionReadiness.notReady,
        );
        expect(
          saved.archiveState,
          fixture.isArchived
              ? IntentionArchiveState.archived
              : IntentionArchiveState.active,
        );
        expect(saved.createdAt.value, fixture.createdAt);
        expect(saved.updatedAt.value, DateTime.utc(2026, 9, 3, 12 + index));
      }

      final updatedRows = await database.select(database.intentions).get();
      expect(
        updatedRows.map((row) => row.titleSearchKey),
        everyElement('обновлённое  название'),
      );
      expect(diagnostics.events, [
        _successfulCommand(IntentionCommandDiagnosticsType.update),
        _successfulCommand(IntentionCommandDiagnosticsType.update),
      ]);
    });

    test(
      'не выполняет запись и возвращает прежнее намерение при no-op update',
      () async {
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: id.toCanonicalString(),
          title: 'Неизменное название',
          description: 'Неизменное описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        clock = _DeterministicClock([DateTime.utc(2026, 9, 3, 12)]);
        repository = DriftIntentionRepository(
          database,
          idGenerator,
          clock.call,
          diagnostics,
        );
        writeTrace.updateStatements.clear();

        final result = await repository.execute(
          UpdateIntention(
            id: id,
            title: 'Неизменное название',
            description: 'Неизменное описание',
          ),
        );

        final saved = _saved(result);
        expect(saved.updatedAt.value, createdAt);
        expect(saved.createdAt.value, createdAt);
        expect(clock.calls, 0);
        expect(writeTrace.updateStatements, isEmpty);
      },
    );

    test('оставляет прежнее намерение при недопустимом изменении', () async {
      final id = _id(_firstUuid);
      final createdAt = DateTime.utc(2026, 9, 2, 10);
      await _insertIntention(
        database,
        id: id.toCanonicalString(),
        title: 'Исходное название',
        description: 'Исходное описание',
        createdAt: createdAt,
      );
      writeTrace.updateStatements.clear();

      final result = await repository.execute(
        UpdateIntention(id: id, title: '  \n\t  ', description: null),
      );

      expect(result, _failure<IntentionValidationFailure>());
      expect(clock.calls, 0);
      expect(writeTrace.updateStatements, isEmpty);
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
      expect(row.title, 'Исходное название');
      expect(row.description, 'Исходное описание');
      expect(row.updatedAt, createdAt.microsecondsSinceEpoch);
    });

    test(
      'возвращает not-found при изменении отсутствующего намерения',
      () async {
        final result = await repository.execute(
          UpdateIntention(
            id: _id(_firstUuid),
            title: 'Новое название',
            description: null,
          ),
        );

        expect(result, _failure<IntentionNotFoundFailure>());
        expect(clock.calls, 0);
        expect(diagnostics.events, [
          _failedCommand(
            IntentionCommandDiagnosticsType.update,
            DiagnosticsFailureCode.notFound,
          ),
        ]);
      },
    );
  });
}

const _firstUuid = '018f0b5d-6b2e-7c80-8000-000000000401';
const _secondUuid = '018f0b5d-6b2e-7c80-8000-000000000402';

Intention _saved(Result<IntentionCommandSuccess> result) {
  expect(result, isA<ResultSuccess<IntentionCommandSuccess>>());
  final success = (result as ResultSuccess<IntentionCommandSuccess>).value;
  expect(success, isA<IntentionSaved>());
  return (success as IntentionSaved).intention;
}

Matcher _failure<TFailure extends IntentionFailure>() =>
    isA<ResultFailure<IntentionCommandSuccess>>().having(
      (result) => result.failure,
      'failure',
      isA<TFailure>(),
    );

Matcher _successfulCommand(IntentionCommandDiagnosticsType commandType) =>
    isA<IntentionCommandDiagnosticsEvent>()
        .having((event) => event.commandType, 'commandType', commandType)
        .having((event) => event.status, 'status', isA<DiagnosticsSucceeded>());

Matcher _failedCommand(
  IntentionCommandDiagnosticsType commandType,
  DiagnosticsFailureCode failureCode,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having((event) => event.commandType, 'commandType', commandType)
    .having(
      (event) => event.status,
      'status',
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'code',
        failureCode,
      ),
    );

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

Future<void> _insertIntention(
  AppDatabase database, {
  required String id,
  required String title,
  String? description,
  bool isActionReady = false,
  bool isArchived = false,
  required DateTime createdAt,
}) => database
    .into(database.intentions)
    .insert(
      IntentionsCompanion.insert(
        id: id,
        title: title,
        titleSearchKey: title.toLowerCase(),
        description: Value(description),
        isActionReady: Value(isActionReady),
        isArchived: Value(isArchived),
        createdAt: createdAt.microsecondsSinceEpoch,
        updatedAt: createdAt.microsecondsSinceEpoch,
      ),
    );

final class _DeterministicIntentionIdGenerator implements IntentionIdGenerator {
  _DeterministicIntentionIdGenerator(Iterable<IntentionId> ids)
    : _ids = List.unmodifiable(ids);

  final List<IntentionId> _ids;
  final List<IntentionId> generated = [];

  @override
  IntentionId generate() {
    if (generated.length == _ids.length) {
      throw StateError('Последовательность идентификаторов исчерпана.');
    }
    final id = _ids[generated.length];
    generated.add(id);
    return id;
  }
}

final class _DeterministicClock {
  _DeterministicClock(Iterable<DateTime> values)
    : _values = List.unmodifiable(values);

  final List<DateTime> _values;
  var calls = 0;

  DateTime call() {
    if (calls == _values.length) {
      throw StateError('Последовательность времени исчерпана.');
    }
    return _values[calls++];
  }
}

final class _WriteTrace extends QueryInterceptor {
  final List<String> updateStatements = [];

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    updateStatements.add(statement);
    return super.runUpdate(executor, statement, args);
  }
}
