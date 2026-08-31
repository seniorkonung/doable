import 'package:drift/drift.dart';

part 'app_database.g.dart';

@DriftDatabase(include: {'schema/intention_schema.drift'})
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
