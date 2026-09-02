import 'package:drift/isolate.dart';
import 'package:sqlite3/sqlite3.dart';

sealed class SqliteFailure {
  const SqliteFailure();
}

final class SqliteCorruptionFailure extends SqliteFailure {
  const SqliteCorruptionFailure();
}

final class SqliteUnavailableFailure extends SqliteFailure {
  const SqliteUnavailableFailure();
}

final class SqliteConstraintFailure extends SqliteFailure {
  const SqliteConstraintFailure(this.extendedResultCode);

  final int extendedResultCode;
}

final class SqliteUnexpectedFailure extends SqliteFailure {
  const SqliteUnexpectedFailure();
}

SqliteFailure classifySqliteFailure(Object error) {
  final cause = unwrapDriftRemoteException(error);
  return switch (cause) {
    SqliteException(:final resultCode, :final extendedResultCode) =>
      switch (resultCode) {
        SqlError.SQLITE_CORRUPT ||
        SqlError.SQLITE_NOTADB => const SqliteCorruptionFailure(),
        SqlError.SQLITE_BUSY ||
        SqlError.SQLITE_LOCKED ||
        SqlError.SQLITE_CANTOPEN ||
        SqlError.SQLITE_IOERR => const SqliteUnavailableFailure(),
        SqlError.SQLITE_CONSTRAINT => SqliteConstraintFailure(
          extendedResultCode,
        ),
        _ => const SqliteUnexpectedFailure(),
      },
    _ => const SqliteUnexpectedFailure(),
  };
}

Object unwrapDriftRemoteException(Object error) {
  var cause = error;
  while (cause is DriftRemoteException) {
    cause = cause.remoteCause;
  }
  return cause;
}
