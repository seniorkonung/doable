import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum ModeWriteStep {
  prepare('подготовка'),
  createTemporary('создание временного файла'),
  write('запись'),
  rename('переименование'),
  cleanup('очистка');

  const ModeWriteStep(this.label);
  final String label;
}

/// Задерживает отдельную стадию, сохраняя настоящие файловые операции.
final class ModeWriteAttempt {
  ModeWriteAttempt({this.holdAt, this.failAt, this.failCleanup = false});

  final ModeWriteStep? holdAt;
  final ModeWriteStep? failAt;
  final bool failCleanup;
  final started = Completer<void>();
  final held = Completer<void>();
  final release = Completer<void>();
  String? temporaryPath;
  String? key;
  bool? flushed;
  bool? exclusive;

  Future<void> step(ModeWriteStep step) async {
    if (step == holdAt) {
      held.complete();
      await release.future;
    }
    if (step == failAt || (step == ModeWriteStep.cleanup && failCleanup)) {
      throw const FileSystemException('Секретный путь и содержимое');
    }
  }
}

/// Подменяет только IO-фабрики внутри зоны, без тестовых зависимостей адаптера.
/// https://api.dart.dev/dart-io/IOOverrides/runZoned.html
final class ControlledModeIo {
  ControlledModeIo(this.modeFile, this.plan)
    : _settingsUri = modeFile.parent.uri;

  final File modeFile;
  final List<ModeWriteAttempt> plan;
  final Uri _settingsUri;
  final startedAttempts = <ModeWriteAttempt>[];
  final committedKeys = <String>[];
  Object? readError;

  Future<T> run<T>(Future<T> Function() body) {
    final realIo = Zone.current;
    return IOOverrides.runZoned(
      body,
      createDirectory: (path) {
        final directory = realIo.run(() => Directory(path));
        if (directory.uri != _settingsUri) return directory;
        return _SettingsDirectory(directory, this);
      },
      createFile: (path) {
        final file = realIo.run(() => File(path));
        if (path == modeFile.path) return _ModeFile(file, this, null);
        if (file.parent.uri != _settingsUri) return file;
        if (plan.any((attempt) => attempt.temporaryPath == path)) return file;
        final attempt = startedAttempts.last;
        attempt.temporaryPath = path;
        return _ModeFile(file, this, attempt);
      },
    );
  }

  ModeWriteAttempt begin() {
    final attempt = plan[startedAttempts.length];
    startedAttempts.add(attempt);
    attempt.started.complete();
    return attempt;
  }
}

final class _SettingsDirectory implements Directory {
  _SettingsDirectory(this.real, this.io);

  final Directory real;
  final ControlledModeIo io;

  @override
  String get path => real.path;

  @override
  Uri get uri => real.uri;

  @override
  Future<Directory> create({bool recursive = false}) async {
    await io.begin().step(ModeWriteStep.prepare);
    await real.create(recursive: recursive);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ModeFile implements File {
  _ModeFile(this.real, this.io, this.attempt);

  final File real;
  final ControlledModeIo io;
  final ModeWriteAttempt? attempt;

  @override
  String get path => real.path;

  @override
  Directory get parent => real.parent;

  @override
  Future<Uint8List> readAsBytes() async {
    final error = io.readError;
    if (error != null) throw error;
    return real.readAsBytes();
  }

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    attempt!.exclusive = exclusive;
    await attempt!.step(ModeWriteStep.createTemporary);
    await real.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    final writing = attempt!;
    writing.key = contents;
    writing.flushed = flush;
    // Даже частичная запись временного файла не меняет основной.
    await real.writeAsString('Незавершённая запись');
    await writing.step(ModeWriteStep.write);
    await real.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    return this;
  }

  @override
  Future<File> rename(String newPath) async {
    await attempt!.step(ModeWriteStep.rename);
    final renamed = await real.rename(newPath);
    io.committedKeys.add(await io.modeFile.readAsString());
    return renamed;
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await attempt!.step(ModeWriteStep.cleanup);
    return real.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
