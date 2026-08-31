import 'package:doable/src/data/local/bootstrap/local_data_bootstrap.dart';
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_diagnostics_sink.dart';

void main() {
  group('LocalDataBootstrap', () {
    test(
      'открывает новую базу и предоставляет её только в результате ready',
      () async {
        final bootstrap = LocalDataBootstrap(
          executorFactory: NativeDatabase.memory,
          diagnosticsSink: InMemoryDiagnosticsSink(),
        );
        addTearDown(bootstrap.close);

        final result = await bootstrap.open();

        expect(result, isA<LocalDataReady>());
        final ready = result as LocalDataReady;
        final foreignKeys = await ready.database
            .customSelect('PRAGMA foreign_keys')
            .getSingle();
        expect(foreignKeys.read<int>('foreign_keys'), 1);
      },
    );
  });
}
