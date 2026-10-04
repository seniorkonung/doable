import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Пояс с переходами на летнее и зимнее время, по правилам которого выбраны
/// недели перехода в `daily_choice_calendar_boundaries_test.dart`.
const _timeZone = 'America/New_York';

/// Ограничение дочернего прогона вместе с компиляцией его тестов.
const _childTimeLimit = Duration(minutes: 5);

/// Время на завершение дочернего прогона после превышения ограничения.
const _childStopTimeLimit = Duration(seconds: 30);

void main() {
  test(
    'календарные даты сохраняются в часовом поясе $_timeZone с переходом на летнее время',
    () async {
      final workerPath = File.fromUri(
        Directory.current.uri.resolve(
          'test/daily_choice/presentation/catalog/'
          'daily_choice_calendar_time_zone_worker.dart',
        ),
      ).path;
      // Часовой пояс процесса задаётся при запуске, поэтому проверки дат
      // выполняет отдельный процесс `flutter test`.
      final process = await Process.start(
        _findFlutterExecutable(),
        ['test', '--no-pub', '--reporter', 'expanded', workerPath],
        workingDirectory: Directory.current.path,
        environment: {'TZ': _timeZone},
      );
      final output = StringBuffer();
      final outputDone = Future.wait([
        process.stdout.transform(utf8.decoder).forEach(output.write),
        process.stderr.transform(utf8.decoder).forEach(output.write),
      ]);

      final int exitCode;
      try {
        exitCode = await process.exitCode.timeout(_childTimeLimit);
      } on TimeoutException {
        await _stop(process);
        await outputDone.timeout(_childStopTimeLimit, onTimeout: () => []);
        fail(
          'Дочерний прогон в $_timeZone не завершился за $_childTimeLimit:\n'
          '$output',
        );
      }
      await outputDone;

      expect(
        exitCode,
        0,
        reason: 'Дочерний прогон в $_timeZone завершился ошибкой:\n$output',
      );
      expect(
        output.toString(),
        contains('All tests passed!'),
        reason: 'Дочерний прогон в $_timeZone не выполнил проверки:\n$output',
      );
    },
    timeout: Timeout(_childTimeLimit + _childStopTimeLimit * 3),
  );
}

/// Останавливает дочерний `flutter test`: сначала даёт ему завершить
/// собственные процессы тестов, затем завершает принудительно.
Future<void> _stop(Process process) async {
  process.kill();
  await process.exitCode.timeout(
    _childStopTimeLimit,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return process.exitCode;
    },
  );
}

String _findFlutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Flutter SDK не найден.');
    }
    directory = parent;
  }
}
