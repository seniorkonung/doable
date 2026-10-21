import 'dart:io';

import 'package:doable/src/data/local/sqlite_failure_classifier.dart';
import 'package:drift/drift.dart' show CouldNotRollBackException;
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

    // Коды занятости и блокировки хранятся одним набором: проверены общие и
    // расширенные коды обоих семейств.
    test(
      'классифицирует временные коды занятости и блокировки как недоступность',
      () {
        for (final code in [
          SqlError.SQLITE_BUSY,
          SqlExtendedError.SQLITE_BUSY_SNAPSHOT,
          SqlError.SQLITE_LOCKED,
          SqlExtendedError.SQLITE_LOCKED_SHAREDCACHE,
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
      },
    );

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

    test('относит к нехватке места SQLITE_FULL настоящего SQLite, которому '
        'не хватило страниц базы', () {
      final database = sqlite3.openInMemory();
      addTearDown(database.close);
      database.execute('CREATE TABLE payload (bytes BLOB)');
      final pageCount = database.select('PRAGMA page_count').single.columnAt(0);
      database.execute('PRAGMA max_page_count = $pageCount');

      expect(
        () => database.execute('INSERT INTO payload VALUES (zeroblob(65536))'),
        throwsA(
          isA<SqliteException>().having(
            classifySqliteFailure,
            'классификация',
            isA<SqliteStorageFullFailure>(),
          ),
        ),
      );
    });

    test('относит к нехватке места только отказ файловой системы ENOSPC', () {
      expect(
        classifySqliteFailure(
          const FileSystemException(
            'CANARY-личные-данные',
            'CANARY-путь',
            OSError('No space left on device', 28),
          ),
        ),
        isA<SqliteStorageFullFailure>(),
      );
      expect(
        classifySqliteFailure(
          const FileSystemException(
            'CANARY-личные-данные',
            'CANARY-путь',
            OSError('Permission denied', 13),
          ),
        ),
        isA<SqliteUnexpectedFailure>(),
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

    // Drift сообщает об отказе ROLLBACK, когда SQLite после SQLITE_FULL уже
    // сам откатил всю транзакцию. Из фонового соединения обе ошибки приходят
    // в DriftRemoteException.
    test('относит отказ отката транзакции из фонового соединения к категории '
        'ошибки, из-за которой транзакция откатывалась', () {
      final failure = classifySqliteFailure(
        CouldNotRollBackException(
          _NestedDriftRemoteException(
            SqliteException(
              extendedResultCode: SqlError.SQLITE_FULL,
              message: 'CANARY-личные-данные',
            ),
          ),
          StackTrace.empty,
          _NestedDriftRemoteException(
            SqliteException(
              extendedResultCode: SqlError.SQLITE_ERROR,
              message: 'cannot rollback - no transaction is active',
            ),
          ),
        ),
      );

      expect(failure, isA<SqliteStorageFullFailure>());
    });

    // Достаточно общего кода и кодов, от которых зависит приложение
    // (первичный ключ — конфликт создания, уникальность — конфликт тега),
    // а также внешнего ключа и триггера схемы.
    test(
      'сохраняет extended код известных constraint без предметного conflict',
      () {
        for (final code in [
          SqlError.SQLITE_CONSTRAINT,
          SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY,
          SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY,
          SqlExtendedError.SQLITE_CONSTRAINT_TRIGGER,
          SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
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
      },
    );

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
