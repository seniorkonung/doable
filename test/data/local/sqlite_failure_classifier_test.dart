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

    test('разрешает retry только для точной временной SQLite allowlist', () {
      for (final code in [
        SqlError.SQLITE_BUSY,
        SqlExtendedError.SQLITE_BUSY_RECOVERY,
        SqlExtendedError.SQLITE_BUSY_SNAPSHOT,
        SqlExtendedError.SQLITE_BUSY_TIMEOUT,
        SqlError.SQLITE_LOCKED,
        SqlExtendedError.SQLITE_LOCKED_SHAREDCACHE,
        SqlExtendedError.SQLITE_LOCKED_VTAB,
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

    test('классифицирует IOERR_DATA как повреждение', () {
      expect(
        classifySqliteFailure(
          SqliteException(
            extendedResultCode: SqlExtendedError.SQLITE_IOERR_DATA,
            message: 'CANARY-личные-данные',
          ),
        ),
        isA<SqliteCorruptionFailure>(),
      );
    });

    test('оставляет первичные и неизвестные extended коды unexpected', () {
      for (final code in [
        SqlError.SQLITE_CANTOPEN,
        SqlExtendedError.SQLITE_CANTOPEN_ISDIR,
        SqlError.SQLITE_IOERR,
        _sqliteIoerrCorruptFs,
        SqlError.SQLITE_BUSY | (999 << 8),
        SqlError.SQLITE_CONSTRAINT | (999 << 8),
      ]) {
        expect(
          classifySqliteFailure(
            SqliteException(
              extendedResultCode: code,
              message: 'CANARY-личные-данные',
            ),
          ),
          isA<SqliteUnexpectedFailure>(),
        );
      }
    });

    test('раскрывает вложенные DriftRemoteException до SQLite причины', () {
      final failure = classifySqliteFailure(
        _NestedDriftRemoteException(
          _NestedDriftRemoteException(
            SqliteException(
              extendedResultCode: SqlExtendedError.SQLITE_IOERR_DATA,
              message: 'CANARY-личные-данные',
            ),
          ),
        ),
      );

      expect(failure, isA<SqliteCorruptionFailure>());
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

const _sqliteIoerrCorruptFs = 8458;
