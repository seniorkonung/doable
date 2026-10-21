import 'dart:io';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/data_transfer/application/graph_composition.dart';
import 'package:doable/src/data_transfer/application/graph_composition_provider.dart';
import 'package:doable/src/data_transfer/application/graph_export.dart';
import 'package:doable/src/data_transfer/application/graph_export_provider.dart';
import 'package:doable/src/data_transfer/presentation/export_data_sheet.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/file_document_access.dart';
import '../../support/in_memory_diagnostics_sink.dart';

const _russianWarning =
    'Файл не защищён. Любой, у кого он есть, сможет прочитать написанное.';

void main() {
  for (final (language, title, composition, warning, button) in [
    (
      'ru',
      'Экспорт данных',
      '1 намерение, 2 связи, 5 дневных выборов и 21 тег в одном файле',
      _russianWarning,
      'Сохранить в файл',
    ),
    (
      'en',
      'Export data',
      '1 intention, 2 relations, 5 daily choices and 21 tags in one file',
      'The file is not protected. Anyone who has it can read what you wrote.',
      'Save to a file',
    ),
  ]) {
    testWidgets('$language: заголовок, состав файла, предупреждение и кнопка '
        'доступны экранному диктору', (tester) async {
      final semantics = tester.ensureSemantics();
      await _ExportSheetApp(
        const GraphCompositionReadSucceeded(
          GraphComposition(
            intentionCount: 1,
            relationCount: 2,
            dailyChoiceCount: 5,
            tagCount: 21,
          ),
        ),
      ).open(tester, language: language);

      expect(
        tester.getSemantics(find.text(title)),
        matchesSemantics(label: title, isHeader: true, namesRoute: true),
      );
      for (final text in [composition, warning]) {
        expect(
          tester.getSemantics(find.text(text)),
          matchesSemantics(label: text),
        );
      }
      expect(
        tester.getSemantics(find.widgetWithText(FilledButton, button)),
        matchesSemantics(
          label: button,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });
  }

  for (final (language, counts, composition) in [
    (
      'ru',
      (2, 5, 21, 1),
      '2 намерения, 5 связей, 21 дневной выбор и 1 тег в одном файле',
    ),
    (
      'ru',
      (5, 21, 1, 2),
      '5 намерений, 21 связь, 1 дневной выбор и 2 тега в одном файле',
    ),
    (
      'ru',
      (21, 1, 2, 5),
      '21 намерение, 1 связь, 2 дневных выбора и 5 тегов в одном файле',
    ),
    (
      'en',
      (2, 5, 21, 1),
      '2 intentions, 5 relations, 21 daily choices and 1 tag in one file',
    ),
    (
      'en',
      (5, 21, 1, 2),
      '5 intentions, 21 relations, 1 daily choice and 2 tags in one file',
    ),
    (
      'en',
      (21, 1, 2, 5),
      '21 intentions, 1 relation, 2 daily choices and 5 tags in one file',
    ),
  ]) {
    testWidgets('$language: состав согласует числа $counts по правилам языка', (
      tester,
    ) async {
      final (intentions, relations, dailyChoices, tags) = counts;
      await _ExportSheetApp(
        GraphCompositionReadSucceeded(
          GraphComposition(
            intentionCount: intentions,
            relationCount: relations,
            dailyChoiceCount: dailyChoices,
            tagCount: tags,
          ),
        ),
      ).open(tester, language: language);

      expect(find.text(composition), findsOneWidget);
    });
  }

  testWidgets('при отказе чтения состава панель показывает предупреждение '
      'и кнопку без состава', (tester) async {
    await _ExportSheetApp(const GraphCompositionReadFailed()).open(tester);

    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data),
      ['Экспорт данных', _russianWarning, 'Сохранить в файл'],
    );
  });

  testWidgets('«Сохранить в файл» закрывает панель и один раз открывает '
      'системный диалог сохранения', (tester) async {
    final app = _ExportSheetApp(
      const GraphCompositionReadSucceeded(
        GraphComposition(
          intentionCount: 1,
          relationCount: 0,
          dailyChoiceCount: 0,
          tagCount: 0,
        ),
      ),
    );
    await app.open(tester);

    await tester.tap(find.text('Сохранить в файл'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Открыть панель'), findsOneWidget);
    expect(app.documents.suggestedNames, ['Doable 2026-10-18.jsonl.gz']);
  });
}

/// Страница, открывающая панель экспорта, с составом графа [composition] и
/// экспортом, системный диалог которого человек закрывает без выбора места.
final class _ExportSheetApp {
  _ExportSheetApp(this.composition);

  final GraphCompositionRead composition;

  final documents = FileDocumentAccess(Directory.systemTemp)
    ..dialog = () async => const DocumentCreationCancelled();

  Future<void> open(WidgetTester tester, {String language = 'ru'}) async {
    final export = GraphExport(
      documents: documents,
      // Отмена диалога завершает экспорт до записи состояния графа.
      compaction: GraphLogCompaction(
        log: const _UnreadGraphFactLog(),
        directory: Directory.systemTemp,
        clock: DateTime.now,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      ),
      temporaryDirectory: Future.value(Directory.systemTemp),
      clock: () => DateTime(2026, 10, 18, 12),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          graphCompositionSourceProvider.overrideWithValue(
            _CompositionSource(composition),
          ),
          graphExportControllerProvider.overrideWith(
            () => GraphExportController(export),
          ),
        ],
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: doableTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showExportDataSheet(context),
                  child: const Text('Открыть панель'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть панель'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  }
}

final class _CompositionSource implements GraphCompositionSource {
  const _CompositionSource(this._read);

  final GraphCompositionRead _read;

  @override
  Stream<GraphCompositionRead> watchComposition() => Stream.value(_read);
}

/// Лог фактов, который панель не читает: экспорт до записи состояния не
/// доходит.
final class _UnreadGraphFactLog implements ObservableGraphFactLog {
  const _UnreadGraphFactLog();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Панель экспорта не читает лог фактов.');
}
