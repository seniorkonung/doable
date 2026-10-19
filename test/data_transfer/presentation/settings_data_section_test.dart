import 'dart:async';
import 'dart:io';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart' hide GraphBackups, Tag;
import 'package:doable/src/data_transfer/application/document_access.dart';
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
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_local_date.dart';
import '../../support/file_document_access.dart';
import '../../support/graph_import_files.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/temporary_graph_files.dart';

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

  testWidgets('после возвращения приложения в активное состояние с другой '
      'местной датой строка «Резервные копии» без новых копий называет '
      'вчерашней сегодняшнюю копию', (tester) async {
    final localDate = ControlledDailyChoiceLocalDate(
      CalendarDate.fromParts(2026, 10, 18),
    );
    final app = await _DataSectionApp.open(
      tester,
      localDate: localDate,
      backups: Stream.value(
        GraphBackupsReadSucceeded([_backup(DateTime(2026, 10, 18, 8, 15))]),
      ),
    );
    expect(find.text('Последняя копия сегодня в 08:15'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    app.clock.now = DateTime(2026, 10, 19, 7);
    localDate.today = CalendarDate.fromParts(2026, 10, 19);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Последняя копия вчера в 08:15'), findsOneWidget);
  });

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

  const restoreFailed = 'Не удалось восстановить копию. Ничего не изменено';
  const storageFull =
      'Недостаточно места на устройстве. Освободите место и повторите. '
      'Ничего не изменено';

  testWidgets('отказ восстановления копии показан под строкой «Резервные '
      'копии» без действия и прочитан экранным диктором, а после ухода со '
      'страницы общая поверхность его не повторяет', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await _RestoreApp.open(tester);
    app.storage.failsWith = sqlite.SqlError.SQLITE_IOERR;
    await app.chooseBackup();

    await tester.tap(find.text('Восстановить копию'));
    await _waitFor(
      tester,
      () => find.text(restoreFailed).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text(restoreFailed)),
      isSemantics(label: restoreFailed, isLiveRegion: true),
    );
    expect(find.text('Повторить'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text(restoreFailed), findsNothing);
    semantics.dispose();
  });

  testWidgets('отказ восстановления, который строка «Резервные копии» не '
      'успела показать, после ухода со страницы показывает общая '
      'поверхность', (tester) async {
    final app = await _RestoreApp.open(tester);
    app.storage.failsWith = sqlite.SqlError.SQLITE_IOERR;
    await app.chooseBackup();
    // Без фокуса ввода сообщение под строкой не считается показанным.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    await tester.tap(find.text('Восстановить копию'));
    await _waitFor(
      tester,
      () => find.text(restoreFailed).evaluate().isNotEmpty,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(restoreFailed),
      ),
      findsOneWidget,
    );
  });

  testWidgets('при нехватке места под строкой «Резервные копии» показано '
      'сообщение с «Повторить», которое снова открывает подтверждение '
      'восстановления той же копии с новым подсчётом изменений', (
    tester,
  ) async {
    final app = await _RestoreApp.open(tester);
    app.storage.failsWith = sqlite.SqlError.SQLITE_FULL;
    await app.chooseBackup();
    await tester.tap(find.text('Восстановить копию'));
    await _waitFor(tester, () => find.text(storageFull).evaluate().isNotEmpty);
    await tester.runAsync(() => app.createTag('Лес'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Повторить'));
    await app.waitForChangesSince();

    expect(
      find.text(
        'Она сделана сегодня в 09:00. С тех пор: 2 добавлено. '
        'Восстановление отменит всё это.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Восстановить копию'));
    await _waitFor(
      tester,
      () => find.text('Копия восстановлена').evaluate().isNotEmpty,
    );
    expect(find.text(storageFull), findsNothing);
    expect(await app.tagNames(), ['Дом']);
  });

  for (final (language, export, nothing, import, bringBack, replace) in [
    (
      'ru',
      'Экспорт данных',
      'Пока нечего экспортировать',
      'Импорт данных',
      'Вернуть копию из файла',
      'Заменить всё копией из файла',
    ),
    (
      'en',
      'Export data',
      'Nothing to export yet',
      'Import data',
      'Bring back a copy from a file',
      'Replace everything with a copy from a file',
    ),
  ]) {
    testWidgets('$language: сценарий «Пустой граф новой установки»: строка '
        '«Экспорт данных» недоступна, а строка «Импорт данных» стоит после '
        'неё, доступна и предлагает вернуть копию из файла, пока не появится '
        'первый тег', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _DataSectionApp.open(tester, language: language);

      expect(find.text(nothing), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(import)).dy,
        greaterThan(tester.getTopLeft(find.text(export)).dy),
      );
      expect(
        tester.getSemantics(find.text(import)),
        isSemantics(
          label: '$import\n$bringBack',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await app.createTag('Дом');
      await tester.pumpAndSettle();
      expect(find.text(bringBack), findsNothing);
      expect(find.text(replace), findsOneWidget);
      semantics.dispose();
    });
  }

  for (final (state, read) in [
    ('пока состав графа не прочитан', null),
    ('после отказа чтения состава графа', const GraphCompositionReadFailed()),
  ]) {
    testWidgets('$state строка «Импорт данных» доступна и предлагает '
        'заменить всё копией из файла', (tester) async {
      final semantics = tester.ensureSemantics();
      final composition = StreamController<GraphCompositionRead>();
      addTearDown(composition.close);
      if (read != null) composition.add(read);
      await _DataSectionApp.open(tester, composition: composition.stream);

      expect(
        tester.getSemantics(find.text('Импорт данных')),
        isSemantics(
          label: 'Импорт данных\nЗаменить всё копией из файла',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });
  }

  testWidgets('пока идёт экспорт, строка «Импорт данных» доступна и '
      'начинает импорт: открывает диалог выбора, а выбранный файл ждёт '
      'подтверждения замены непустого графа', (tester) async {
    final app = await _ImportApp.open(tester);
    final writeReached = Completer<void>();
    final releaseWrite = Completer<void>();
    app.documents.beforeWrite = () {
      writeReached.complete();
      return releaseWrite.future;
    };
    await tester.tap(find.text('Экспорт данных'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить в файл'));
    await _waitFor(tester, () => writeReached.isCompleted);
    await tester.pumpAndSettle();
    expect(find.text('Сохраняется в файл…'), findsOneWidget);
    app.choose(graphExportFileOf(referenceGraphFileLines()));

    await tester.tap(find.text('Импорт данных'));
    await _waitFor(
      tester,
      () => find.text('Импортировать эту копию?').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(app.openings, 1);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    releaseWrite.complete();
    await _waitFor(
      tester,
      () => find.text('Данные сохранены в файл').evaluate().isNotEmpty,
    );
  });

  const invalidFile =
      'Не удалось импортировать файл. Это не экспорт Doable, или он '
      'повреждён. Ничего не изменено';
  const chooseAnotherFile = 'Выбрать другой файл';
  const retry = 'Повторить';

  for (final (cause, arrange, message, action)
      in <(String, void Function(_ImportApp app), String, String?)>[
        (
          'выбран не экспорт Doable',
          (app) => app.choose(photoFile()),
          invalidFile,
          chooseAnotherFile,
        ),
        (
          'выбран файл более новой версии',
          (app) => app.choose(newerFormatVersionFile()),
          'Файл создан более новой версией Doable. Обновите приложение, '
              'чтобы импортировать его. Ничего не изменено',
          null,
        ),
        (
          'копии файла не хватило места',
          (app) => app
            ..choose(graphExportFileOf(referenceGraphFileLines()))
            ..documents.copyFailure = const DocumentCopyStorageFull(),
          storageFull,
          retry,
        ),
        (
          'файл не прочитан',
          (app) => app
            ..choose(graphExportFileOf(referenceGraphFileLines()))
            ..documents.copyFailure = const DocumentNotRead(),
          'Не удалось прочитать файл. Проверьте доступ к нему и повторите. '
              'Ничего не изменено',
          retry,
        ),
        (
          'копия файла не записана по неизвестной причине',
          (app) => app
            ..choose(graphExportFileOf(referenceGraphFileLines()))
            ..documents.copyFailure = const DocumentCopyFailed(),
          'Не удалось импортировать данные. Ничего не изменено',
          null,
        ),
      ]) {
    testWidgets('$cause: под строкой «Импорт данных» показан отказ, который '
        'читает экранный диктор, ${switch (action) {
          null => 'без действия',
          final action => 'с действием «$action»',
        }}', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _ImportApp.open(tester);
      arrange(app);

      await tester.tap(find.text('Импорт данных'));
      await _waitFor(tester, () => find.text(message).evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester.getTopLeft(find.text(message)).dy,
        greaterThan(tester.getTopLeft(find.text('Импорт данных')).dy),
      );
      expect(
        tester.getSemantics(find.text(message)),
        isSemantics(label: message, isLiveRegion: true),
      );
      for (final label in [chooseAnotherFile, retry]) {
        if (label == action) {
          expect(
            tester.getSemantics(find.text(label)),
            isSemantics(label: label, isButton: true, hasTapAction: true),
          );
        } else {
          expect(find.text(label), findsNothing);
        }
      }
      semantics.dispose();
    });
  }

  testWidgets('en: отказ импорта чужого файла под строкой «Import data» '
      'предлагает выбрать другой файл', (tester) async {
    final app = await _ImportApp.open(tester, language: 'en');
    app.choose(photoFile());

    await tester.tap(find.text('Import data'));
    const message =
        'Couldn’t import the file. It isn’t a Doable export, or it’s '
        'damaged. Nothing was changed';
    await _waitFor(tester, () => find.text(message).evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    expect(find.text('Choose another file'), findsOneWidget);
  });

  testWidgets('«Выбрать другой файл» один раз снова открывает диалог выбора '
      'и убирает прежний отказ', (tester) async {
    final app = await _ImportApp.open(tester);
    app.choose(photoFile());
    await tester.tap(find.text('Импорт данных'));
    await _waitFor(tester, () => find.text(invalidFile).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    app.choose(graphExportFileOf(referenceGraphFileLines()));

    await tester.tap(find.text(chooseAnotherFile));
    await _waitFor(
      tester,
      () => find.text('Импортировать эту копию?').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(app.openings, 2);
    expect(find.text(invalidFile), findsNothing);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
  });

  testWidgets('отказ импорта, показанный под строкой «Импорт данных», после '
      'ухода со страницы общая поверхность не повторяет', (tester) async {
    final app = await _ImportApp.open(tester);
    app.choose(photoFile());
    await tester.tap(find.text('Импорт данных'));
    await _waitFor(tester, () => find.text(invalidFile).evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text(invalidFile), findsNothing);
  });

  testWidgets('отказ импорта, который строка «Импорт данных» не успела '
      'показать, после ухода со страницы показывает общая поверхность', (
    tester,
  ) async {
    final app = await _ImportApp.open(tester);
    app.choose(photoFile());
    // Без фокуса ввода сообщение под строкой не считается показанным.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    await tester.tap(find.text('Импорт данных'));
    await _waitFor(tester, () => find.text(invalidFile).evaluate().isNotEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(invalidFile),
      ),
      findsOneWidget,
    );
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
/// и [backups]. Местную дату можно задать управляемым источником
/// [localDate].
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
    ControlledDailyChoiceLocalDate? localDate,
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
          ?localDate?.override,
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

/// Приложение новой установки на странице «Настройки» с одной ежедневной
/// копией с тегом «Дом», после которой создан тег «Сад». Часы остановлены
/// 7 октября 2026 года в 09:00, а замену графа может отклонить [storage].
final class _RestoreApp {
  _RestoreApp._(this._tester, this._container, this.storage);

  final WidgetTester _tester;
  final ProviderContainer _container;
  final _ReplacementFailure storage;

  static Future<_RestoreApp> open(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [const Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final storage = _ReplacementFailure();
    final files = TemporaryGraphFiles();
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        storage,
      ),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: files.create,
      clock: () => DateTime(2026, 10, 7, 9).toUtc(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      // Выключение дожидается работы, начатой в кадрах проверки, например
      // проверки ежедневной копии при возвращении в приложение, поэтому
      // продолжается и в реальном ожидании, и в кадрах.
      var isShutDown = false;
      unawaited(runtime.shutdown().whenComplete(() => isShutDown = true));
      await _waitFor(tester, () => isShutDown);
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    final app = _RestoreApp._(tester, ready.container, storage);
    await tester.runAsync(() async {
      await app.createTag('Дом');
      // Проверка при запуске могла сделать ежедневную копию уже с тегом, и
      // тогда второй копии за день не будет.
      await ready.container.read(graphBackupsProvider).makeDailyBackupIfDue();
      await app.createTag('Сад');
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await _waitFor(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
    await _waitFor(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await _waitFor(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> createTag(String name) async => expect(
    await _container
        .read(personalGraphRepositoryProvider)
        .execute(CreateTag(TagName.fromInput(name))),
    isA<GraphCommandSucceeded>(),
  );

  /// Открывает строкой «Резервные копии» панель копий и выбирает копию.
  Future<void> chooseBackup() async {
    await _tester.tap(find.text('Резервные копии'));
    await _waitFor(
      _tester,
      () => find.text('Сегодня, 09:00').evaluate().isNotEmpty,
    );
    await _tester.pumpAndSettle();
    await _tester.tap(find.text('Сегодня, 09:00'));
    await waitForChangesSince();
  }

  /// Ждёт, пока подтверждение восстановления посчитает изменения с тех пор.
  Future<void> waitForChangesSince() async {
    await _waitFor(
      _tester,
      () => find.textContaining('С тех пор').evaluate().isNotEmpty,
    );
    await _tester.pumpAndSettle();
  }

  /// Названия тегов графа в порядке создания.
  Future<List<String>> tagNames() async {
    final catalog = await _tester.runAsync(
      () => _container
          .read(personalGraphRepositoryProvider)
          .getTagCatalog(const TagCatalogBrowseMode()),
    );
    return [
      for (final tag in (catalog! as TagCatalogSuccess).value.items)
        tag.name.value,
    ];
  }
}

/// Приложение новой установки с тегом «Дом» на языке [language], открытое
/// на странице «Настройки». Файл, который человек выбирает в диалоге
/// выбора, задаёт [choose].
final class _ImportApp {
  _ImportApp._(this.documents, this._chosen);

  /// Документы, копирование и запись которых проверка может изменить.
  final FileDocumentAccess documents;
  final File _chosen;

  /// Сколько раз открывался диалог выбора файла.
  var openings = 0;

  static Future<_ImportApp> open(
    WidgetTester tester, {
    String language = 'ru',
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [Locale(language)];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final chosenDirectory = Directory.systemTemp.createTempSync(
      'doable_import_row_',
    );
    addTearDown(() => chosenDirectory.deleteSync(recursive: true));
    final files = TemporaryGraphFiles();
    final runtime = AppRuntime(
      connectionFactory: openInMemoryLocalDatabase,
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: files.create,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      var isShutDown = false;
      unawaited(runtime.shutdown().whenComplete(() => isShutDown = true));
      await _waitFor(tester, () => isShutDown);
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    await tester.runAsync(() async {
      expect(
        await ready.container
            .read(personalGraphRepositoryProvider)
            .execute(CreateTag(TagName.fromInput('Дом'))),
        isA<GraphCommandSucceeded>(),
      );
    });
    final app = _ImportApp._(
      files.documents,
      File.fromUri(chosenDirectory.uri.resolve('chosen.jsonl.gz')),
    );
    files.documents.openingDialog = () async {
      app.openings++;
      return files.documents.chosen(app._chosen);
    };
    await tester.pumpWidget(MainApp(runtime: runtime));
    await _waitFor(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
    await _waitFor(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip(switch (language) {
        'en' => 'Settings',
        _ => 'Настройки',
      }),
    );
    await _waitFor(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    return app;
  }

  /// Человек выбирает в диалоге выбора файл с байтами [bytes].
  void choose(List<int> bytes) => _chosen.writeAsBytesSync(bytes);
}

/// Отклоняет отказом хранилища с кодом [failsWith] первый оператор удаления
/// прежнего графа следующей замены графа; последующие замены не трогает.
final class _ReplacementFailure extends LocalDatabaseConnectionObserver {
  int? failsWith;

  @override
  FutureOr<void> beforeStatement(LocalDatabaseSqlStatement statement) {
    final code = failsWith;
    if (code == null ||
        !statement.statements.any(
          (sql) => sql.startsWith('DELETE FROM daily_choices '),
        )) {
      return null;
    }
    failsWith = null;
    throw sqlite.SqliteException(
      extendedResultCode: code,
      message: 'injected storage failure',
    );
  }
}

/// Чередует реальное ожидание хранилища и изолята записи снимка с кадрами,
/// пока не выполнится [done].
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}
