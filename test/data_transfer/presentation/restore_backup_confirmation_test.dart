import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data_transfer/application/graph_restore.dart';
import 'package:doable/src/data_transfer/presentation/restore_backup_confirmation.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Текущий момент проверок подтверждения: 7 октября 2026 года, полдень.
final _now = DateTime(2026, 10, 7, 12);

void main() {
  for (final (language, title, replaces, cancel, confirm, facts) in [
    (
      'ru',
      'Восстановить эту копию?',
      'Она заменит всё, что сейчас есть в Doable. Сначала текущее состояние '
          'сохраняется как резервная копия.',
      'Отмена',
      'Восстановить копию',
      [
        'Она сделана сегодня в 08:15. С тех пор: 2 добавлено, 1 изменено. '
            'Восстановление отменит всё это.',
        'Она сделана вчера в 21:40. С тех пор ничего не изменилось.',
        'Она сделана 5 октября 2026 в 09:05. С тех пор данные заменялись. '
            'Восстановление отменит все изменения.',
        'Она сделана 3 октября 2025 в 10:00.',
      ],
    ),
    (
      'en',
      'Restore this copy?',
      'It will replace everything now in Doable. A backup of the current '
          'state is made first.',
      'Cancel',
      'Restore copy',
      [
        'It was made today at 8:15 AM. Since then: 2 added, 1 changed. '
            'Restoring undoes all of it.',
        'It was made yesterday at 9:40 PM. Nothing has changed since '
            'then.',
        'It was made on 5 October 2026 at 9:05 AM. The data has been '
            'replaced since then. Restoring undoes every change.',
        'It was made on 3 October 2025 at 10:00 AM.',
      ],
    ),
  ]) {
    testWidgets('$language: подтверждение называет, когда сделана копия, что '
        'с тех пор изменилось или что изменения не посчитаны, и что '
        'восстановление заменит всё', (tester) async {
      final cases = [
        (
          DateTime(2026, 10, 7, 8, 15),
          const GraphChangesSinceBackupCounted(
            GraphChangeCounts(added: 2, changed: 1, deleted: 0),
          ),
        ),
        (
          DateTime(2026, 10, 6, 21, 40),
          const GraphChangesSinceBackupCounted(
            GraphChangeCounts(added: 0, changed: 0, deleted: 0),
          ),
        ),
        (
          DateTime(2026, 10, 5, 9, 5),
          const GraphChangesSinceBackupCounted(GraphDataReplaced()),
        ),
        (DateTime(2025, 10, 3, 10), const GraphChangesSinceBackupUncounted()),
      ];

      for (final (index, (madeAt, changesSince)) in cases.indexed) {
        await _openConfirmation(
          tester,
          language: language,
          backup: _backup(madeAt),
          changesSince: Future.value(changesSince),
        );

        expect(_dialogTexts(tester), [
          title,
          facts[index],
          replaces,
          cancel,
          confirm,
        ]);
        await tester.tap(find.text(cancel));
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('пока изменения с тех пор считаются, подтверждение называет '
      'только момент копии, а «Восстановить копию» недоступно', (tester) async {
    final counting = Completer<GraphChangesSinceBackup>();
    await _openConfirmation(
      tester,
      backup: _backup(DateTime(2026, 10, 7, 8, 15)),
      changesSince: counting.future,
    );

    expect(find.text('Она сделана сегодня в 08:15.'), findsOneWidget);
    expect(_restoreButton(tester).onPressed, isNull);

    counting.complete(
      const GraphChangesSinceBackupCounted(
        GraphChangeCounts(added: 1, changed: 0, deleted: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Она сделана сегодня в 08:15. С тех пор: 1 добавлено. '
        'Восстановление отменит всё это.',
      ),
      findsOneWidget,
    );
    expect(_restoreButton(tester).onPressed, isNotNull);
  });

  testWidgets('если изменения с тех пор не посчитаны, «Восстановить копию» '
      'доступно и подтверждает восстановление', (tester) async {
    final confirmation = await _openConfirmation(
      tester,
      backup: _backup(DateTime(2026, 10, 7, 8, 15)),
      changesSince: Future.value(const GraphChangesSinceBackupUncounted()),
    );

    await tester.tap(find.text('Восстановить копию'));
    await tester.pumpAndSettle();

    expect(await confirmation, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('экранный диктор называет подтверждение и читает его текст и '
      'доступные действия', (tester) async {
    final semantics = tester.ensureSemantics();
    const facts =
        'Она сделана сегодня в 08:15. С тех пор: 2 добавлено, 1 изменено. '
        'Восстановление отменит всё это.';
    const replaces =
        'Она заменит всё, что сейчас есть в Doable. Сначала текущее '
        'состояние сохраняется как резервная копия.';
    await _openConfirmation(
      tester,
      backup: _backup(DateTime(2026, 10, 7, 8, 15)),
      changesSince: Future.value(
        const GraphChangesSinceBackupCounted(
          GraphChangeCounts(added: 2, changed: 1, deleted: 0),
        ),
      ),
    );

    final routeName = find.semantics.byFlag(SemanticsFlag.namesRoute);
    expect(routeName, findsOne);
    expect(
      routeName.evaluate().single,
      isSemantics(
        label: 'Восстановить эту копию?',
        scopesRoute: true,
        namesRoute: true,
      ),
    );
    for (final text in [facts, replaces]) {
      expect(tester.getSemantics(find.text(text)), isSemantics(label: text));
    }
    for (final action in ['Отмена', 'Восстановить копию']) {
      expect(
        tester.getSemantics(find.text(action)),
        isSemantics(
          label: action,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    }
    semantics.dispose();
  });
}

GraphBackupEntry _backup(DateTime madeAt) => GraphBackupEntry(
  id: const GraphBackupId(1),
  kind: GraphBackupKind.daily,
  position: 1,
  madeAt: madeAt,
  summary: const GraphChangeCounts(added: 1, changed: 0, deleted: 0),
);

/// Тексты открытого подтверждения сверху вниз.
List<String?> _dialogTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .toList();

FilledButton _restoreButton(WidgetTester tester) =>
    tester.widget(find.widgetWithText(FilledButton, 'Восстановить копию'));

/// Открывает над страницей подтверждение восстановления копии [backup] в
/// момент [_now] и возвращает его исход.
Future<Future<bool>> _openConfirmation(
  WidgetTester tester, {
  required GraphBackupEntry backup,
  required Future<GraphChangesSinceBackup> changesSince,
  String language = 'ru',
}) async {
  late Future<bool> confirmation;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [graphBackupsClockProvider.overrideWithValue(() => _now)],
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: doableTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => confirmation = confirmBackupRestore(
                  context,
                  backup: backup,
                  changesSince: changesSince,
                ),
                child: const Text('Открыть подтверждение'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть подтверждение'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  return confirmation;
}
