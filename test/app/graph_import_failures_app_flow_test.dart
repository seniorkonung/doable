import 'dart:async';
import 'dart:io';

import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_flow_wait.dart' as app_flow;
import '../support/graph_import_app_harness.dart';
import '../support/graph_import_files.dart';
import '../support/temporary_import_document.dart';

/// Отказ импорта файла, который не является экспортом Doable или повреждён.
const _invalidFile =
    'Не удалось импортировать файл. Это не экспорт Doable, или он повреждён. '
    'Ничего не изменено';

/// Отказ импорта файла более новой версии формата.
const _newerVersion =
    'Файл создан более новой версией Doable. Обновите приложение, чтобы '
    'импортировать его. Ничего не изменено';

/// Отказ импорта, которому не хватило места на устройстве.
const _storageFull =
    'Недостаточно места на устройстве. Освободите место и повторите. '
    'Ничего не изменено';

/// Заголовок прогресса импорта.
const _importRunning = 'Импорт данных…';

void main() {
  testWidgets('принятая отмена чтения имеет приоритет над поздним отказом '
      'копирования: после «Отмена…» прогресс закрывается без подтверждения, '
      'сообщения, операции координатора и события отказа', (tester) async {
    final app = await _startApp(tester);
    await app.openSettings();
    final before = app.storedState();
    final completions = <GraphCommandCompletion>[];
    final subscription = app.container
        .read(graphCommandCoordinatorProvider.notifier)
        .completions
        .listen(completions.add);
    addTearDown(subscription.cancel);
    final providerAnswer = Completer<void>();
    final cancellationAnswer = Completer<void>();
    app.documents
      ..beforeCopy = (() => providerAnswer.future)
      ..beforeCancellationAnswer = (() => cancellationAnswer.future)
      ..copyFailure = const DocumentNotRead();
    app.chooseForImport(temporaryImportDocument(_referenceFile()));

    await app.startImport();
    await app_flow.until(tester, find.text(_importRunning));
    await tester.tap(find.text('Отменить'));
    await tester.pump();
    expect(find.text('Отмена…'), findsOneWidget);

    providerAnswer.complete();
    await app.waitForProgressEnd();
    cancellationAnswer.complete();
    await app_flow.settle(tester);

    expect(find.text('Импортировать эту копию?'), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(find.textContaining('Ничего не изменено'), findsNothing);
    expect(completions, isEmpty);
    expect(
      app.diagnostics.events.whereType<GraphImportDiagnosticsEvent>(),
      isEmpty,
    );
    expect(app.storedState(), before);
  });

  testWidgets('сценарий «Выбран чужой файл»: фотография без чтения остатка '
      'и попытки записи при нехватке места без подтверждения даёт '
      'под строкой «Импорт данных» отказ с действием «Выбрать другой файл», '
      'которое снова открывает системный диалог, а отказ от подтверждения '
      'выбранного в нём файла ничего не меняет и сообщения не даёт', (
    tester,
  ) async {
    final documents = _PhotoDocumentAccess();
    final app = await _startApp(tester, documents: documents);
    await app.openSettings();
    final before = app.storedState();

    await app.startImport();
    await app_flow.until(tester, find.text(_invalidFile));

    expect(find.text('Импортировать эту копию?'), findsNothing);
    expect(find.text(_storageFull), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(documents.remainderRequested, isFalse);
    expect(documents.copyAttempts, 0);
    expect(documents.finished, isTrue);
    expect(app.storedState(), before);

    // Подтверждение откроется, только если новый диалог выбрал исправный
    // файл.
    app.chooseForImport(temporaryImportDocument(_referenceFile()));
    documents.followingDocuments = app.documents;
    await tester.tap(find.text('Выбрать другой файл'));
    await app.waitForConfirmation();
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    // Прогресс и сообщение появились бы за это время.
    await app_flow.settle(tester);

    expect(find.text('Импортировать эту копию?'), findsNothing);
    expect(find.text(_importRunning), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(find.text(_invalidFile), findsNothing);
    expect(app.storedState(), before);
  });

  testWidgets('сценарий «Файл более новой версии»: без подтверждения под '
      'строкой «Импорт данных» отказ предлагает обновить приложение и не '
      'предлагает действия, а граф и копии остаются прежними', (tester) async {
    final app = await _startApp(tester);
    await app.openSettings();
    final before = app.storedState();
    app.chooseForImport(temporaryImportDocument(newerFormatVersionFile()));

    await app.startImport();
    await app_flow.until(tester, find.text(_newerVersion));

    expect(find.text('Импортировать эту копию?'), findsNothing);
    expect(find.text('Выбрать другой файл'), findsNothing);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(app.storedState(), before);
  });

  testWidgets('сценарий «Повреждение обнаружено после подтверждения»: после '
      'подтверждения файла, обрезанного посередине, замена отменяется, граф и '
      'копии остаются прежними, а под строкой «Импорт данных» показан отказ '
      'повреждённого файла', (tester) async {
    final app = await _startApp(tester);
    await app.openSettings();
    final before = app.storedState();
    app.chooseForImport(temporaryImportDocument(truncatedGraphExportFile()));
    await app.startImport();
    await app.waitForConfirmation();

    await app.confirmImport();
    await app_flow.until(tester, find.text(_invalidFile));

    expect(find.text(_importRunning), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(app.storedState(), before);
  });

  testWidgets('сценарий «Не хватает места на устройстве»: замена откатывается, '
      'граф и копии остаются прежними, а «Повторить» под строкой «Импорт '
      'данных» снова открывает системный диалог и после освобождения места '
      'импортирует выбранный в нём файл', (tester) async {
    final app = await _startApp(tester);
    await app.openSettings();
    app.fillStorage();
    final before = app.storedState();
    app.chooseForImport(temporaryImportDocument(_fileWithLongDescriptions()));
    await app.startImport();
    await app.waitForConfirmation();

    await app.confirmImport();
    await app_flow.until(tester, find.text(_storageFull));

    expect(find.text(_importRunning), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(app.storedState(), before);

    app.freeStorage();
    // Граф заменит эталонный файл, только если новый диалог выбрал его.
    app.chooseForImport(temporaryImportDocument(_referenceFile()));
    await tester.tap(find.text('Повторить'));
    await app.waitForConfirmation();
    await app.confirmImport();
    await app_flow.until(tester, find.text('Данные импортированы'));

    expect(find.text(_storageFull), findsNothing);
    expect(await app.graphState(), referenceGraphFileLines().skip(1));
  });
}

/// Показание часов устройства для графа, копий и местного сегодня.
final _now = DateTime(2026, 10, 6, 8, 15);

/// Создаёт граф командой, чтобы он был отражён в логе, и ждёт первую
/// ежедневную копию перед сравнением сохранённого состояния.
Future<ImportAppHarness> _startApp(
  WidgetTester tester, {
  DocumentAccess? documents,
}) async {
  final app = await ImportAppHarness.start(
    tester,
    at: _now,
    documents: documents,
    seed: (graph) async {
      expect(
        await graph.execute(CreateTag(TagName.fromInput('Дом'))),
        isA<GraphCommandSucceeded>(),
      );
    },
  );
  await app.waitForBackups(1);
  return app;
}

/// Облачная фотография: доступно только начало, запись копии дала бы
/// нехватку места. Следующий выбор использует обычные файловые документы.
final class _PhotoDocumentAccess implements DocumentAccess, DocumentRead {
  DocumentAccess? followingDocuments;
  var remainderRequested = false;
  var copyAttempts = 0;
  var finished = false;

  @override
  Future<DocumentOpening> openDocument() async =>
      followingDocuments?.openDocument() ??
      const DocumentOpened(OpenedDocument('content://cloud/photo.jpg'));

  @override
  DocumentRead readDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) =>
      followingDocuments?.readDocument(
        document,
        destination: destination,
        cancellation: cancellation,
      ) ??
      this;

  @override
  Stream<List<int>> get prefix async* {
    yield photoFile();
    remainderRequested = true;
    throw DocumentReadFailure.unreadable;
  }

  @override
  Future<DocumentCopy> copy() async {
    copyAttempts++;
    return const DocumentCopyStorageFull();
  }

  @override
  Future<void> finish() async => finished = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Исправный эталонный файл экспорта.
List<int> _referenceFile() => graphExportFileOf(referenceGraphFileLines());

/// Эталонный файл экспорта, описания намерений которого занимают страницы
/// переполнения, которых в сжатом файле хранилища нет.
List<int> _fileWithLongDescriptions() {
  var lines = referenceGraphFileLines();
  for (var line = 3; line <= 6; line++) {
    lines = withEditedLine(lines, line, (intention) {
      intention['description'] = 'ж' * 4000;
    });
  }
  return graphExportFileOf(lines);
}
