import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:drift/native.dart';

import 'in_memory_diagnostics_sink.dart';

final class LocalDatabaseHarness {
  LocalDatabaseHarness._({
    required _LocalDatabaseStorage storage,
    Directory? temporaryDirectory,
    File? databaseFile,
  }) : _storage = storage,
       _temporaryDirectory = temporaryDirectory,
       _databaseFile = databaseFile;

  factory LocalDatabaseHarness.inMemory() =>
      LocalDatabaseHarness._(storage: _LocalDatabaseStorage.inMemory);

  static Future<LocalDatabaseHarness> fileBacked() async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'doable_local_database_',
    );
    return LocalDatabaseHarness._(
      storage: _LocalDatabaseStorage.fileBacked,
      temporaryDirectory: temporaryDirectory,
      databaseFile: File('${temporaryDirectory.path}/doable.sqlite'),
    );
  }

  final _LocalDatabaseStorage _storage;
  final Directory? _temporaryDirectory;
  final File? _databaseFile;
  LocalDataBootstrap? _bootstrap;
  var _isDisposed = false;

  File get databaseFile =>
      _databaseFile ??
      (throw StateError('In-memory harness не имеет SQLite-файла.'));

  Directory get temporaryDirectory =>
      _temporaryDirectory ??
      (throw StateError('In-memory harness не имеет временного каталога.'));

  Future<LocalDataBootstrapResult> open({DatabaseSetup? setup}) {
    if (_isDisposed) {
      throw StateError('Нельзя открыть уже освобождённый database harness.');
    }
    if (_bootstrap != null) {
      throw StateError('Текущий persistence object graph уже открыт.');
    }

    final bootstrap = LocalDataBootstrap(
      executorFactory: () => switch (_storage) {
        _LocalDatabaseStorage.inMemory => NativeDatabase.memory(setup: setup),
        _LocalDatabaseStorage.fileBacked => NativeDatabase(
          databaseFile,
          setup: setup,
        ),
      },
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    _bootstrap = bootstrap;
    return bootstrap.open();
  }

  Future<AppDatabase> openReadyDatabase({DatabaseSetup? setup}) async {
    final result = await open(setup: setup);
    if (result is LocalDataReady) return result.database;
    throw StateError('Bootstrap не предоставил готовое локальное хранилище.');
  }

  Future<void> closePersistenceObjectGraph() async {
    final bootstrap = _bootstrap;
    _bootstrap = null;
    await bootstrap?.close();
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    try {
      await closePersistenceObjectGraph();
    } finally {
      final temporaryDirectory = _temporaryDirectory;
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }
}

enum _LocalDatabaseStorage { inMemory, fileBacked }
