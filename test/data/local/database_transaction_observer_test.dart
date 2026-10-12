import 'package:doable/src/data/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_database_harness.dart';

void main() {
  test('наблюдатель охватывает чтение и завершение транзакции', () async {
    final harness = LocalDatabaseHarness.inMemory();
    addTearDown(harness.dispose);
    final observer = _TransactionObserver();
    final database = await harness.openReadyDatabase(observer: observer);
    observer.events.clear();

    await database.transaction(() async {
      await database.customSelect('SELECT 1').getSingle();
      observer.events.add('чтение');
    });
    expect(observer.events, ['начало', 'чтение', 'конец']);

    observer.events.clear();
    await expectLater(
      database.transaction(() async => throw StateError('откат')),
      throwsStateError,
    );
    expect(observer.events, ['начало', 'конец']);
  });
}

final class _TransactionObserver extends LocalDatabaseConnectionObserver {
  final events = <String>[];

  @override
  void onTransactionStarted() => events.add('начало');

  @override
  void onTransactionFinished() => events.add('конец');
}
