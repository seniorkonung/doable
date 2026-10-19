import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/data_transfer/application/graph_import.dart';
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
  var replacementSnapshotRunner = runGraphReplacementSnapshotWriteInIsolate;
  var chosenFiles = 0;

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
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() async {
      await container.read(graphCommandCoordinatorProvider.notifier).shutdown();
      container.dispose();
    });
  });

  GraphImport graphImport({DocumentAccess? access}) => GraphImport(
    documents: access ?? documents,
    compaction: compaction,
    replacement: repository,
    temporaryDirectory: Future.value(temporary),
    snapshotFiles: Future.value(),
  );

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
    Future<void>? cancellation,
  }) => graphImport(access: access).readChosenFile(
    onDocumentChosen: onDocumentChosen ?? () {},
    cancellation: cancellation ?? Completer<void>().future,
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

  test('ход импорта сообщается долями записи снимка замены, а затем замены, '
      'и каждая растёт до полной', () async {
    await createGraph();
    final file = await readFile(graphExportFileOf(reference));
    final progress = <GraphReplacementProgress>[];

    await importFile(file, onProgress: progress.add);

    final phases = [for (final step in progress) step.phase];
    expect(
      phases.indexOf(GraphReplacementPhase.replacement),
      greaterThan(phases.lastIndexOf(GraphReplacementPhase.snapshotWrite)),
    );
    for (final phase in GraphReplacementPhase.values) {
      final shares = [
        for (final step in progress)
          if (step.phase == phase) step.share,
      ];
      for (var index = 1; index < shares.length; index++) {
        expect(shares[index], greaterThan(shares[index - 1]));
      }
      expect(shares.last, 1, reason: '$phase');
    }
  });

  test('неподходящий файл отклоняется там, где его можно обнаружить, своим '
      'исходом и не меняет граф, копии, лог, реестр и каталог снимков и '
      'временный каталог', () async {
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
      expect(await rejectionOf(bytes), rejection, reason: reason);
      expect(await storedState(), before, reason: reason);
      expect(await _fileNamesIn(temporary), isEmpty, reason: reason);
    }
  });

  test('отмена диалога, диалог, который не открылся, и отказы копирования '
      'документа дают свои исходы и не оставляют временных файлов', () async {
    final document = choose(graphExportFileOf(reference));
    final cases = <String, (DocumentOpening, DocumentCopy?, Matcher)>{
      'отмена диалога': (
        const DocumentOpeningCancelled(),
        null,
        isA<GraphImportFileReadingCancelled>(),
      ),
      'диалог не открылся': (
        const DocumentOpeningFailed(),
        null,
        _readingFailed(GraphImportFailure.unknown),
      ),
      'документ не прочитан': (
        documents.chosen(document),
        const DocumentNotRead(),
        _readingFailed(GraphImportFailure.documentUnreadable),
      ),
      'копии не хватило места': (
        documents.chosen(document),
        const DocumentCopyStorageFull(),
        _readingFailed(GraphImportFailure.storageFull),
      ),
      'копия не записана': (
        documents.chosen(document),
        const DocumentCopyFailed(),
        _readingFailed(GraphImportFailure.unknown),
      ),
    };

    for (final MapEntry(key: reason, value: (dialog, copyFailure, outcome))
        in cases.entries) {
      documents
        ..openingDialog = (() async => dialog)
        ..copyFailure = copyFailure;

      expect(await readChosen(), outcome, reason: reason);
      expect(await _fileNamesIn(temporary), isEmpty, reason: reason);
    }
  });

  test('отказ от прочитанного файла удаляет его временную копию', () async {
    final file = await readFile(graphExportFileOf(reference));

    await file.discard();

    expect(await _fileNamesIn(temporary), isEmpty);
  });

  group('нехватка места', () {
    test(
      'при записи снимка замены даёт свой исход и ничего не меняет',
      () async {
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

        expect(await storedState(), before);
        expect(await _fileNamesIn(temporary), isEmpty);
      },
    );

    test('при замене графа, когда база не может вырасти, даёт свой исход и '
        'ничего не меняет', () async {
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

      expect(await storedState(), before);
      expect(await _fileNamesIn(temporary), isEmpty);
    });
  });

  group('отмена', () {
    test('во время копирования документа сразу завершает чтение файла без '
        'временных файлов, а копирование, брошенное ею и закончившееся во '
        'время следующего импорта, не меняет его временный файл и '
        'исход', () async {
      choose(graphExportFileOf(reference));
      final providerAnswer = Completer<void>();
      documents.beforeCopy = () => providerAnswer.future;
      final cancellation = Completer<void>();
      final chosen = Completer<void>();
      final abandoned = readChosen(
        onDocumentChosen: chosen.complete,
        cancellation: cancellation.future,
      );
      await chosen.future;

      cancellation.complete();

      expect(await abandoned, isA<GraphImportFileReadingCancelled>());
      documents.beforeCopy = null;
      final file = await readFile(graphExportFileOf(reference));
      providerAnswer.complete();
      await documents.copies.first;
      expect(await importFile(file), isA<GraphImported>());
      expect(await graphState(), reference.skip(1));
      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('сразу после копирования документа завершает чтение файла без '
        'временных файлов', () async {
      choose(graphExportFileOf(reference));
      final cancellation = Completer<void>();

      expect(
        await readChosen(
          access: _CancelledAfterCopy(documents, cancellation),
          cancellation: cancellation.future,
        ),
        isA<GraphImportFileReadingCancelled>(),
      );

      expect(await _fileNamesIn(temporary), isEmpty);
    });

    test('во время записи снимка замены прекращает импорт без изменений и '
        'без файлов', () async {
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
    });

    test('во время замены откатывает её без изменений и без файлов', () async {
      await createGraph();
      final before = await storedState();
      final file = await readFile(graphExportFileOf(reference));
      final cancellation = GraphReplacementCancellation();

      final outcome = await importFile(
        file,
        onProgress: (progress) {
          if (progress case GraphReplacementProgress(
            phase: GraphReplacementPhase.replacement,
            share: > 0,
          )) {
            scheduleMicrotask(cancellation.request);
          }
        },
        cancellation: cancellation,
      );

      expect(outcome, isA<GraphImportCancelled>());
      expect(await storedState(), before);
      expect(await _fileNamesIn(temporary), isEmpty);
    });
  });
}

/// Где импорт обнаружил, что файл не подходит.
enum _Detection { header, snapshotWrite, replacement }

Matcher _readingFailed(GraphImportFailure failure) =>
    isA<GraphImportFileReadingFailed>().having(
      (failed) => failed.failure,
      'категория',
      failure,
    );

/// Доступ к документам, при котором человек отменяет чтение файла сразу
/// после того, как документ скопирован.
final class _CancelledAfterCopy implements DocumentAccess {
  _CancelledAfterCopy(this._documents, this._cancellation);

  final DocumentAccess _documents;
  final Completer<void> _cancellation;

  @override
  Future<DocumentOpening> openDocument() => _documents.openDocument();

  @override
  Future<DocumentCopy> copyDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) async {
    final copy = await _documents.copyDocument(
      document,
      destination: destination,
      cancellation: cancellation,
    );
    _cancellation.complete();
    return copy;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
