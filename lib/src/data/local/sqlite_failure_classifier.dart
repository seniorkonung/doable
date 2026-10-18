import 'dart:io';

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

/// Нехватка места на устройстве: SQLite сообщил `SQLITE_FULL`, в том числе
/// при достижении `PRAGMA max_page_count`, или запись файла отказала с
/// `ENOSPC`.
final class SqliteStorageFullFailure extends SqliteFailure {
  const SqliteStorageFullFailure();
}

final class SqliteUnexpectedFailure extends SqliteFailure {
  const SqliteUnexpectedFailure();
}

SqliteFailure classifySqliteFailure(Object error) {
  final cause = unwrapDriftRemoteException(error);
  return switch (cause) {
    SqliteException(:final extendedResultCode) => switch (extendedResultCode) {
      SqlExtendedError.SQLITE_IOERR_DATA => const SqliteCorruptionFailure(),
      SqlError.SQLITE_FULL => const SqliteStorageFullFailure(),
      _ when _isCorruptionFamily(extendedResultCode) =>
        const SqliteCorruptionFailure(),
      _ when _unavailableExtendedResultCodes.contains(extendedResultCode) =>
        const SqliteUnavailableFailure(),
      _ when _constraintExtendedResultCodes.contains(extendedResultCode) =>
        SqliteConstraintFailure(extendedResultCode),
      _ => const SqliteUnexpectedFailure(),
    },
    FileSystemException(osError: OSError(errorCode: _enospc)) =>
      const SqliteStorageFullFailure(),
    _ => const SqliteUnexpectedFailure(),
  };
}

/// Код `ENOSPC` в Linux и Android.
const _enospc = 28;

const _unavailableExtendedResultCodes = <int>{
  SqlError.SQLITE_BUSY,
  SqlExtendedError.SQLITE_BUSY_RECOVERY,
  SqlExtendedError.SQLITE_BUSY_SNAPSHOT,
  SqlExtendedError.SQLITE_BUSY_TIMEOUT,
  SqlError.SQLITE_LOCKED,
  SqlExtendedError.SQLITE_LOCKED_SHAREDCACHE,
  SqlExtendedError.SQLITE_LOCKED_VTAB,
};

const _constraintExtendedResultCodes = <int>{
  SqlError.SQLITE_CONSTRAINT,
  SqlExtendedError.SQLITE_CONSTRAINT_CHECK,
  SqlExtendedError.SQLITE_CONSTRAINT_COMMITHOOK,
  SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY,
  SqlExtendedError.SQLITE_CONSTRAINT_FUNCTION,
  SqlExtendedError.SQLITE_CONSTRAINT_NOTNULL,
  SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY,
  SqlExtendedError.SQLITE_CONSTRAINT_TRIGGER,
  SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
  SqlExtendedError.SQLITE_CONSTRAINT_VTAB,
  SqlExtendedError.SQLITE_CONSTRAINT_ROWID,
  SqlExtendedError.SQLITE_CONSTRAINT_PINNED,
};

bool _isCorruptionFamily(int extendedResultCode) {
  final primaryResultCode = _primaryResultCode(extendedResultCode);
  return primaryResultCode == SqlError.SQLITE_CORRUPT ||
      primaryResultCode == SqlError.SQLITE_NOTADB;
}

int _primaryResultCode(int extendedResultCode) => extendedResultCode & 0xff;

Object unwrapDriftRemoteException(Object error) {
  var cause = error;
  while (cause is DriftRemoteException) {
    cause = cause.remoteCause;
  }
  return cause;
}
