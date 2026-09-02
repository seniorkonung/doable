import '../app_database.dart';

sealed class LocalDataBootstrapResult {
  const LocalDataBootstrapResult();
}

final class LocalDataReady extends LocalDataBootstrapResult {
  const LocalDataReady(this.database);

  final AppDatabase database;
}

final class LocalDataRetryableFailure extends LocalDataBootstrapResult {
  const LocalDataRetryableFailure();
}

final class LocalDataCorruption extends LocalDataBootstrapResult {
  const LocalDataCorruption();
}

final class LocalDataUnexpectedFailure extends LocalDataBootstrapResult {
  const LocalDataUnexpectedFailure();
}

final class LocalDataIncompatibleSchema extends LocalDataBootstrapResult {
  const LocalDataIncompatibleSchema({
    required this.expectedSchemaVersion,
    required this.detectedSchemaVersion,
  });

  final int expectedSchemaVersion;
  final int detectedSchemaVersion;
}
