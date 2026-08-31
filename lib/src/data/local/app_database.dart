import 'package:drift/drift.dart';

import 'migrations/migration_strategy.dart';

part 'app_database.g.dart';

@DriftDatabase(include: {'schema/intention_schema.drift'})
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static const currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => localDataMigrationStrategy(this);

  Future<void> open() async {
    final foreignKeys = await customSelect('PRAGMA foreign_keys').getSingle();
    if (foreignKeys.read<int>('foreign_keys') != 1) {
      throw StateError('Внешние ключи не включены после открытия базы данных.');
    }
  }
}
