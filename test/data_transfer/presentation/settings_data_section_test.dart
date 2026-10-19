import 'dart:async';
import 'dart:io';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data/local/app_database.dart' hide GraphBackups, Tag;
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
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
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

  for (final (language, name, nothing, none, justNow, today, export) in [
    (
      'ru',
      'Резервные копии',
      'Пока нечего копировать',
      'Пока нет копий',
      'Последняя копия только что',
      'Последняя копия сегодня в 09:00',
      'Экспорт данных',
    ),
    (
      'en',
      'Backups',
      'Nothing to back up yet',
      'No backups yet',
      'Last copy just now',
      'Last copy today at 9:00 AM',
      'Export data',
    ),
  ]) {
    testWidgets('$language: строка «Резервные копии» стоит первой; без копий '
        'при пустом графе она недоступна, с первым тегом открывает панель '
        'копий, а после ручной копии сообщает время последней копии', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await _DataSectionApp.open(tester, language: language);

      expect(
        tester.getTopLeft(find.text(name)).dy,
        lessThan(tester.getTopLeft(find.text(export)).dy),
      );
      expect(
        tester.getSemantics(find.text(name)),
        matchesSemantics(
          label: '$name\n$nothing',
          isButton: true,
          hasEnabledState: true,
          hasSelectedState: true,
        ),
      );
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await app.createTag('Дом');
      await tester.pumpAndSettle();
      expect(find.text(none), findsOneWidget);
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text(name)),
        isSemantics(
          label: '$name\n$justNow',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      app.clock.now = app.clock.now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text(today), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets('пока копии есть, строка «Резервные копии» доступна и после '
      'удаления последнего тега', (tester) async {
    final app = await _DataSectionApp.open(tester);
    final tag = await app.createTag('Дом');
    await app.makeManualBackup();
    await tester.pumpAndSettle();

    await app.confirm<TagDeleted>(DeleteTag(tag.id));
    await tester.pumpAndSettle();
    expect(find.text('Пока нечего экспортировать'), findsOneWidget);
    await tester.tap(find.text('Последняя копия только что'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  for (final (language, madeAt, expected) in [
    ('ru', DateTime(2026, 10, 17, 21, 40), 'Последняя копия вчера в 21:40'),
    ('ru', DateTime(2026, 10, 6, 9, 5), 'Последняя копия 6 октября в 09:05'),
    ('en', DateTime(2026, 10, 17, 21, 40), 'Last copy yesterday at 9:40 PM'),
    ('en', DateTime(2026, 10, 6, 9, 5), 'Last copy on 6 October at 9:05 AM'),
  ]) {
    testWidgets('$language: строка «Резервные копии» сообщает день и время '
        'последней по созданию копии: $expected', (tester) async {
      await _DataSectionApp.open(
        tester,
        language: language,
        backups: Stream.value(
          GraphBackupsReadSucceeded([
            _backup(madeAt),
            _backup(DateTime(2026, 10, 18, 8, 15)),
          ]),
        ),
      );

      expect(find.text(expected), findsOneWidget);
    });
  }

  testWidgets('при отказе чтения копий строка «Резервные копии» и при пустом '
      'графе доступна без времени последней копии, а панель сообщает об '
      'отказе', (tester) async {
    final semantics = tester.ensureSemantics();
    await _DataSectionApp.open(
      tester,
      backups: Stream.value(const GraphBackupsReadFailed()),
    );
    expect(
      tester.getSemantics(find.text('Резервные копии')),
      isSemantics(
        label: 'Резервные копии',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.text('Резервные копии'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить копии'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('при отказе чтения состава строка «Резервные копии» без копий '
      'доступна с подписью «Пока нет копий»', (tester) async {
    await _DataSectionApp.open(
      tester,
      composition: Stream.value(const GraphCompositionReadFailed()),
    );

    await tester.tap(find.text('Пока нет копий'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });
}

var _nextBackupId = 0;

GraphBackupEntry _backup(DateTime madeAt) {
  final id = ++_nextBackupId;
  return GraphBackupEntry(
    id: GraphBackupId(id),
    kind: GraphBackupKind.daily,
    position: id,
    madeAt: madeAt,
    summary: const GraphChangeCounts(added: 1, changed: 0, deleted: 0),
  );
}

/// Раздел «Данные» над настоящим хранилищем графа в памяти: состав и копии
/// читает, а экспорт и копии пишет репозиторий. Документы — файлы временного
/// каталога, а чтение состава и копий можно заменить потоками [composition]
/// и [backups].
final class _DataSectionApp {
  _DataSectionApp._(
    this._repository,
    this._backups,
    this.documents,
    this.clock,
  );

  final DriftPersonalGraphRepository _repository;
  final GraphBackups _backups;
  final FileDocumentAccess documents;
  final _Clock clock;

  static Future<_DataSectionApp> open(
    WidgetTester tester, {
    String language = 'ru',
    Stream<GraphCompositionRead>? composition,
    Stream<GraphBackupsRead>? backups,
  }) async {
    final database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    addTearDown(database.close);
    final clock = _Clock();
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      clock.tick,
      InMemoryDiagnosticsSink(),
    );
    final directory = Directory.systemTemp.createTempSync(
      'doable_settings_data_section_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final documents = FileDocumentAccess(
      Directory('${directory.path}/documents')..createSync(),
    );
    final compaction = GraphLogCompaction(
      log: repository,
      directory: Directory('${directory.path}/graph_snapshots')..createSync(),
      clock: () => clock.now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    final graphBackups = GraphBackups(
      registry: repository,
      compaction: compaction,
      clock: () => clock.now,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    final export = GraphExport(
      documents: documents,
      compaction: compaction,
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
          graphBackupsProvider.overrideWithValue(graphBackups),
          graphBackupsClockProvider.overrideWithValue(() => clock.now),
          if (backups != null)
            graphBackupListProvider.overrideWith((ref) => backups),
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
    return _DataSectionApp._(repository, graphBackups, documents, clock);
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

  Future<void> makeManualBackup() async =>
      expect(await _backups.makeManualBackup(), ManualGraphBackupOutcome.made);
}

/// Часы устройства, которые проверка переводит вперёд. Каждая запись в
/// хранилище продвигает их на секунду, поэтому моменты записей различны.
final class _Clock {
  var now = DateTime(2026, 10, 18, 9);

  DateTime tick() => now = now.add(const Duration(seconds: 1));
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
