import 'dart:async';

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
Future<ImportAppHarness> _startApp(WidgetTester tester) async {
  final app = await ImportAppHarness.start(
    tester,
    at: _now,
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
