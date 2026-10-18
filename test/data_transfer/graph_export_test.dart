import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' show AppDatabase;
import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/data_transfer/application/graph_export.dart';
import 'package:doable/src/data_transfer/application/graph_export_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_file.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/encoded_diagnostics_log.dart';
import '../support/failing_snapshot_temporary_files.dart';
import '../support/file_document_access.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late Directory snapshots;
  late Directory temporary;
  late FileDocumentAccess documents;
  late EncodedDiagnosticsLog diagnostics;
  var now = DateTime.utc(2026, 10, 7, 9);
  // Местное время, поэтому дата в имени документа не зависит от часового
  // пояса проверки.
  final exportMoment = DateTime(2026, 10, 7, 23, 30);

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    database = await harness.openReadyDatabase();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now = now.add(const Duration(seconds: 1)),
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
    diagnostics = EncodedDiagnosticsLog();
  });

  /// Контейнер приложения с экспортом, который пишет состояние графа
  /// изолятом [stateWriteRunner].
  ProviderContainer app({
    GraphStateWriteRunner stateWriteRunner = runGraphStateWriteInIsolate,
  }) {
    final export = GraphExport(
      documents: documents,
      compaction: GraphLogCompaction(
        log: repository,
        directory: snapshots,
        clock: () => now,
        diagnosticsSink: InMemoryDiagnosticsSink(),
        stateWriteRunner: stateWriteRunner,
      ),
      temporaryDirectory: Future.value(temporary),
      clock: () => exportMoment,
      diagnosticsSink: diagnostics,
    );
    final container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        graphExportControllerProvider.overrideWith(
          () => GraphExportController(export),
        ),
      ],
    );
    addTearDown(() async {
      await container.read(graphCommandCoordinatorProvider.notifier).shutdown();
      container.dispose();
    });
    return container;
  }

  /// Завершение следующего экспорта, опубликованное координатором.
  Future<GraphExportCompletion> nextExport(ProviderContainer container) =>
      container
          .read(graphCommandCoordinatorProvider.notifier)
          .completions
          .where((completion) => completion is GraphExportCompletion)
          .cast<GraphExportCompletion>()
          .first;

  Future<void> startExport(ProviderContainer container) =>
      container.read(graphExportControllerProvider.notifier).start();

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

  Future<Intention> createIntention(
    String title, {
    Set<TagId> tagIds = const {},
  }) async => (await confirm<IntentionSaved>(
    CreateIntention.withInitialState(
      title: title,
      description: null,
      readiness: IntentionReadiness.notReady,
      tagIds: tagIds,
    ),
  )).intention;

  test('документ, выбранный в системном диалоге, читается модулем формата в '
      'выгрузку базы с моментом экспорта в заголовке, временный файл '
      'удаляется, работа с документом завершается один раз, а успех '
      'диагностируется без пользовательских данных', () async {
    final home = await createTag('Дом');
    final health = await createIntention('Здоровье', tagIds: {home.id});
    final running = await createIntention('Бегать');
    await confirm<LongTermRelationCreated>(
      CreateLongTermRelation(
        sourceIntentionId: health.id,
        relatedIntentionId: running.id,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    );
    await confirm(ArchiveIntention(running.id));
    final expected = _lines(await referenceGraphRecords(database));
    final container = app();
    final exported = nextExport(container);

    await startExport(container);

    expect((await exported).outcome, GraphExportOutcome.succeeded);
    final reading = await GraphFormatFile.read(
      documents.created.single.openRead(),
    );
    expect(reading.header.writtenAt, exportMoment.toUtc());
    expect(_lines(await reading.records.toList()), expected);
    expect(await _filesIn(temporary), isEmpty);
    expect(documents.finished, [documents.created.single.uri.toString()]);
    expect(diagnostics.events, [
      {'operation': 'graphExport', 'outcome': 'succeeded'},
    ]);
  });

  test('отмена диалога с именем по умолчанию «Doable <местная дата>.jsonl.gz» '
      'не принимает экспорт, не диагностируется и не оставляет файлов, а '
      'следующий запуск снова открывает диалог', () async {
    await createTag('Дом');
    documents.dialog = () async => const DocumentCreationCancelled();
    final container = app();
    final published = <GraphCommandCompletion>[];
    final subscription = container
        .read(graphCommandCoordinatorProvider.notifier)
        .completions
        .listen(published.add);
    addTearDown(subscription.cancel);
    final states = <GraphExportState>[];
    container.listen(
      graphExportControllerProvider,
      (_, state) => states.add(state),
    );

    await startExport(container);
    await pumpEventQueue();

    expect(documents.suggestedNames, ['Doable 2026-10-07.jsonl.gz']);
    expect(published, isEmpty);
    expect(states, isEmpty);
    expect(diagnostics.events, isEmpty);
    expect(await _filesIn(temporary), isEmpty);
    await startExport(container);
    expect(documents.suggestedNames, hasLength(2));
  });

  test('отказ записи временного файла даёт отказ экспорта, диагностируемый '
      'этапом записи временного файла, не оставляет временных файлов и '
      'созданного документа и завершает работу с документом '
      'один раз', () async {
    await createTag('Дом');
    final container = app(
      stateWriteRunner: writeGraphStateFailingIn(temporary),
    );
    final exported = nextExport(container);

    await startExport(container);

    expect((await exported).outcome, GraphExportOutcome.failed);
    expect(await _filesIn(temporary), isEmpty);
    expect(documents.created.single.existsSync(), isFalse);
    expect(documents.finished, [documents.created.single.uri.toString()]);
    expect(
      container.read(graphExportControllerProvider),
      isA<GraphExportIdle>(),
    );
    expect(diagnostics.events, [
      {
        'operation': 'graphExport',
        'stage': 'temporaryFileWrite',
        'outcome': 'failed',
        'failureCode': 'unavailable',
      },
    ]);
  });

  test('повреждённый последний снимок, когда сжатие лога не ведётся, даёт '
      'отказ экспорта, диагностируемый этапом записи временного файла и '
      'категорией повреждения снимка', () async {
    await createTag('Дом');
    final damaged = await GraphSnapshotStore(
      log: repository,
      directory: snapshots,
      clock: () => now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    ).writeSnapshot(1);
    final damagedFile = File.fromUri(snapshots.uri.resolve(damaged.fileName));
    final bytes = await damagedFile.readAsBytes();
    bytes[bytes.length ~/ 2] ^= 0xff;
    await damagedFile.writeAsBytes(bytes);
    final container = app();
    final exported = nextExport(container);

    await startExport(container);

    expect((await exported).outcome, GraphExportOutcome.failed);
    expect(diagnostics.events, [
      {
        'operation': 'graphExport',
        'stage': 'temporaryFileWrite',
        'outcome': 'failed',
        'failureCode': 'snapshotCorruption',
      },
    ]);
  });

  test('отказ записи документа даёт отказ экспорта без временных файлов и '
      'созданного документа, диагностируемый этапом записи документа, и '
      'завершает работу с документом один раз, а повтор из сообщения снова '
      'открывает диалог и сохраняет граф', () async {
    await createTag('Дом');
    documents.failsWrites = true;
    final container = app();
    final failed = nextExport(container);
    await startExport(container);
    final failure = await failed;
    expect(failure.outcome, GraphExportOutcome.failed);
    expect(await _filesIn(temporary), isEmpty);
    expect(documents.created.single.existsSync(), isFalse);
    expect(documents.finished, [documents.created.single.uri.toString()]);
    expect(diagnostics.events, [
      {
        'operation': 'graphExport',
        'stage': 'documentWrite',
        'outcome': 'failed',
        'failureCode': 'unavailable',
      },
    ]);

    documents.failsWrites = false;
    final retried = nextExport(container);
    failure.retry();

    expect((await retried).outcome, GraphExportOutcome.succeeded);
    expect(documents.suggestedNames, hasLength(2));
    final reading = await GraphFormatFile.read(
      documents.created.last.openRead(),
    );
    expect(
      _lines(await reading.records.toList()),
      _lines(await referenceGraphRecords(database)),
    );
  });

  test('системный диалог, который не открылся, даёт отказ экспорта, '
      'диагностируемый этапом создания документа', () async {
    await createTag('Дом');
    documents.dialog = () async => const DocumentCreationFailed();
    final container = app();
    final exported = nextExport(container);

    await startExport(container);

    expect((await exported).outcome, GraphExportOutcome.failed);
    expect(diagnostics.events, [
      {
        'operation': 'graphExport',
        'stage': 'documentCreation',
        'outcome': 'failed',
        'failureCode': 'unavailable',
      },
    ]);
  });

  test('файл с данными, выбранный в диалоге, даёт отдельный исход экспорта '
      'без хода экспорта и без диагностики', () async {
    await createTag('Дом');
    documents.dialog = () async => const ExistingFileChosen();
    final container = app();
    final states = <GraphExportState>[];
    container.listen(
      graphExportControllerProvider,
      (_, state) => states.add(state),
    );
    final exported = nextExport(container);

    await startExport(container);

    expect((await exported).outcome, GraphExportOutcome.existingFile);
    expect(states, isEmpty);
    expect(diagnostics.events, isEmpty);
  });

  test('повторный запуск во время ожидания диалога и во время экспорта не '
      'открывает второй диалог', () async {
    await createTag('Дом');
    final dialogAnswer = Completer<DocumentCreation>();
    documents.dialog = () => dialogAnswer.future;
    final writeReached = Completer<void>();
    final releaseWrite = Completer<void>();
    documents.beforeWrite = () {
      writeReached.complete();
      return releaseWrite.future;
    };
    final container = app();
    final exported = nextExport(container);
    final firstStart = startExport(container);

    // Диалог открывается синхронно, поэтому второй запуск не ожидается: иначе
    // второй диалог ждал бы ответа вместо отказа проверки.
    unawaited(startExport(container));
    expect(documents.suggestedNames, hasLength(1));

    dialogAnswer.complete(documents.newDocument());
    await firstStart;
    await writeReached.future;
    await startExport(container);
    expect(documents.suggestedNames, hasLength(1));

    releaseWrite.complete();
    expect((await exported).outcome, GraphExportOutcome.succeeded);
  });

  test(
    'ход экспорта растёт до полного, а после завершения экспорта нет',
    () async {
      final home = await createTag('Дом');
      await createIntention('Здоровье', tagIds: {home.id});
      await createIntention('Бегать');
      final container = app();
      final states = <GraphExportState>[];
      container.listen(
        graphExportControllerProvider,
        (_, state) => states.add(state),
      );
      final exported = nextExport(container);

      await startExport(container);
      await exported;

      final progress = [
        for (final state in states)
          if (state case GraphExportRunning(:final progress)) progress,
      ];
      expect(progress.first, 0);
      for (var index = 1; index < progress.length; index++) {
        expect(progress[index], greaterThan(progress[index - 1]));
      }
      expect(progress.last, 1);
      expect(states.last, isA<GraphExportIdle>());
    },
  );
}

/// Файлы каталога [directory]; каталога может ещё не быть.
Future<List<FileSystemEntity>> _filesIn(Directory directory) async =>
    await directory.exists() ? await directory.list().toList() : const [];

List<String> _lines(List<GraphEntityRecord> records) => [
  for (final record in records) utf8.decode(GraphFormatCodec.encode(record)),
];
