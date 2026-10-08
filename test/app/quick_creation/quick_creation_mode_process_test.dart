import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/app/quick_creation/file_quick_creation_mode_store.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import 'controlled_mode_io.dart';

const _initial = QuickCreationMode.dailyChoiceFromIntention;
const _a = QuickCreationMode.relation;
const _b = QuickCreationMode.dailyChoiceFromAction;

void main() {
  late Directory directory;
  late File modeFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('doable_process_режимы ');
    modeFile = File.fromUri(
      directory.uri.resolve('settings/quick_creation_mode'),
    );
    expect(
      await FileQuickCreationModeStore(
        localDataDirectory: directory,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      ).save(_initial),
      isA<QuickCreationModeSaved>(),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  for (final step in [ModeWriteStep.write, ModeWriteStep.rename]) {
    for (final outcomes in ['ss', 'fs', 'sf', 'ff', 'ffs', 'sss']) {
      test('${step.label}: отдельный процесс восстанавливает последний успех '
          '$outcomes без объединения выборов', () async {
        final modes = [_a, _b, if (outcomes.length == 3) _a];
        final worker = await _Worker.start(directory, [
          step.name,
          outcomes,
          modes.map((mode) => mode.storageKey).join(','),
          if (outcomes == 'ffs') 'throw',
        ]);
        addTearDown(worker.stop);
        final temporaryPaths = <String>{};
        final committed = <String>[];
        var expected = _initial;

        for (var i = 0; i < modes.length; i++) {
          final held = await worker.next('held');
          expect(held['pid'], worker.process.pid);
          expect(held['pid'], isNot(pid));
          expect(held['held'], i);
          expect(held['started'], i + 1);
          expect(temporaryPaths.add(held['temporaryPath'] as String), isTrue);
          expect(await modeFile.readAsString(), expected.storageKey);

          worker.process.stdin.writeln('release');
          final finished = await worker.next('finished');
          expect(finished['finished'], i);
          final succeeds = outcomes[i] == 's';
          expect(finished['saved'], succeeds);
          if (succeeds) {
            expected = modes[i];
            committed.add(expected.storageKey);
          }
          expect(finished['committed'], committed);
          expect(await modeFile.readAsString(), expected.storageKey);
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
        await _expectNewProcess(directory, expected);
      });
    }

    test('${step.label}: завершение процесса оставляет только заменённый '
        'файл, незавершённая и ожидающая записи теряются', () async {
      final worker = await _Worker.start(directory, [
        step.name,
        'sss',
        [_a, _b, _initial].map((mode) => mode.storageKey).join(','),
      ]);
      addTearDown(worker.stop);
      await worker.next('held');
      worker.process.stdin.writeln('release');
      expect((await worker.next('finished'))['saved'], isTrue);
      final held = await worker.next('held');
      expect(held['held'], 1);
      expect(held['started'], 2);
      final temporary = File(held['temporaryPath'] as String);
      expect(await temporary.exists(), isTrue);
      expect(await modeFile.readAsString(), _a.storageKey);

      expect(worker.process.kill(ProcessSignal.sigkill), isTrue);
      await worker.finish(killed: true);

      expect(await temporary.exists(), isTrue);
      expect(worker.diagnostics, isEmpty);
      await _expectNewProcess(directory, _a);
      expect(await modeFile.readAsString(), _a.storageKey);
    });
  }
}

Future<void> _expectNewProcess(
  Directory directory,
  QuickCreationMode mode,
) async {
  final reader = await _Worker.start(directory, ['read']);
  addTearDown(reader.stop);
  final restored = await reader.next('mode');
  expect(restored['mode'], mode.storageKey);
  expect(restored['pid'], reader.process.pid);
  expect(restored['pid'], isNot(pid));
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
