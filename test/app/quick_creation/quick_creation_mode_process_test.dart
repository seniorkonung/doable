import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controlled_mode_io.dart';

/// Прежний ключ неизвестен режимам, поэтому отличает нетронутый файл от записи.
const _initial =
    'daily'
    '-choice';
const _saved = QuickCreationMode.intention;

void main() {
  late Directory directory;
  late File modeFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('doable_process_режимы ');
    modeFile = File.fromUri(
      directory.uri.resolve('settings/quick_creation_mode'),
    );
    await modeFile.parent.create();
    await modeFile.writeAsString(_initial);
  });
  tearDown(() => directory.delete(recursive: true));

  // Очередь и точки отказа подробно проверяет тест хранилища в процессе
  // теста; здесь нужны лишь отказ после успеха и отказы с падающим получателем
  // диагностики, по одному на каждую точку записи.
  for (final (step, outcomes) in [
    (ModeWriteStep.write, 'sf'),
    (ModeWriteStep.rename, 'ffs'),
  ]) {
    test('${step.label}: отдельный процесс восстанавливает последний успех '
        '$outcomes', () async {
      final modes = List.filled(outcomes.length, _saved);
      final worker = await _Worker.start(directory, [
        step.name,
        outcomes,
        modes.map((mode) => mode.storageKey).join(','),
        if (outcomes == 'ffs') 'throw',
      ]);
      addTearDown(worker.stop);
      var expected = _initial;

      for (var i = 0; i < modes.length; i++) {
        await worker.next('held');
        expect(await modeFile.readAsString(), expected);

        worker.process.stdin.writeln('release');
        final finished = await worker.next('finished');
        final succeeds = outcomes[i] == 's';
        expect(finished['saved'], succeeds);
        if (succeeds) expected = _saved.storageKey;
        expect(await modeFile.readAsString(), expected);
      }
      await worker.finish();
      expect(worker.diagnostics, [
        for (final outcome in outcomes.split(''))
          if (outcome == 'f')
            {
              'operation': 'quickCreationMode',
              'stage': 'write',
              'outcome': 'failed',
              'failureCode': 'unavailable',
            },
      ]);
      expect(await modeFile.parent.list().length, 1);
      await _expectNewProcess(directory);
    });
  }

  test('переименование: завершение процесса оставляет только заменённый '
      'файл, незавершённая и ожидающая записи теряются', () async {
    final worker = await _Worker.start(directory, [
      ModeWriteStep.rename.name,
      'sss',
      List.filled(3, _saved.storageKey).join(','),
    ]);
    addTearDown(worker.stop);
    await worker.next('held');
    worker.process.stdin.writeln('release');
    expect((await worker.next('finished'))['saved'], isTrue);
    await worker.next('held');
    expect(await modeFile.readAsString(), _saved.storageKey);

    expect(worker.process.kill(ProcessSignal.sigkill), isTrue);
    await worker.finish(killed: true);

    expect(worker.diagnostics, isEmpty);
    await _expectNewProcess(directory);
    expect(await modeFile.readAsString(), _saved.storageKey);
  });
}

Future<void> _expectNewProcess(Directory directory) async {
  final reader = await _Worker.start(directory, ['read']);
  addTearDown(reader.stop);
  final restored = await reader.next('mode');
  expect(restored['mode'], _saved.storageKey);
  await reader.finish();
  expect(reader.diagnostics, isEmpty);
}

/// Прямой Dart-процесс не разделяет контейнер или IOOverrides родителя.
final class _Worker {
  _Worker(this.process) {
    messages = StreamIterator(
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) => jsonDecode(line) as Map<String, dynamic>),
    );
    errorsDone = process.stderr
        .transform(utf8.decoder)
        .listen(errors.write)
        .asFuture<void>();
  }

  final Process process;
  final errors = StringBuffer();
  final diagnostics = <Map<String, dynamic>>[];
  late final StreamIterator<Map<String, dynamic>> messages;
  late final Future<void> errorsDone;
  bool finished = false;

  static Future<_Worker> start(
    Directory directory,
    List<String> arguments,
  ) async {
    final process = await Process.start(_dartExecutable(), [
      '--packages=.dart_tool/package_config.json',
      'test/support/quick_creation_mode_process_worker.dart',
      directory.path,
      ...arguments,
    ], workingDirectory: Directory.current.path);
    return _Worker(process);
  }

  Future<Map<String, dynamic>> next(String key) async {
    while (await messages.moveNext().timeout(const Duration(seconds: 15))) {
      final message = messages.current;
      if (message['diagnostic'] case final Map<String, dynamic> event) {
        expect(event.remove('durationMicros'), isA<int>());
        diagnostics.add(event);
      } else {
        expect(message.containsKey(key), isTrue, reason: '$message');
        return message;
      }
    }
    throw StateError('Процесс завершился до сообщения $key: $errors');
  }

  Future<void> finish({bool killed = false}) async {
    await process.stdin.close();
    final code = await process.exitCode.timeout(const Duration(seconds: 15));
    await errorsDone;
    finished = true;
    await messages.cancel();
    expect(code, killed ? isNot(0) : 0, reason: '$errors');
    expect(errors.toString(), isEmpty);
  }

  Future<void> stop() async {
    if (!finished) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await messages.cancel();
    }
  }
}

String _dartExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final executable = File.fromUri(
      directory.uri.resolve(
        'bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
      ),
    );
    if (executable.existsSync()) return executable.path;
    final parent = directory.parent;
    if (parent.path == directory.path) throw StateError('Dart SDK не найден.');
    directory = parent;
  }
}
