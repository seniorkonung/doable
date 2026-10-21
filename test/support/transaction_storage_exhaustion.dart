import 'package:doable/src/data/local/app_database.dart'
    show LocalDatabaseConnectionObserver, LocalDatabaseSqlStatement;
import 'package:sqlite3/sqlite3.dart';

/// Перед оператором, который выбирает [exhaustsBefore], исчерпывает место
/// хранилища так, что SQLite сам откатывает всю идущую транзакцию, а не
/// один оператор, как при отказе записи на заполненном устройстве.
///
/// В соединении [storage] запрещает файлу расти и вставляет строку, которой
/// не хватает свободных страниц, в таблицу без триггеров. У такой
/// однострочной вставки нет журнала оператора, поэтому после `SQLITE_FULL`
/// SQLite откатывает всю транзакцию. Ошибка [SqliteException] этой вставки
/// становится отказом выбранного оператора, а `ROLLBACK` от Drift затем
/// отказывает: транзакции уже нет.
base class TransactionStorageExhaustion
    extends LocalDatabaseConnectionObserver {
  /// Соединение SQLite хранилища, которое передаёт setup соединения.
  late Database storage;

  bool Function(LocalDatabaseSqlStatement statement)? exhaustsBefore;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (exhaustsBefore?.call(statement) ?? false) _exhaustStorage();
  }

  void _exhaustStorage() {
    // Таблица создаётся в транзакции и исчезает вместе с её откатом.
    storage.execute('CREATE TABLE storage_exhaustion (bytes BLOB NOT NULL)');
    final pages = storage
        .select(
          'SELECT page_count, freelist_count, page_size '
          'FROM pragma_page_count, pragma_freelist_count, pragma_page_size',
        )
        .single;
    storage
      ..execute('PRAGMA max_page_count = ${pages['page_count']}')
      // Строка длиннее всех свободных страниц, поэтому файлу пришлось бы
      // расти.
      ..execute('INSERT INTO storage_exhaustion VALUES (zeroblob(?))', [
        ((pages['freelist_count'] as int) + 1) * (pages['page_size'] as int),
      ]);
  }
}
