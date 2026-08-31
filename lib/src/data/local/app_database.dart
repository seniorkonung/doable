import 'package:drift/drift.dart';

final class AppDatabase {
  AppDatabase(this._executor);

  final QueryExecutor _executor;

  Future<void> close() => _executor.close();
}
