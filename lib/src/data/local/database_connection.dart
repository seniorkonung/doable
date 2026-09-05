part of 'app_database.dart';

/// Типизированное доказательство привязки обязательного SQLite setup.
///
/// Capability не утверждает, что ленивый executor уже открыл соединение.
final class ConfiguredLocalDatabaseConnection {
  const ConfiguredLocalDatabaseConnection._(this._executor);

  final QueryExecutor _executor;
}

enum LocalDatabaseSqlOperation { custom, select, insert, update, delete, batch }

/// Безопасное описание SQL-операции для закрытых тестовых adapters.
final class LocalDatabaseSqlStatement {
  const LocalDatabaseSqlStatement._(
    this.operation,
    this.statements,
    this.arguments,
  );

  factory LocalDatabaseSqlStatement.single(
    LocalDatabaseSqlOperation operation,
    String statement,
    List<Object?> arguments,
  ) => LocalDatabaseSqlStatement._(operation, [statement], arguments);

  factory LocalDatabaseSqlStatement.batch(BatchedStatements statements) =>
      LocalDatabaseSqlStatement._(
        LocalDatabaseSqlOperation.batch,
        statements.statements,
        const [],
      );

  final LocalDatabaseSqlOperation operation;
  final List<String> statements;
  final List<Object?> arguments;
}

/// Узкий hook для tracing и fault injection без доступа к [QueryExecutor].
abstract base class LocalDatabaseConnectionObserver {
  const LocalDatabaseConnectionObserver();

  FutureOr<void> beforeOpen() {}

  FutureOr<void> beforeStatement(LocalDatabaseSqlStatement statement) {}

  FutureOr<void> afterStatement(LocalDatabaseSqlStatement statement) {}

  FutureOr<List<Map<String, Object?>>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) => rows;

  FutureOr<void> beforeClose() {}
}

abstract final class AndroidProductionDatabaseConnection {
  static const databaseName = 'doable';
  static const databaseFileName = '$databaseName.sqlite';

  static File databaseFileIn(Directory applicationDocumentsDirectory) =>
      File.fromUri(applicationDocumentsDirectory.uri.resolve(databaseFileName));

  static List<File> sqliteFilesIn(Directory applicationDocumentsDirectory) {
    final databaseFile = databaseFileIn(applicationDocumentsDirectory);
    return [
      databaseFile,
      File('${databaseFile.path}-wal'),
      File('${databaseFile.path}-shm'),
    ];
  }
}

ConfiguredLocalDatabaseConnection openAndroidProductionDatabaseConnection() =>
    ConfiguredLocalDatabaseConnection._(
      driftDatabase(
        name: AndroidProductionDatabaseConnection.databaseName,
        native: const DriftNativeOptions(
          setup: configureDoableSqliteConnection,
        ),
      ),
    );

ConfiguredLocalDatabaseConnection openInMemoryLocalDatabase({
  DatabaseSetup? setup,
}) => ConfiguredLocalDatabaseConnection._(
  NativeDatabase.memory(setup: composeDoableSqliteConnectionSetup(setup)),
);

ConfiguredLocalDatabaseConnection openFileBackedLocalDatabase(
  File databaseFile, {
  DatabaseSetup? setup,
}) => ConfiguredLocalDatabaseConnection._(
  NativeDatabase(
    databaseFile,
    setup: composeDoableSqliteConnectionSetup(setup),
  ),
);

/// Изолятный test adapter, создающий connection только с обязательным setup.
final class ConfiguredInMemoryLocalDatabaseIsolate {
  const ConfiguredInMemoryLocalDatabaseIsolate._(this._isolate);

  final DriftIsolate _isolate;

  Future<ConfiguredLocalDatabaseConnection> connect() async {
    final connection = await _isolate.connect();
    return ConfiguredLocalDatabaseConnection._(connection.executor);
  }

  Future<void> shutdownAll() => _isolate.shutdownAll();
}

Future<ConfiguredInMemoryLocalDatabaseIsolate>
spawnConfiguredInMemoryLocalDatabaseIsolate() async {
  final isolate = await DriftIsolate.spawn(
    () =>
        NativeDatabase.memory(setup: composeDoableSqliteConnectionSetup(null)),
  );
  return ConfiguredInMemoryLocalDatabaseIsolate._(isolate);
}

ConfiguredLocalDatabaseConnection observeConfiguredLocalDatabaseConnection(
  ConfiguredLocalDatabaseConnection connection,
  LocalDatabaseConnectionObserver observer,
) => ConfiguredLocalDatabaseConnection._(
  connection._executor.interceptWith(
    _LocalDatabaseObserverInterceptor(observer),
  ),
);

final class _LocalDatabaseObserverInterceptor extends QueryInterceptor {
  _LocalDatabaseObserverInterceptor(this._observer);

  final LocalDatabaseConnectionObserver _observer;

  @override
  Future<bool> ensureOpen(
    QueryExecutor executor,
    QueryExecutorUser user,
  ) async {
    await _observer.beforeOpen();
    return executor.ensureOpen(_ObservedQueryExecutorUser(user, this));
  }

  @override
  Future<void> close(QueryExecutor inner) async {
    await _observer.beforeClose();
    await inner.close();
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _runVoid(
    LocalDatabaseSqlStatement.batch(statements),
    () => executor.runBatched(statements),
  );

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> arguments,
  ) => _runVoid(
    LocalDatabaseSqlStatement.single(
      LocalDatabaseSqlOperation.custom,
      statement,
      arguments,
    ),
    () => executor.runCustom(statement, arguments),
  );

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> arguments,
  ) => _run(
    LocalDatabaseSqlStatement.single(
      LocalDatabaseSqlOperation.insert,
      statement,
      arguments,
    ),
    () => executor.runInsert(statement, arguments),
  );

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> arguments,
  ) => _run(
    LocalDatabaseSqlStatement.single(
      LocalDatabaseSqlOperation.delete,
      statement,
      arguments,
    ),
    () => executor.runDelete(statement, arguments),
  );

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> arguments,
  ) => _run(
    LocalDatabaseSqlStatement.single(
      LocalDatabaseSqlOperation.update,
      statement,
      arguments,
    ),
    () => executor.runUpdate(statement, arguments),
  );

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> arguments,
  ) async {
    final sqlStatement = LocalDatabaseSqlStatement.single(
      LocalDatabaseSqlOperation.select,
      statement,
      arguments,
    );
    await _observer.beforeStatement(sqlStatement);
    final rows = await executor.runSelect(statement, arguments);
    final observedRows = await _observer.afterSelect(sqlStatement, rows);
    await _observer.afterStatement(sqlStatement);
    return observedRows;
  }

  Future<T> _run<T>(
    LocalDatabaseSqlStatement statement,
    Future<T> Function() operation,
  ) async {
    await _observer.beforeStatement(statement);
    final result = await operation();
    await _observer.afterStatement(statement);
    return result;
  }

  Future<void> _runVoid(
    LocalDatabaseSqlStatement statement,
    Future<void> Function() operation,
  ) async {
    await _observer.beforeStatement(statement);
    await operation();
    await _observer.afterStatement(statement);
  }
}

final class _ObservedQueryExecutorUser implements QueryExecutorUser {
  const _ObservedQueryExecutorUser(this._delegate, this._interceptor);

  final QueryExecutorUser _delegate;
  final QueryInterceptor _interceptor;

  @override
  int get schemaVersion => _delegate.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) {
    return _delegate.beforeOpen(executor.interceptWith(_interceptor), details);
  }
}
