import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/data_transfer/application/graph_composition.dart';
import 'package:doable/src/data_transfer/application/graph_import.dart';
import 'package:doable/src/data_transfer/application/graph_import_provider.dart';
import 'package:doable/src/data_transfer/application/graph_replacement.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/failing_snapshot_temporary_files.dart';
import '../support/file_document_access.dart';
import '../support/graph_import_files.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/encoded_diagnostics_log.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/stalling_replacement_snapshot_reads.dart';

void main() {
  final reference = referenceGraphFileLines();

  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late Directory temporary;
  late FileDocumentAccess documents;
  late GraphLogCompaction compaction;
  late ProviderContainer container;
  late EncodedDiagnosticsLog diagnostics;
  late _ControlledComposition composition;
  var replacementSnapshotRunner = runGraphReplacementSnapshotWriteInIsolate;
  var chosenFiles = 0;

  GraphImport graphImport({DocumentAccess? access}) => GraphImport(
    documents: access ?? documents,
    compaction: compaction,
    replacement: repository,
    temporaryDirectory: Future.value(temporary),
    snapshotFiles: Future.value(),
    diagnosticsSink: diagnostics,
  );

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    database = await harness.openReadyDatabase();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime(2026, 10, 19, 9),
      InMemoryDiagnosticsSink(),
    );
    snapshots = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('graph_snapshots/'),
    );
    temporary = Directory.fromUri(
      harness.temporaryDirectory.uri.resolve('tmp/'),
    );
    documents = FileDocumentAccess(
      await Directory.fromUri(
        harness.temporaryDirectory.uri.resolve('documents/'),
      ).create(),
    );
    replacementSnapshotRunner = runGraphReplacementSnapshotWriteInIsolate;
    compaction = GraphLogCompaction(
      log: repository,
      directory: snapshots,
      clock: () => DateTime(2026, 10, 19, 9),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      replacementSnapshotRunner: (write) => replacementSnapshotRunner(write),
    );
    addTearDown(compaction.shutdown);
    diagnostics = EncodedDiagnosticsLog();
    composition = _ControlledComposition(repository);
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        graphImportControllerProvider.overrideWith(
          () => GraphImportController(graphImport(), composition),
        ),
      ],
    );
    addTearDown(() async {
      await container.read(graphCommandCoordinatorProvider.notifier).shutdown();
      container.dispose();
    });
  });

  /// Человек выбирает в системном диалоге документ с байтами [bytes].
  File choose(List<int> bytes) {
    final document = File.fromUri(
      harness.temporaryDirectory.uri.resolve('chosen-${++chosenFiles}.gz'),
    )..writeAsBytesSync(bytes);
    documents.openingDialog = () async => documents.chosen(document);
    return document;
  }

  Future<GraphImportFileReading> readChosen({
    DocumentAccess? access,
    void Function()? onDocumentChosen,
    GraphImportReadingCancellation? cancellation,
  }) => graphImport(access: access).readChosenFile(
    onDocumentChosen: onDocumentChosen ?? () {},
    cancellation: cancellation ?? GraphImportReadingCancellation(),
  );

  Future<GraphImportFile> readFile(List<int> bytes) async {
    choose(bytes);
    return switch (await readChosen()) {
      GraphImportFileRead(:final file) => file,
      final reading => throw TestFailure('Файл не прочитан: $reading'),
    };
  }

  /// Импортирует прочитанный файл [file] операцией, принятой координатором.
  Future<GraphImportOutcome> importFile(
    GraphImportFile file, {
    void Function(GraphReplacementProgress progress)? onProgress,
    GraphReplacementCancellation? cancellation,
  }) {
    final start = container
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptImport(
          (exclusive) => graphImport().importFile(
            file,
            exclusive,
            onProgress: onProgress ?? (_) {},
            cancellation: cancellation ?? GraphReplacementCancellation(),
          ),
        );
    return (start as GraphImportAccepted).future;
  }

  /// Где и с какой категорией отказа импорт отклонил выбранный документ с
  /// байтами [bytes]; `null` — файл не отклонён.
  Future<(_Detection, GraphImportFailure)?> rejectionOf(List<int> bytes) async {
    choose(bytes);
    switch (await readChosen()) {
      case GraphImportFileReadingFailed(:final failure):
        return (_Detection.header, failure);
      case GraphImportFileReadingCancelled():
        return null;
      case GraphImportFileRead(:final file):
        final phases = <GraphReplacementPhase>{};
        final outcome = await importFile(
          file,
          onProgress: (progress) => phases.add(progress.phase),
        );
        return switch (outcome) {
          GraphImportFailed(:final failure) => (
            phases.contains(GraphReplacementPhase.replacement)
                ? _Detection.replacement
                : _Detection.snapshotWrite,
            failure,
          ),
          GraphImported() || GraphImportCancelled() => null,
        };
    }
  }

  Future<T> confirm<T extends GraphCommandOutcome>(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await repository.execute(command);
    final confirmed =
        (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
            as ConfirmedGraphResult;
    return confirmed.value as T;
  }

  Future<Tag> createTag(String name) async =>
      (await confirm<TagCreated>(CreateTag(TagName.fromInput(name)))).tag;

  /// Непустой граф: тег и намерение с этим тегом.
  Future<void> createGraph() async {
    final garden = await createTag('Сад');
    await confirm(
      CreateIntention.withInitialState(
        title: 'Полить грядки',
        description: null,
        readiness: IntentionReadiness.notReady,
        tagIds: {garden.id},
      ),
    );
  }

  Future<List<GraphBackupEntry>> storedBackups() async =>
      switch (await repository.watchBackups().first) {
        GraphBackupsReadSucceeded(:final backups) => backups,
        GraphBackupsReadFailed() => throw TestFailure('Копии не прочитаны.'),
      };

  Future<List<String>> graphState() async =>
      _lines(await referenceGraphRecords(database));

  /// Состояние графа на позиции [position], собранное из снимков и лога.
  Future<List<String>> stateAt(int position) async {
    final snapshot = await compaction.readHistory(
      (history) async => compaction.writeReplacementSnapshot(
        await history.selectStateAt(position),
        onProgress: (_) {},
        cancelled: Completer<void>().future,
      ),
    );
    try {
      return _lines(await snapshot.readRecords().toList());
    } finally {
      await snapshot.delete();
    }
  }

  Future<List<List<Object?>>> rows(String query) async => [
    for (final row in await database.customSelect(query).get())
      row.data.values.toList(),
  ];

  /// Граф, копии, лог, реестр и каталог снимков.
  Future<List<Object>> storedState() async => [
    await graphState(),
    await rows('SELECT * FROM graph_backups ORDER BY id'),
    await rows(
      'SELECT position, kind, snapshot_id FROM graph_log_packages '
      'ORDER BY position',
    ),
    await rows('SELECT * FROM graph_snapshots ORDER BY id'),
    await _fileNamesIn(snapshots),
  ];

  test('сценарий «Сохранённое состояние импортируется как есть»: эталонный '
      'файл версии 1 с дневным выбором, путь которого проходит через '
      'архивированную связь к намерению без готовности к действию, заменяет '
      'непустой граф графом, выгрузка которого совпадает с записями файла, а '
      'прежнее состояние становится копией перед заменой', () async {
    await createGraph();
    final before = await graphState();

    final file = await readFile(graphExportFileOf(reference));
    expect(
      file.header.writtenAt,
      DateTime.utc(2026, 10, 3, 18, 42, 7, 654, 321),
    );
    expect(_countsOf(file.header.counts), [2, 4, 3, 3, 2]);
    expect(await importFile(file), isA<GraphImported>());

    expect(await graphState(), reference.skip(1));
    final [backup] = await storedBackups();
    expect(backup.kind, GraphBackupKind.beforeReplacement);
    expect(await stateAt(backup.position), before);
    expect(await _fileNamesIn(temporary), isEmpty);
  });

  test('импорт в пустой граф не добавляет копии перед заменой', () async {
    final file = await readFile(graphExportFileOf(reference));

    expect(await importFile(file), isA<GraphImported>());

    expect(await graphState(), reference.skip(1));
    expect(await storedBackups(), isEmpty);
  });

  test('успешный импорт диагностируется успехом без пользовательских '
      'данных', () async {
    await createGraph();
    final file = await readFile(graphExportFileOf(reference));

    expect(await importFile(file), isA<GraphImported>());

    expect(diagnostics.events, [
      {'operation': 'graphImport', 'outcome': 'succeeded'},
    ]);
  });

  test('сценарий «Отклонённый файл диагностируется без содержимого»: '
      'неподходящий файл, в том числе с двумя тегами одного названия, '
      'отклоняется там, где его можно обнаружить, своим исходом, '
      'диагностируется этапом проверки данных и своей категорией без '
      'пользовательских данных и не меняет граф, копии, лог, реестр и каталог '
      'снимков и временный каталог', () async {
    await createGraph();
    final before = await storedState();
    List<int> edited(int line, void Function(Map<String, Object?> json) edit) =>
        graphExportFileOf(withEditedLine(reference, line, edit));
    // Строки эталона: 1–2 — теги, 3–6 — намерения, 7–9 — назначения тегов,
    // 10–12 — долговременные связи, 13–14 — дневные выборы.
    final cases = <String, (List<int>, (_Detection, GraphImportFailure))>{
      'фотография': (
        photoFile(),
        (_Detection.header, GraphImportFailure.invalidFile),
      ),
      'файл более новой версии': (
        newerFormatVersionFile(),
        (_Detection.header, GraphImportFailure.newerFormatVersion),
      ),
      'файл, обрезанный посередине': (
        truncatedGraphExportFile(),
        (_Detection.snapshotWrite, GraphImportFailure.invalidFile),
      ),
      'недопустимое значение поля': (
        edited(10, (relation) => relation['priority'] = 'P5'),
        (_Detection.snapshotWrite, GraphImportFailure.invalidFile),
      ),
      'намерения не по каноническому порядку': (
        graphExportFileOf([
          ...reference.take(3),
          reference[4],
          reference[3],
          ...reference.skip(5),
        ]),
        (_Detection.snapshotWrite, GraphImportFailure.invalidFile),
      ),
      'ссылка на отсутствующую сущность': (
        edited(
          7,
          (assignment) => assignment['intentionId'] =
              '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f99',
        ),
        (_Detection.replacement, GraphImportFailure.invalidFile),
      ),
      'повторённый идентификатор': (
        edited(2, (tag) => tag['id'] = jsonDecode(reference[1])['id']),
        (_Detection.replacement, GraphImportFailure.invalidFile),
      ),
      'совпадение названий тегов': (
        edited(2, (tag) => tag['name'] = 'Дом'),
        (_Detection.replacement, GraphImportFailure.invalidFile),
      ),
      'совпадение направленных пар связей': (
        edited(
          11,
          (relation) => relation['relatedIntentionId'] =
              '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f12',
        ),
        (_Detection.replacement, GraphImportFailure.invalidFile),
      ),
      'самосвязь': (
        edited(
          10,
          (relation) =>
              relation['relatedIntentionId'] = relation['sourceIntentionId'],
        ),
        (_Detection.replacement, GraphImportFailure.invalidFile),
      ),
      'активная связь с архивированным участником': (
        edited(12, (relation) => relation['archived'] = false),
        (_Detection.replacement, GraphImportFailure.invalidFile),
      ),
      'путь, который не доходит до выбранного намерения': (
        edited(
          14,
          (choice) => choice['selectedIntentionId'] =
              '1f6c7a2e-3b4d-4e5f-9a60-0b1c2d3e4f12',
        ),
        (_Detection.replacement, GraphImportFailure.invalidFile),
      ),
    };

    for (final MapEntry(key: reason, value: (bytes, rejection))
        in cases.entries) {
      diagnostics = EncodedDiagnosticsLog();

      expect(await rejectionOf(bytes), rejection, reason: reason);
      expect(diagnostics.events, [
        _importFailed('dataValidation', rejection.$2),
      ], reason: reason);
      expect(await storedState(), before, reason: reason);
      expect(await _fileNamesIn(temporary), isEmpty, reason: reason);
    }
  });

  test('отмена диалога, диалог, который не открылся, и отказы копирования '
      'документа дают свои исходы, отказы диагностируются этапом чтения '
      'документа, а отмена события не даёт, и не остаётся временных '
      'файлов', () async {
    final document = choose(graphExportFileOf(reference));
    final cases =
        <String, (DocumentOpening, DocumentCopy?, GraphImportFailure?)>{
          'отмена диалога': (const DocumentOpeningCancelled(), null, null),
          'диалог не открылся': (
            const DocumentOpeningFailed(),
            null,
            GraphImportFailure.unknown,
          ),
          'документ не прочитан': (
            documents.chosen(document),
            const DocumentNotRead(),
            GraphImportFailure.documentUnreadable,
          ),
          'копии не хватило места': (
            documents.chosen(document),
            const DocumentCopyStorageFull(),
            GraphImportFailure.storageFull,
          ),
          'копия не записана': (
            documents.chosen(document),
            const DocumentCopyFailed(),
            GraphImportFailure.unknown,
          ),
        };

    for (final MapEntry(key: reason, value: (dialog, copyFailure, failure))
        in cases.entries) {
      documents
        ..openingDialog = (() async => dialog)
        ..copyFailure = copyFailure;
      diagnostics = EncodedDiagnosticsLog();

      final reading = await readChosen();

      if (failure == null) {
        expect(reading, isA<GraphImportFileReadingCancelled>(), reason: reason);
        expect(diagnostics.events, isEmpty, reason: reason);
      } else {
        expect(reading, _readingFailed(failure), reason: reason);
        expect(diagnostics.events, [
          _importFailed('documentRead', failure),
        ], reason: reason);
      }
      expect(await _fileNamesIn(temporary), isEmpty, reason: reason);
    }
  });

  for (final (name, bytes, failure) in [
    ('фотография', photoFile(), GraphImportFailure.invalidFile),
    (
      'чужой gzip',
      graphExportFileOf(['{"format":"another-app","version":1}']),
      GraphImportFailure.invalidFile,
    ),
    (
      'более новая версия',
      newerFormatVersionFile(),
      GraphImportFailure.newerFormatVersion,
    ),
    (
      'повреждённая дата заголовка',
      graphExportFileOf(
        withEditedLine(reference, 0, (header) {
          header['writtenAt'] = 'не дата';
        }),
      ),
      GraphImportFailure.invalidFile,
    ),
    (
      'повреждённые количества заголовка',
      graphExportFileOf(
        withEditedLine(reference, 0, (header) {
          header['counts'] = {'tags': -1};
        }),
      ),
      GraphImportFailure.invalidFile,
    ),
    (
      'заголовок длиннее 4 КиБ',
      graphExportFileOf([reference.first.padRight(4 * 1024 + 1)]),
      GraphImportFailure.invalidFile,
    ),
  ]) {
    test('$name отклоняется до копирования и не подменяется нехваткой '
        'места', () async {
      final access = _PrefixDocumentAccess(bytes)
        ..copyFailure = const DocumentCopyStorageFull();
      final reading = readChosen(access: access);
      reading.ignore();

      expect(
        await Future.any([
          reading,
          access.remainderRequested.future.then<GraphImportFileReading>(
            (_) => throw TestFailure('Импорт запросил недоступный остаток.'),
          ),
        ]),
        _readingFailed(failure),
      );
      expect(access.copies, 0);
      expect(access.prefixClosed, isTrue);
      expect(access.finished, isTrue);
      expect(await _fileNamesIn(temporary), isEmpty);
    });
  }

  for (final (name, header) in [
    ('опубликованный эталон', reference.first),
    ('заголовок на пределе', reference.first.padRight(4 * 1024)),
  ]) {
    test('$name разрешает копирование без ожидания остатка и сохраняет '
        'проверенный заголовок в полностью записанном файле', () async {
      final bytes = graphExportFileOf([header, ...reference.skip(1)]);
      final access = _PrefixDocumentAccess(bytes);
      final reading = readChosen(access: access);
      reading.ignore();

      final result = await Future.any([
        reading,
        access.remainderRequested.future.then<GraphImportFileReading>(
          (_) => throw TestFailure('Проверка заголовка запросила остаток.'),
        ),
      ]);

      expect(result, isA<GraphImportFileRead>());
      final file = (result as GraphImportFileRead).file;
      expect(_countsOf(file.header.counts), [2, 4, 3, 3, 2]);
      expect(
        file.header.writtenAt,
        DateTime.utc(2026, 10, 3, 18, 42, 7, 654, 321),
      );
      expect(access.copies, 1);
      expect(access.prefixClosed, isTrue);
      expect(access.finished, isTrue);
      await file.discard();
    });
  }

  test('отсутствие заголовка в 64 КиБ сжатого начала не разрешает '
      'копирование остатка', () async {
    // Неоконченное имя в обрамлении gzip не даёт распакованных строк.
    choose([
      0x1f,
      0x8b,
      8,
      8,
      0,
      0,
      0,
      0,
      0,
      0,
      ...List.filled(documentPrefixByteLimit, 0x61),
    ]);
    var chunks = 0;
    documents
      ..afterPrefixAnswer = () {
        chunks++;
      }
      ..copyFailure = const DocumentCopyStorageFull();

    expect(await readChosen(), _readingFailed(GraphImportFailure.invalidFile));
    expect(chunks * documentPrefixChunkSize, documentPrefixByteLimit);
    expect(documents.copies, isEmpty);
    expect(await _fileNamesIn(temporary), isEmpty);
  });

  test('ошибка поставщика до получения заголовка остаётся отказом чтения '
      'документа без копирования', () async {
    final access = _PrefixDocumentAccess([])
      ..prefixFailure = DocumentReadFailure.unreadable;

    expect(
      await readChosen(access: access),
      _readingFailed(GraphImportFailure.documentUnreadable),
    );
    expect(access.copies, 0);
    expect(access.finished, isTrue);
    expect(diagnostics.events, [
      _importFailed('documentRead', GraphImportFailure.documentUnreadable),
    ]);
  });

  test('принятая отмена при чтении начала сохраняет приоритет над отказом '
      'поставщика и не даёт диагностики', () async {
    final cancellation = GraphImportReadingCancellation();
    final access = _PrefixDocumentAccess([])..waitForCancellation = true;
    final reading = readChosen(access: access, cancellation: cancellation);
    await access.prefixStarted.future;

    cancellation.request();

    expect(await reading, isA<GraphImportFileReadingCancelled>());
    expect(access.copies, 0);
    expect(access.finished, isTrue);
    expect(diagnostics.events, isEmpty);
    expect(await _fileNamesIn(temporary), isEmpty);
  });

  test('принятая отмена между проверкой заголовка и разрешением копирования '
      'завершает сессию без копии и диагностики', () async {
    final cancellation = GraphImportReadingCancellation();
    final access = _PrefixDocumentAccess(graphExportFileOf(reference))
      ..onPrefixClosed = cancellation.request;

    expect(
      await readChosen(access: access, cancellation: cancellation),
      isA<GraphImportFileReadingCancelled>(),
    );
    expect(access.copies, 0);
    expect(access.finished, isTrue);
    expect(diagnostics.events, isEmpty);
    expect(await _fileNamesIn(temporary), isEmpty);
  });

  test('отказ от прочитанного файла удаляет его временную копию и события '
      'диагностики не даёт', () async {
    final file = await readFile(graphExportFileOf(reference));

    await file.discard();

    expect(await _fileNamesIn(temporary), isEmpty);
    expect(diagnostics.events, isEmpty);
  });

  group('перезапуск изолята во время копирования документа', () {
    for (final lateCopy in _LateCopy.values) {
      test(
        switch (lateCopy) {
          _LateCopy.cancelledDeletion =>
            'позднее удаление отменённой копии сохраняет заголовок и записи '
                'следующего выбранного документа',
          _LateCopy.detachedWrite =>
            'поздняя запись копии без движка сохраняет заголовок и записи '
                'следующего выбранного документа',
        },
        () async {
          final firstLines = [
            jsonEncode({
              'format': 'doable-graph',
              'version': 1,
              'writtenAt': '2026-10-03T18:42:07.654321Z',
              'counts': {
                'tags': 1,
                'intentions': 0,
                'tagAssignments': 0,
                'longTermRelations': 0,
                'dailyChoices': 0,
              },
            }),
            reference[1],
          ];
          final secondLines = withEditedLine(
            withEditedLine(firstLines, 0, (header) {
              header['writtenAt'] = '2026-10-19T09:00:00.000000Z';
            }),
            1,
            (tag) => tag['name'] = 'Сад',
          );
          final firstDocument = choose(graphExportFileOf(firstLines));
          final first = await _startImportReadInNewIsolate(
            temporary,
            firstDocument,
          );
          // Копирование живёт за пределами изолята, как поток JVM. Его файл
          // уже появился, но поставщик ещё не закончил работу с документом.
          await firstDocument.copy(first.copy.path);
          switch (lateCopy) {
            case _LateCopy.cancelledDeletion:
              first.answer.send(const DocumentCopyCancelled());
              expect(
                await first.reading,
                isA<GraphImportFileReadingCancelled>(),
              );
            case _LateCopy.detachedWrite:
              final stopped = expectLater(
                first.reading,
                throwsA(isA<RemoteError>()),
              );
              first.isolate.kill(priority: Isolate.immediate);
              await stopped;
          }

          // Новый запуск очищает каталог после завершения прежнего изолята.
          await temporary.delete(recursive: true);
          await temporary.create();
          final secondDocument = choose(graphExportFileOf(secondLines));
          final second = await _startImportReadInNewIsolate(
            temporary,
            secondDocument,
          );
          await secondDocument.copy(second.copy.path);

          // Ответ прежнего поставщика приходит, когда новая копия уже есть,
          // но её заголовок и записи ещё не прочитаны новым импортом.
          switch (lateCopy) {
            case _LateCopy.cancelledDeletion:
              if (await first.copy.exists()) await first.copy.delete();
            case _LateCopy.detachedWrite:
              await firstDocument.copy(first.copy.path);
          }
          second.answer.send(const DocumentCopied());
          final reading = await second.reading;
          expect(reading, isA<GraphImportFileRead>());
          final file = (reading as GraphImportFileRead).file;
          expect(file.header.writtenAt, DateTime.utc(2026, 10, 19, 9));
          expect(_countsOf(file.header.counts), [1, 0, 0, 0, 0]);
          expect(await importFile(file), isA<GraphImported>());
          expect(await graphState(), secondLines.skip(1));
        },
      );
    }
  });

  group('нехватка места', () {
    test('при записи снимка замены даёт свой исход, диагностируемый этапом '
        'записи снимка замены, и ничего не меняет', () async {
      await createGraph();
      final before = await storedState();
      final file = await readFile(graphExportFileOf(reference));
      replacementSnapshotRunner =
          writeGraphReplacementSnapshotFailingOnTemporaryFiles;

      expect(
        await importFile(file),
        isA<GraphImportFailed>().having(
          (failed) => failed.failure,
          'категория',
          GraphImportFailure.storageFull,
        ),
      );

      expect(diagnostics.events, [
        _importFailed('snapshotWrite', GraphImportFailure.storageFull),
      ]);
      expect(await storedState(), before);
      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('при замене графа, когда база не может вырасти, даёт свой исход, '
        'диагностируемый этапом замены, и ничего не меняет', () async {
      // Длинные описания занимают страницы переполнения, которых в базе
      // после VACUUM нет.
      var lines = reference;
      for (var line = 3; line <= 6; line++) {
        lines = withEditedLine(lines, line, (intention) {
          intention['description'] = 'ж' * 4000;
        });
      }
      await createTag('Дом');
      final file = await readFile(graphExportFileOf(lines));
      await database.customStatement('VACUUM');
      final pageCount = await database
          .customSelect('PRAGMA page_count')
          .getSingle();
      await database.customStatement(
        'PRAGMA max_page_count = ${pageCount.read<int>('page_count')}',
      );
      final before = await storedState();

      expect(
        await importFile(file),
        isA<GraphImportFailed>().having(
          (failed) => failed.failure,
          'категория',
          GraphImportFailure.storageFull,
        ),
      );

      expect(diagnostics.events, [
        _importFailed('replacement', GraphImportFailure.storageFull),
      ]);
      expect(await storedState(), before);
      expect(await _fileNamesIn(temporary), isEmpty);
    });
  });

  group('отмена', () {
    test('после отправленного отказа копирования, до его обработки, '
        'завершает чтение без отказа и события диагностики', () async {
      choose(graphExportFileOf(reference));
      final cancellation = GraphImportReadingCancellation();
      documents
        ..copyFailure = const DocumentNotRead()
        ..afterCopyAnswer = cancellation.request;

      final reading = await readChosen(cancellation: cancellation);

      expect(reading, isA<GraphImportFileReadingCancelled>());
      expect(diagnostics.events, isEmpty);
      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('после ответа с началом фотографии имеет приоритет над '
        'отказом заголовка и не даёт события диагностики', () async {
      choose(photoFile());
      final cancellation = GraphImportReadingCancellation();

      documents.afterPrefixAnswer = cancellation.request;
      final reading = await readChosen(cancellation: cancellation);

      expect(reading, isA<GraphImportFileReadingCancelled>());
      expect(diagnostics.events, isEmpty);
      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('во время копирования документа сразу завершает чтение файла без '
        'временных файлов и события диагностики, а копирование, брошенное ею и закончившееся во '
        'время следующего импорта, не меняет его временный файл и '
        'исход', () async {
      choose(graphExportFileOf(reference));
      final providerAnswer = Completer<void>();
      final copyStarted = Completer<void>();
      documents.beforeCopy = () {
        copyStarted.complete();
        return providerAnswer.future;
      };
      final cancellation = GraphImportReadingCancellation();
      final abandoned = readChosen(cancellation: cancellation);
      await copyStarted.future;

      cancellation.request();

      expect(await abandoned, isA<GraphImportFileReadingCancelled>());
      expect(diagnostics.events, isEmpty);
      documents.beforeCopy = null;
      final file = await readFile(graphExportFileOf(reference));
      providerAnswer.complete();
      await documents.copies.first;
      expect(await importFile(file), isA<GraphImported>());
      expect(await graphState(), reference.skip(1));
      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('сразу после копирования документа завершает чтение файла без '
        'временных файлов и события диагностики', () async {
      choose(graphExportFileOf(reference));
      final cancellation = GraphImportReadingCancellation();

      expect(
        await readChosen(
          access: _CancelledAfterCopy(documents, cancellation),
          cancellation: cancellation,
        ),
        isA<GraphImportFileReadingCancelled>(),
      );

      expect(await _fileNamesIn(temporary), isEmpty);
      expect(diagnostics.events, isEmpty);
    });

    test('во время записи снимка замены прекращает импорт без изменений, '
        'без файлов и без события диагностики', () async {
      await createGraph();
      final before = await storedState();
      final file = await readFile(graphExportFileOf(reference));
      final [copy] = await temporary.list().toList();
      final stalls = ReceivePort();
      addTearDown(stalls.close);
      replacementSnapshotRunner = writeGraphReplacementSnapshotStallingReadOf(
        copy.path,
        stalls.sendPort,
      );
      final cancellation = GraphReplacementCancellation();
      final phases = <GraphReplacementPhase>{};
      final imported = importFile(
        file,
        onProgress: (progress) => phases.add(progress.phase),
        cancellation: cancellation,
      );
      final resume = await stalls.first as SendPort;

      cancellation.request();
      // Отмена уходит в изолят записи микрозадачей и приходит туда раньше
      // продолжения чтения: сообщения одного изолята доставляются по порядку.
      await Future<void>.delayed(Duration.zero);
      resume.send(null);

      expect(await imported, isA<GraphImportCancelled>());
      expect(phases, isNot(contains(GraphReplacementPhase.replacement)));
      expect(await storedState(), before);
      expect(await _fileNamesIn(temporary), isEmpty);
      expect(diagnostics.events, isEmpty);
    });
  });

  group('импорт на протяжении жизни контейнера', () {
    late List<GraphImportState> states;
    late List<GraphCommandCompletion> completions;

    setUp(() {
      states = [];
      container.listen(
        graphImportControllerProvider,
        (_, state) => states.add(state),
      );
      completions = [];
      final published = container
          .read(graphCommandCoordinatorProvider.notifier)
          .completions
          .listen(completions.add);
      addTearDown(published.cancel);
    });

    GraphImportController controller() =>
        container.read(graphImportControllerProvider.notifier);

    GraphImportState current() => container.read(graphImportControllerProvider);

    /// Дожидается состояния импорта вида [T].
    Future<T> reached<T extends GraphImportState>() async {
      if (current() case final T state) return state;
      final reached = Completer<T>();
      final subscription = container.listen(graphImportControllerProvider, (
        _,
        state,
      ) {
        if (state case final T state when !reached.isCompleted) {
          reached.complete(state);
        }
      });
      try {
        return await reached.future;
      } finally {
        subscription.close();
      }
    }

    test('сценарий «Отмена чтения выбранного файла»: отмена показывает '
        'отмену, пока копирование документа не прекращено, и завершает импорт '
        'без подтверждения, сообщения, изменений и временных файлов', () async {
      await createGraph();
      final before = await storedState();
      choose(graphExportFileOf(reference));
      final providerAnswer = Completer<void>();
      final copyStarted = Completer<void>();
      documents.beforeCopy = () {
        copyStarted.complete();
        return providerAnswer.future;
      };
      final started = controller().start();
      await reached<GraphImportReadingFile>();
      await copyStarted.future;

      controller().cancel();

      expect(current(), isA<GraphImportCancelling>());
      expect(await started, isNull);
      expect(states, [
        isA<GraphImportReadingFile>(),
        isA<GraphImportCancelling>(),
        isA<GraphImportIdle>(),
      ]);
      providerAnswer.complete();
      await documents.copies.single;
      expect(completions, isEmpty);
      expect(await storedState(), before);
      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('отмена, пока после чтения файла читается состав графа, завершает '
        'импорт без подтверждения и временных файлов', () async {
      await createGraph();
      choose(graphExportFileOf(reference));
      final compositionRead = composition.holdNextRead();
      final started = controller().start();
      await compositionRead.reached;

      controller().cancel();
      compositionRead.release();

      expect(await started, isNull);
      expect(states, [
        isA<GraphImportReadingFile>(),
        isA<GraphImportCancelling>(),
        isA<GraphImportIdle>(),
      ]);
      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('отказ чтения файла завершает импорт, принятый координатором, без '
        'подтверждения, а вызывающий по его токену получает право предъявить '
        'отказ', () async {
      await createGraph();
      final before = await storedState();
      choose(photoFile());

      final accepted = await controller().start();

      expect(
        await accepted!.future,
        _importFailedWith(GraphImportFailure.invalidFile),
      );
      final claim = container
          .read(graphCommandCoordinatorProvider.notifier)
          .claimInitiatorFailure(accepted.token);
      expect(
        claim?.completion,
        isA<GraphImportCompletion>().having(
          (completion) => completion.result,
          'исход',
          _importFailedWith(GraphImportFailure.invalidFile),
        ),
      );
      expect(states, [isA<GraphImportReadingFile>(), isA<GraphImportIdle>()]);
      expect(await storedState(), before);
    });

    test('при непустом графе импорт ждёт подтверждения с датой сохранения и '
        'количествами файла, не меняя граф, а подтверждение заменяет граф '
        'записями файла', () async {
      await createGraph();
      final before = await storedState();
      choose(graphExportFileOf(reference));
      final started = controller().start();

      final awaiting = await reached<GraphImportAwaitingConfirmation>();

      expect(
        awaiting.header.writtenAt,
        DateTime.utc(2026, 10, 3, 18, 42, 7, 654, 321),
      );
      expect(_countsOf(awaiting.header.counts), [2, 4, 3, 3, 2]);
      expect(await storedState(), before);
      controller().confirm();
      expect(await (await started)!.future, isA<GraphImported>());
      expect(await graphState(), reference.skip(1));
      expect(current(), isA<GraphImportIdle>());
    });

    test('при пустом графе, состав которого не прочитан, импорт ждёт '
        'подтверждения', () async {
      composition.failsReads = true;
      choose(graphExportFileOf(reference));
      final started = controller().start();

      await reached<GraphImportAwaitingConfirmation>();

      expect(await graphState(), isEmpty);
      controller().decline();
      await started;
    });

    test('отказ от подтверждения завершает импорт без сообщения, изменений и '
        'временных файлов', () async {
      await createGraph();
      final before = await storedState();
      choose(graphExportFileOf(reference));
      final started = controller().start();
      await reached<GraphImportAwaitingConfirmation>();

      controller().decline();

      expect(await started, isNull);
      expect(current(), isA<GraphImportIdle>());
      expect(completions, isEmpty);
      expect(await storedState(), before);
      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('сценарий «Импорт в пустой граф без подтверждения»: замена '
        'начинается сразу после чтения файла', () async {
      choose(graphExportFileOf(reference));

      final accepted = await controller().start();

      expect(await accepted!.future, isA<GraphImported>());
      expect(states, isNot(contains(isA<GraphImportAwaitingConfirmation>())));
      expect(await graphState(), reference.skip(1));
    });

    test('ход замены сообщается долями обеих фаз по порядку от нуля до '
        'полного, а после импорта его нет', () async {
      choose(graphExportFileOf(reference));

      await (await controller().start())!.future;

      final progress = [
        for (final state in states)
          if (state case GraphImportReplacing(:final progress)) progress,
      ];
      for (final phase in GraphReplacementPhase.values) {
        final shares = [
          for (final step in progress)
            if (step.phase == phase) step.share,
        ];
        expect(shares.first, 0, reason: '$phase');
        expect(shares.last, 1, reason: '$phase');
        for (var index = 1; index < shares.length; index++) {
          expect(shares[index], greaterThan(shares[index - 1]));
        }
      }
      final phases = [for (final step in progress) step.phase];
      expect(
        phases.indexOf(GraphReplacementPhase.replacement),
        greaterThan(phases.lastIndexOf(GraphReplacementPhase.snapshotWrite)),
      );
      expect(states.last, isA<GraphImportIdle>());
    });

    test('отмена во время замены показывает отмену до конца отката и '
        'завершает импорт без сообщения, изменений, временных файлов и '
        'события диагностики', () async {
      await createGraph();
      final before = await storedState();
      choose(graphExportFileOf(reference));
      final started = controller().start();
      await reached<GraphImportAwaitingConfirmation>();
      container.listen(graphImportControllerProvider, (_, state) {
        if (state case GraphImportReplacing(
          progress: GraphReplacementProgress(
            phase: GraphReplacementPhase.replacement,
            share: > 0,
          ),
        )) {
          scheduleMicrotask(controller().cancel);
        }
      });

      controller().confirm();

      expect(await (await started)!.future, isA<GraphImportCancelled>());
      expect(states.sublist(states.length - 2), [
        isA<GraphImportCancelling>(),
        isA<GraphImportIdle>(),
      ]);
      expect(completions, isEmpty);
      expect(await storedState(), before);
      expect(await _fileNamesIn(temporary), isEmpty);
      expect(diagnostics.events, isEmpty);
    });

    test('после точки невозврата замены отмена не принимается: импорт '
        'подтверждает замену без отмены и заменяет граф', () async {
      choose(graphExportFileOf(reference));
      container.listen(graphImportControllerProvider, (_, state) {
        if (state is GraphImportCommitting) controller().cancel();
      });

      final accepted = await controller().start();

      expect(await accepted!.future, isA<GraphImported>());
      expect(states, isNot(contains(isA<GraphImportCancelling>())));
      expect(states.sublist(states.length - 2), [
        isA<GraphImportCommitting>(),
        isA<GraphImportIdle>(),
      ]);
      expect(await graphState(), reference.skip(1));
    });

    test('пока ожидается ответ диалога выбора или идёт импорт, новый запуск '
        'ничего не делает', () async {
      final document = choose(graphExportFileOf(reference));
      var dialogs = 0;
      final answer = Completer<DocumentOpening>();
      documents.openingDialog = () {
        dialogs += 1;
        return answer.future;
      };
      final releaseSnapshotWrite = Completer<void>();
      replacementSnapshotRunner = (write) async {
        await releaseSnapshotWrite.future;
        return runGraphReplacementSnapshotWriteInIsolate(write);
      };
      final first = controller().start();
      final duringDialog = controller().start();
      answer.complete(documents.chosen(document));
      final accepted = await first;

      final duringImport = controller().start();
      releaseSnapshotWrite.complete();

      expect(await accepted!.future, isA<GraphImported>());
      expect(await duringDialog, isNull);
      expect(await duringImport, isNull);
      expect(dialogs, 1);
    });
  });
}

/// Где импорт обнаружил, что файл не подходит.
enum _Detection { header, snapshotWrite, replacement }

/// Действие копирования, пережившего прежний движок и его Dart-изолят.
enum _LateCopy { cancelledDeletion, detachedWrite }

/// Чтение настоящим GraphImport в новом изоляте. Копированием управляет
/// вызывающая проверка вне этого изолята, в том числе после его завершения.
Future<
  ({
    File copy,
    SendPort answer,
    Isolate isolate,
    Future<GraphImportFileReading> reading,
  })
>
_startImportReadInNewIsolate(Directory temporary, File document) async {
  final requests = ReceivePort();
  addTearDown(requests.close);
  final reading = _readChosenFileInNewIsolate(
    temporary.path,
    document.uri.toString(),
    requests.sendPort,
  );
  // Уничтожение изолята ожидаемо завершает Isolate.run ошибкой. Даже если
  // проверка прервалась раньше, ошибка не должна стать необработанной.
  reading.ignore();
  final (path, answer, isolate) =
      await requests.first as (String, SendPort, Isolate);
  requests.close();
  addTearDown(() => isolate.kill(priority: Isolate.immediate));
  return (copy: File(path), answer: answer, isolate: isolate, reading: reading);
}

/// Отдельная функция не захватывает базу и контейнер проверки замыканием.
Future<GraphImportFileReading> _readChosenFileInNewIsolate(
  String temporaryPath,
  String documentUri,
  SendPort requests,
) => Isolate.run(() async {
  final storage = _UnusedImportStorage();
  final graphImport = GraphImport(
    documents: _ExternalCopyDocumentAccess(documentUri, requests),
    compaction: GraphLogCompaction(
      log: storage,
      directory: Directory('$temporaryPath/snapshots'),
      clock: DateTime.now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    ),
    replacement: storage,
    temporaryDirectory: Future.value(Directory(temporaryPath)),
    snapshotFiles: Future.value(),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  return graphImport.readChosenFile(
    onDocumentChosen: () {},
    cancellation: GraphImportReadingCancellation(),
  );
});

/// До чтения записей импорт не обращается к логу и замене графа.
final class _UnusedImportStorage
    implements ObservableGraphFactLog, GraphReplacement {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('Чтение документа не должно обращаться к хранилищу.');
}

/// Передаёт копирование наружу, чтобы оно переживало уничтожение изолята.
final class _ExternalCopyDocumentAccess implements DocumentAccess {
  _ExternalCopyDocumentAccess(this._documentUri, this._requests);

  final String _documentUri;
  final SendPort _requests;

  @override
  Future<DocumentOpening> openDocument() async =>
      DocumentOpened(OpenedDocument(_documentUri));

  @override
  DocumentRead readDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) {
    final read = FileDocumentAccess(Directory.systemTemp).readDocument(
      document,
      destination: destination,
      cancellation: cancellation,
    );
    return _CopyOverride(read, () async {
      final answers = ReceivePort();
      try {
        _requests.send((destination.path, answers.sendPort, Isolate.current));
        return await answers.first as DocumentCopy;
      } finally {
        answers.close();
      }
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Отказ импорта на этапе [stage] с категорией [failure] так, как его
/// кодирует журнал разработчика, без длительности.
Map<String, Object?> _importFailed(String stage, GraphImportFailure failure) =>
    {
      'operation': 'graphImport',
      'stage': stage,
      'outcome': 'failed',
      'failureCode': switch (failure) {
        GraphImportFailure.invalidFile => 'invalidGraphFile',
        GraphImportFailure.newerFormatVersion => 'newerGraphFormatVersion',
        GraphImportFailure.storageFull => 'storageFull',
        GraphImportFailure.documentUnreadable => 'documentUnreadable',
        GraphImportFailure.unknown => 'unexpected',
      },
    };

Matcher _readingFailed(GraphImportFailure failure) =>
    isA<GraphImportFileReadingFailed>().having(
      (failed) => failed.failure,
      'категория',
      failure,
    );

Matcher _importFailedWith(GraphImportFailure failure) =>
    isA<GraphImportFailed>().having(
      (failed) => failed.failure,
      'категория',
      failure,
    );

/// Состав графа источника [_source], чтение которого отказывает, пока
/// [failsReads] истинно, а следующее после [holdNextRead] чтение ждёт
/// задержки.
final class _ControlledComposition implements GraphCompositionSource {
  _ControlledComposition(this._source);

  final GraphCompositionSource _source;
  var failsReads = false;
  _CompositionReadHold? _hold;

  _CompositionReadHold holdNextRead() => _hold = _CompositionReadHold();

  @override
  Stream<GraphCompositionRead> watchComposition() async* {
    if (_hold case final hold?) {
      _hold = null;
      hold._reached.complete();
      await hold._released.future;
    }
    if (failsReads) {
      yield const GraphCompositionReadFailed();
    } else {
      yield* _source.watchComposition();
    }
  }
}

/// Задержка чтения состава графа: [reached] завершается, когда оно начато,
/// а продолжается оно после [release].
final class _CompositionReadHold {
  final _reached = Completer<void>();
  final _released = Completer<void>();

  Future<void> get reached => _reached.future;

  void release() => _released.complete();
}

/// Начало доступно порциями, а запрос остатка требует явного разрешения.
final class _PrefixDocumentAccess implements DocumentAccess, DocumentRead {
  _PrefixDocumentAccess(this._bytes) {
    addTearDown(() {
      if (!_release.isCompleted) _release.complete();
    });
  }

  final List<int> _bytes;
  final remainderRequested = Completer<void>();
  final prefixStarted = Completer<void>();
  final _release = Completer<void>();
  late File _destination;
  late Future<void> _cancellation;
  DocumentCopy? copyFailure;
  DocumentReadFailure? prefixFailure;
  var waitForCancellation = false;
  void Function()? onPrefixClosed;
  var copies = 0;
  var prefixClosed = false;
  var finished = false;

  @override
  Future<DocumentOpening> openDocument() async =>
      const DocumentOpened(OpenedDocument('content://chosen-document'));

  @override
  DocumentRead readDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) {
    _destination = destination;
    _cancellation = cancellation;
    return this;
  }

  @override
  late final Stream<List<int>> prefix = _prefix();

  Stream<List<int>> _prefix() async* {
    prefixStarted.complete();
    try {
      if (waitForCancellation) {
        await _cancellation;
        throw DocumentReadFailure.unreadable;
      }
      if (prefixFailure case final failure?) throw failure;
      for (
        var start = 0;
        start < _bytes.length;
        start += documentPrefixChunkSize
      ) {
        final end = start + documentPrefixChunkSize;
        yield _bytes.sublist(start, end < _bytes.length ? end : _bytes.length);
      }
      remainderRequested.complete();
      await _release.future;
    } finally {
      prefixClosed = true;
      onPrefixClosed?.call();
    }
  }

  @override
  Future<DocumentCopy> copy() async {
    copies++;
    if (copyFailure case final failure?) return failure;
    await _destination.writeAsBytes(_bytes);
    return const DocumentCopied();
  }

  @override
  Future<void> finish() async {
    finished = true;
    _release.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Отменяет чтение сразу после ответа о завершённом копировании.
final class _CancelledAfterCopy implements DocumentAccess {
  _CancelledAfterCopy(this._documents, this._cancellation);

  final DocumentAccess _documents;
  final GraphImportReadingCancellation _cancellation;

  @override
  Future<DocumentOpening> openDocument() => _documents.openDocument();

  @override
  DocumentRead readDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) {
    final read = _documents.readDocument(
      document,
      destination: destination,
      cancellation: cancellation,
    );
    return _CopyOverride(read, () async {
      final copy = await read.copy();
      _cancellation.request();
      return copy;
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Сохраняет сессию чтения и заменяет только продолжение копирования.
final class _CopyOverride implements DocumentRead {
  _CopyOverride(this._read, this._copy);

  final DocumentRead _read;
  final Future<DocumentCopy> Function() _copy;

  @override
  Stream<List<int>> get prefix => _read.prefix;

  @override
  Future<DocumentCopy> copy() => _copy();

  @override
  Future<void> finish() => _read.finish();
}

Future<Set<String>> _fileNamesIn(Directory directory) async => {
  if (await directory.exists())
    await for (final entity in directory.list()) entity.uri.pathSegments.last,
};

List<int> _countsOf(GraphRecordCounts counts) => [
  counts.tags,
  counts.intentions,
  counts.tagAssignments,
  counts.longTermRelations,
  counts.dailyChoices,
];

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
