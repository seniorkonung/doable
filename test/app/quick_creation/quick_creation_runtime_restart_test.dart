import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/quick_creation/file_quick_creation_mode_store.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';
import 'controlled_mode_io.dart';

void main() {
  late Directory directory;
  late File modeFile;
  late _Diagnostics diagnostics;

  _ObservedStore store({ControlledModeIo? io}) => _ObservedStore(
    FileQuickCreationModeStore(
      localDataDirectory: directory,
      diagnosticsSink: diagnostics,
    ),
    io: io,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('doable_ui_режимы ');
    modeFile = File.fromUri(
      directory.uri.resolve('settings/quick_creation_mode'),
    );
    diagnostics = _Diagnostics();
  });
  tearDown(() => directory.delete(recursive: true));

  // Соответствие ключа режиму одинаково для всех режимов, а запуск каждого
  // режима проверяет тест запускателя.
  for (final mode in <QuickCreationMode?>[null, QuickCreationMode.relation]) {
    final title =
        mode?.title(lookupAppLocalizations(const Locale('ru'))) ??
        'Первый запуск';
    testWidgets('$title: свежий runtime '
        'открывает Главную и запускает сохранённый режим кнопкой', (
      tester,
    ) async {
      final firstStore = store();
      final first = await _mount(tester, firstStore, diagnostics);
      _expectHome(tester, first, QuickCreationMode.intention);
      await tester.tap(appNavigationDestination(AppDestination.intentionGraph));
      await _settle(tester);
      if (mode != null) {
        await _choose(tester, mode);
        expect(
          await _complete(tester, firstStore.writes.single),
          isA<QuickCreationModeSaved>(),
        );
        expect(await tester.runAsync(modeFile.readAsString), mode.storageKey);
      } else {
        expect(await tester.runAsync(modeFile.exists), isFalse);
      }
      _expectSelected(tester, AppDestination.intentionGraph);
      await _close(tester, first);

      final second = await _mount(tester, store(), diagnostics);
      final restored = mode ?? QuickCreationMode.intention;
      _expectHome(tester, second, restored);
      await _expectLaunch(tester, second, restored);
      expect(diagnostics.failures, isEmpty);
    });
  }

  for (final unreadable in [false, true]) {
    testWidgets('${unreadable ? 'отказ чтения' : 'неизвестный ключ'}: '
        'Главная и создание доступны без сообщения об ошибке', (tester) async {
      await tester.runAsync(() async {
        if (unreadable) {
          await Directory(modeFile.path).create(recursive: true);
        } else {
          await modeFile.parent.create();
          await modeFile.writeAsString('Секретное содержимое настройки');
        }
      });
      final session = await _mount(tester, store(), diagnostics);
      _expectHome(tester, session, QuickCreationMode.intention);
      _expectFailures(diagnostics, 'read', [
        unreadable ? 'unavailable' : 'corruption',
      ]);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await _expectLaunch(tester, session, QuickCreationMode.intention);
    });
  }

  // Остальные сочетания исходов и точек отказа идут теми же ветвями, их
  // подробно проверяет тест хранилища.
  for (final (step, outcomes) in [
    (ModeWriteStep.write, 'sf'),
    (ModeWriteStep.rename, 'ffs'),
  ]) {
    testWidgets('${step.label}, $outcomes: все панели и меню сразу '
        'показывают последний выбор; свежий runtime получает последний успех', (
      tester,
    ) async {
      const initial = QuickCreationMode.dailyChoiceFromIntention;
      const a = QuickCreationMode.relation;
      const b = QuickCreationMode.dailyChoiceFromAction;
      await tester.runAsync(() => store().save(initial));
      final modes = [a, b, if (outcomes.length == 3) a];
      final attempts = [
        for (var i = 0; i < modes.length; i++)
          ModeWriteAttempt(
            holdAt: step,
            failAt: outcomes[i] == 'f' ? step : null,
          ),
      ];
      final io = ControlledModeIo(modeFile, attempts);
      final observed = store(io: io);
      diagnostics.throwsOnMode = outcomes == 'ffs';
      final first = await _mount(tester, observed, diagnostics);
      addTearDown(() async {
        for (final attempt in attempts) {
          if (!attempt.release.isCompleted) attempt.release.complete();
        }
        for (final writing in observed.writes) {
          await _complete(tester, writing);
        }
      });
      await tester.tap(appNavigationDestination(AppDestination.intentionGraph));
      await _settle(tester);
      await _choose(tester, a);
      await _complete(tester, attempts.first.held.future);

      // Второй экземпляр панели принадлежит обычному просмотру тегов.
      await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
      await _settle(tester);
      for (final mode in modes.skip(1)) {
        await _choose(tester, mode);
        _expectVisiblePanel(tester, mode);
        // Скрытый Consumer приостанавливается вместе с маршрутом.
        // Проверяем обе панели при показе, пока запись всё ещё удержана.
        await tester.binding.handlePopRoute();
        await _settle(tester);
        _expectVisiblePanel(tester, mode);
        await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
        await _settle(tester);
        _expectVisiblePanel(tester, mode);
      }
      expect(await tester.runAsync(modeFile.readAsString), initial.storageKey);
      await _openMenu(tester);
      final localizations = AppLocalizations.of(
        tester.element(find.byType(BottomSheet)),
      );
      final selected = find.widgetWithText(
        ListTile,
        modes.last.title(localizations),
      );
      expect(
        find.descendant(of: selected, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );

      var expected = initial;
      for (var i = 0; i < attempts.length; i++) {
        attempts[i].release.complete();
        final result = await _complete(tester, observed.writes[i]);
        if (outcomes[i] == 's') {
          expect(result, isA<QuickCreationModeSaved>());
          expected = modes[i];
        } else {
          expect(result, isA<QuickCreationModeSaveFailed>());
        }
        if (i + 1 < attempts.length) {
          await _complete(tester, attempts[i + 1].held.future);
        }
        await tester.pump();
        expect(
          await tester.runAsync(modeFile.readAsString),
          expected.storageKey,
        );
        _expectVisiblePanel(tester, modes.last);
        expect(
          find.descendant(of: selected, matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      }
      _expectFailures(diagnostics, 'write', [
        for (final outcome in outcomes.split(''))
          if (outcome == 'f') 'unavailable',
      ]);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      _expectSelected(tester, AppDestination.intentionGraph);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      _expectVisiblePanel(tester, modes.last);
      await _close(tester, first);

      final restored = await _mount(tester, store(), diagnostics);
      _expectHome(tester, restored, expected);
      await _expectLaunch(tester, restored, expected);
    });
  }
}

void _expectVisiblePanel(WidgetTester tester, QuickCreationMode mode) {
  final button = find.byType(QuickCreationButton);
  expect(button, findsOneWidget);
  expect(
    find.descendant(of: button, matching: find.byIcon(mode.icon)),
    findsOneWidget,
  );
}

/// Панель показывает выбранным пункт [destination]: залитый значок у него.
void _expectSelected(WidgetTester tester, AppDestination destination) {
  for (final item in AppDestination.values) {
    expect(
      find.descendant(
        of: appNavigationDestination(item),
        matching: find.byIcon(
          item == destination ? item.selectedIcon : item.icon,
        ),
      ),
      findsOneWidget,
      reason: item.name,
    );
  }
}

Future<_Session> _mount(
  WidgetTester tester,
  _ObservedStore store,
  _Diagnostics diagnostics,
) async {
  tester.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final runtime = AppRuntime(
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: diagnostics,
    quickCreationModeStore: store,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.shutdown);
  });
  await tester.runAsync(runtime.bootstrap);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _settle(tester);
  return _Session(runtime);
}

Future<void> _close(WidgetTester tester, _Session session) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(session.runtime.shutdown);
}

Future<T> _complete<T>(WidgetTester tester, Future<T> future) async {
  final completed = Completer<T>();
  unawaited(future.then(completed.complete, onError: completed.completeError));
  for (var i = 0; i < 200 && !completed.isCompleted; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(
    completed.isCompleted,
    isTrue,
    reason: 'Операция IO должна завершиться',
  );
  return completed.future;
}

/// Даёт реальным файловым операциям и чтениям графа закончиться до анимаций.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (!tester.binding.hasScheduledFrame &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  throw StateError('Чтение или анимация приложения не завершились.');
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.longPress(find.byType(QuickCreationButton));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
}

Future<void> _choose(WidgetTester tester, QuickCreationMode mode) async {
  final localizations = AppLocalizations.of(
    tester.element(find.byType(QuickCreationButton)),
  );
  await _openMenu(tester);
  await tester.tap(find.widgetWithText(ListTile, mode.title(localizations)));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsNothing);
  expect(
    find.descendant(
      of: find.byType(QuickCreationButton),
      matching: find.byIcon(mode.icon),
    ),
    findsOneWidget,
  );
}

void _expectHome(
  WidgetTester tester,
  _Session session,
  QuickCreationMode mode,
) {
  expect(find.byType(HomePage), findsOneWidget);
  _expectSelected(tester, AppDestination.home);
  final button = find.byType(QuickCreationButton);
  expect(button.hitTestable(), findsOneWidget);
  expect(
    find.descendant(of: button, matching: find.byIcon(mode.icon)),
    findsOneWidget,
  );
  expect(find.byType(SnackBar), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _expectLaunch(
  WidgetTester tester,
  _Session session,
  QuickCreationMode mode,
) async {
  await tester.tap(find.byType(QuickCreationButton));
  await _settle(tester);
  expect(
    find.byType(switch (mode) {
      QuickCreationMode.intention => IntentionEditorPage,
      QuickCreationMode.relation => RelationEditorPage,
      QuickCreationMode.dailyChoiceFromIntention => DailyChoiceSourcePickerPage,
      QuickCreationMode.dailyChoiceFromAction => DailyChoiceActionPickerPage,
    }),
    findsOneWidget,
  );
  expect(find.byType(SnackBar), findsNothing);
  expect(tester.takeException(), isNull);
}

void _expectFailures(
  _Diagnostics diagnostics,
  String stage,
  List<String> codes,
) {
  expect(diagnostics.failures, [
    for (final code in codes)
      {
        'operation': 'quickCreationMode',
        'stage': stage,
        'outcome': 'failed',
        'failureCode': code,
      },
  ]);
}

final class _Session {
  _Session(this.runtime);
  final AppRuntime runtime;
}

/// Наблюдает исходы реального адаптера, сохраняя его очередь и файловые операции.
final class _ObservedStore implements QuickCreationModeStore {
  _ObservedStore(this.delegate, {this.io});
  final FileQuickCreationModeStore delegate;
  final ControlledModeIo? io;
  final writes = <Future<QuickCreationModeSaveResult>>[];
  @override
  Future<QuickCreationMode> read() => delegate.read();
  @override
  Future<QuickCreationModeSaveResult> save(QuickCreationMode mode) {
    final saving = switch (io) {
      null => delegate.save(mode),
      final overrides => overrides.run(() => delegate.save(mode)),
    };
    writes.add(saving);
    return saving;
  }
}

final class _Diagnostics implements DiagnosticsSink {
  final failures = <Map<String, dynamic>>[];
  bool throwsOnMode = false;
  @override
  void record(DiagnosticsEvent event) {
    if (event is! QuickCreationModeDiagnosticsEvent) return;
    DeveloperDiagnosticsSink((payload) {
      final encoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(encoded.remove('durationMicros'), isA<int>());
      failures.add(encoded);
    }).record(event);
    if (throwsOnMode) throw StateError('Отказ получателя диагностики');
  }
}
