import 'dart:async';
import 'dart:io';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tag;
import 'package:doable/src/data_transfer/application/graph_composition.dart';
import 'package:doable/src/data_transfer/application/graph_composition_provider.dart';
import 'package:doable/src/data_transfer/application/graph_export.dart';
import 'package:doable/src/data_transfer/application/graph_export_provider.dart';
import 'package:doable/src/data_transfer/presentation/settings_data_section.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/file_document_access.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  for (final (language, title, explanation, name, nothing, hint) in [
    (
      'ru',
      'Данные',
      'Всё, что вы пишете, хранится только на этом устройстве.',
      'Экспорт данных',
      'Пока нечего экспортировать',
      'Сохранить копию всего в файл',
    ),
    (
      'en',
      'Data',
      'Everything you write is stored only on this device.',
      'Export data',
      'Nothing to export yet',
      'Save a copy of everything to a file',
    ),
  ]) {
    testWidgets('$language: строка «Экспорт данных» пустого графа недоступна, '
        'а с первым тегом открывает панель экспорта', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _DataSectionApp.open(tester, language: language);

      expect(
        tester.getSemantics(find.text(title)),
        matchesSemantics(label: title, isHeader: true),
      );
      expect(find.text(explanation), findsOneWidget);
      expect(find.text(nothing), findsOneWidget);
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await app.createTag('Дом');
      await tester.pumpAndSettle();
      expect(find.text(nothing), findsNothing);
      await tester.tap(find.text(hint));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets('строка снова недоступна, когда удалён последний тег, и '
      'доступна, когда создано намерение', (tester) async {
    final app = await _DataSectionApp.open(tester);
    final tag = await app.createTag('Дом');
    await tester.pumpAndSettle();
    expect(find.text('Сохранить копию всего в файл'), findsOneWidget);

    await app.confirm<TagDeleted>(DeleteTag(tag.id));
    await tester.pumpAndSettle();
    expect(find.text('Пока нечего экспортировать'), findsOneWidget);

    await app.confirm<IntentionSaved>(
      CreateIntention.withInitialState(
        title: 'Бегать',
        description: null,
        readiness: IntentionReadiness.notReady,
        tagIds: const {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сохранить копию всего в файл'), findsOneWidget);
  });

  testWidgets('при отказе чтения состава строка доступна с обычной подписью '
      'и открывает панель экспорта', (tester) async {
    await _DataSectionApp.open(
      tester,
      composition: Stream.value(const GraphCompositionReadFailed()),
    );

    await tester.tap(find.text('Сохранить копию всего в файл'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('пока состав не прочитан, строка не принимает выбор', (
    tester,
  ) async {
    final composition = StreamController<GraphCompositionRead>();
    addTearDown(composition.close);
    await _DataSectionApp.open(tester, composition: composition.stream);

    await tester.tap(find.text('Экспорт данных'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
  });

  for (final (language, name, save, running, progress, hint) in [
    (
      'ru',
      'Экспорт данных',
      'Сохранить в файл',
      'Сохраняется в файл…',
      '100 %',
      'Сохранить копию всего в файл',
    ),
    (
      'en',
      'Export data',
      'Save to a file',
      'Saving to a file…',
      '100%',
      'Save a copy of everything to a file',
    ),
  ]) {
    testWidgets('$language: пока экспорт идёт, строка показывает его ход '
        'экранному диктору, а её выбор не запускает второй экспорт', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await _DataSectionApp.open(tester, language: language);
      await app.createTag('Дом');
      await tester.pumpAndSettle();
      final writeReached = Completer<void>();
      final releaseWrite = Completer<void>();
      app.documents.beforeWrite = () {
        writeReached.complete();
        return releaseWrite.future;
      };
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(save));
      await _pumpUntil(tester, () => writeReached.isCompleted);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.text(name)),
        matchesSemantics(
          label: '$name\n$running',
          value: progress,
          isButton: true,
          hasEnabledState: true,
          hasSelectedState: true,
        ),
      );
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(app.documents.suggestedNames, hasLength(1));

      releaseWrite.complete();
      await _pumpUntil(tester, () => find.text(hint).evaluate().isNotEmpty);
      expect(app.documents.created.single.lengthSync(), isPositive);
      semantics.dispose();
    });
  }
}

/// Раздел «Данные» над настоящим хранилищем графа в памяти: состав читает,
/// а экспорт пишет репозиторий. Документы — файлы временного каталога, а
/// чтение состава можно заменить потоком [composition].
final class _DataSectionApp {
  _DataSectionApp._(this._repository, this.documents);

  final DriftPersonalGraphRepository _repository;
  final FileDocumentAccess documents;

  static Future<_DataSectionApp> open(
    WidgetTester tester, {
    String language = 'ru',
    Stream<GraphCompositionRead>? composition,
  }) async {
    final database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    addTearDown(database.close);
    var now = DateTime.utc(2026, 10, 18, 9);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now = now.add(const Duration(seconds: 1)),
      InMemoryDiagnosticsSink(),
    );
    final directory = Directory.systemTemp.createTempSync(
      'doable_settings_data_section_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final documents = FileDocumentAccess(
      Directory('${directory.path}/documents')..createSync(),
    );
    final export = GraphExport(
      documents: documents,
      compaction: GraphLogCompaction(
        log: repository,
        directory: Directory('${directory.path}/graph_snapshots')..createSync(),
        clock: () => now,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      ),
      temporaryDirectory: Future.value(Directory('${directory.path}/tmp')),
      clock: () => DateTime(2026, 10, 18, 12),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
          graphCompositionSourceProvider.overrideWithValue(
            switch (composition) {
              null => repository,
              final composition => _CompositionSource(composition),
            },
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
          home: const Scaffold(body: SettingsDataSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _DataSectionApp._(repository, documents);
  }

  Future<T> confirm<T extends GraphCommandOutcome>(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await _repository.execute(command);
    final confirmed =
        (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
            as ConfirmedGraphResult;
    return confirmed.value as T;
  }

  Future<Tag> createTag(String name) async =>
      (await confirm<TagCreated>(CreateTag(TagName.fromInput(name)))).tag;
}

final class _CompositionSource implements GraphCompositionSource {
  const _CompositionSource(this._reads);

  final Stream<GraphCompositionRead> _reads;

  @override
  Stream<GraphCompositionRead> watchComposition() => _reads;
}

/// Чередует реальное ожидание, в котором идут файловые операции и изолят
/// экспорта, с кадрами, пока не выполнится [condition].
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Условие не выполнилось');
}
