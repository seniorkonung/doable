import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'migrations/migration_strategy.dart';
import '../../shared/diagnostics/diagnostics_sink.dart';
import 'sqlite_connection_setup.dart';

part 'app_database.g.dart';
part 'database_connection.dart';

@DriftDatabase(include: {'schema/intention_schema.drift'})
final class AppDatabase extends _$AppDatabase {
  AppDatabase(
    ConfiguredLocalDatabaseConnection connection, {
    this.diagnosticsSink,
  }) : super(connection._executor);

  static const currentSchemaVersion = 1;
  final DiagnosticsSink? diagnosticsSink;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration =>
      localDataMigrationStrategy(this, diagnosticsSink: diagnosticsSink);

  Future<void> open() async {
    final foreignKeys = await customSelect('PRAGMA foreign_keys').getSingle();
    if (foreignKeys.read<int>('foreign_keys') != 1) {
      throw StateError('Внешние ключи не включены после открытия базы данных.');
    }
  }
}
