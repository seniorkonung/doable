import 'package:doable/src/data/local/sqlite_failure_classifier.dart';
import 'package:drift/isolate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('SqliteFailureClassifier', () {
    test(
      'распознаёт primary и extended коды повреждения без текста ошибки',
      () {
        for (final code in [
          SqlError.SQLITE_CORRUPT,
          SqlExtendedError.SQLITE_CORRUPT_VTAB,
          SqlExtendedError.SQLITE_CORRUPT_SEQUENCE,
          SqlExtendedError.SQLITE_CORRUPT_INDEX,
          SqlError.SQLITE_NOTADB,
        ]) {
          expect(
            classifySqliteFailure(
              SqliteException(
                extendedResultCode: code,
                message: 'Временная недоступность: CANARY-личные-данные',
              ),
            ),
            isA<SqliteCorruptionFailure>(),
          );
        }
      },
    );

    test('разрешает retry только для временной SQLite allowlist', () {
      for (final code in [
        SqlError.SQLITE_BUSY,
        SqlExtendedError.SQLITE_BUSY_RECOVERY,
        SqlError.SQLITE_LOCKED,
        SqlExtendedError.SQLITE_LOCKED_SHAREDCACHE,
        SqlError.SQLITE_CANTOPEN,
        SqlExtendedError.SQLITE_CANTOPEN_ISDIR,
        SqlError.SQLITE_IOERR,
        SqlExtendedError.SQLITE_IOERR_READ,
      ]) {
        expect(
          classifySqliteFailure(
            SqliteException(
              extendedResultCode: code,
              message: 'SQLite-файл повреждён: CANARY-личные-данные',
            ),
          ),
          isA<SqliteUnavailableFailure>(),
        );
      }
    });

    test('раскрывает вложенные DriftRemoteException до SQLite причины', () {
      final failure = classifySqliteFailure(
        _NestedDriftRemoteException(
          _NestedDriftRemoteException(
            SqliteException(
              extendedResultCode: SqlExtendedError.SQLITE_BUSY_RECOVERY,
              message: 'CANARY-личные-данные',
            ),
          ),
        ),
      );

      expect(failure, isA<SqliteUnavailableFailure>());
    });

    test('сохраняет extended код всех известных constraint без предметного conflict', () {
      for (final code in [
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
      ]) {
        final failure = classifySqliteFailure(
          SqliteException(
            extendedResultCode: code,
            message: 'Конфликт намерения: CANARY-личные-данные',
          ),
        );

        expect(
          failure,
          isA<SqliteConstraintFailure>().having(
            (failure) => failure.extendedResultCode,
            'extendedResultCode',
            code,
          ),
        );
      }
    });

    test('неизвестные SQLite и non-SQLite причины остаются unexpected', () {
      expect(
        classifySqliteFailure(
          SqliteException(
            extendedResultCode: SqlError.SQLITE_READONLY,
            message: 'CANARY-личные-данные',
          ),
        ),
        isA<SqliteUnexpectedFailure>(),
      );
      expect(
        classifySqliteFailure(StateError('CANARY-личные-данные')),
        isA<SqliteUnexpectedFailure>(),
      );
    });
  });
}

final class _NestedDriftRemoteException implements DriftRemoteException {
  const _NestedDriftRemoteException(this.remoteCause);

  @override
  final Object remoteCause;

  @override
  StackTrace? get remoteStackTrace => null;
}
