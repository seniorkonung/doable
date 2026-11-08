import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/l10n/app_localizations_ru.dart';
import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action.dart' as action_domain;
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/presentation/relation_command_failure_message.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';
import '../../support/intention_cascade_execution.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final (count, suffix) in [
    (1, '1 вспомогательным'),
    (2, '2 вспомогательными'),
    (5, '5 вспомогательными'),
    (21, '21 вспомогательным'),
  ]) {
    testWidgets('число вспомогательных согласуется: $count', (tester) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final accepted = harness.startArchive();
      harness.completeIntentionCascade(
        accepted,
        ArchiveCascadeComposition(
          departing: [
            for (var i = 0; i < count; i++) testDetailsIntentionId(i + 2),
          ],
          promoted: [],

          archivedRelationCount: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Архивирование — «Намерение»: В архиве вместе с $suffix'),
        findsOneWidget,
      );
    });
  }

  testWidgets('архивирование связи объявляет превращение в главное', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final accepted = harness.startRelationArchive();
    harness.completeRelationArchived(
      accepted,
      composition: ArchiveCascadeComposition(
        departing: [],
        promoted: [testDetailsIntentionId(2)],

        archivedRelationCount: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Архивирование — «связь»: Связь в архиве, намерение стало главным',
      ),
      findsOneWidget,
    );
  });

  testWidgets('удаление объявляет каскад и архивирование одним сообщением', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final accepted = harness.startDelete(index: 1, title: 'Намерение');
    harness.completeDeleted(
      accepted,
      composition: DeleteCascadeComposition(
        departing: [testDetailsIntentionId(2)],
        promoted: [],
        archivedByInvariant: [
          testDetailsIntentionId(3),
          testDetailsIntentionId(4),
        ],
        mainsLosingRelation: [],
        deletedRelationCount: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Удаление — «Намерение»: Намерение удалено вместе с 1 вспомогательным; в архив ушли 2 намерения',
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  for (final (count, suffix) in [
    (1, 'ушло 1 намерение'),
    (2, 'ушли 2 намерения'),
    (5, 'ушли 5 намерений'),
  ]) {
    testWidgets('удаление намерения с архивированием: $count', (tester) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
        alteredDeletionPunctuation: true,
      );
      final accepted = harness.startDelete(index: 1, title: 'Намерение');
      harness.completeDeleted(
        accepted,
        composition: DeleteCascadeComposition(
          departing: [],
          promoted: [],
          archivedByInvariant: [
            for (var i = 0; i < count; i++) testDetailsIntentionId(i + 2),
          ],
          mainsLosingRelation: [],
          deletedRelationCount: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Удаление — «Намерение»: Намерение удалено; в архив $suffix'),
        findsOneWidget,
      );
    });
  }

  testWidgets('удаление связи с архивированием не зависит от другой строки', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(
      tester,
      locale: const Locale('ru'),
      alteredDeletionPunctuation: true,
    );
    final accepted = harness.startRelationDelete();
    harness.completeRelationDeleted(
      accepted,
      composition: DeleteCascadeComposition(
        departing: [],
        promoted: [],
        archivedByInvariant: [testDetailsIntentionId(3)],
        mainsLosingRelation: [],
        deletedRelationCount: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Удаление — «связь»: Связь удалена; в архив ушло 1 намерение'),
      findsOneWidget,
    );
  });

  testWidgets('удаление связи объявляет оставленное главным намерение', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final accepted = harness.startRelationDelete();
    harness.completeRelationDeleted(
      accepted,
      composition: DeleteCascadeComposition(
        departing: [],
        promoted: [testDetailsIntentionId(2)],
        archivedByInvariant: [],
        mainsLosingRelation: [],
        deletedRelationCount: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Удаление — «связь»: Связь удалена, намерение стало главным'),
      findsOneWidget,
    );
  });

  testWidgets('восстановление связи объявляет вернувшееся главным намерение', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final accepted = harness.startRelationRestore();
    harness.completeRelationRestored(
      accepted,
      composition: RestoreCascadeComposition(
        restored: [testDetailsIntentionId(1)],
        returnedAsMain: testDetailsIntentionId(1),
        restoredRelationCount: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Восстановление — «связь»: Связь восстановлена, намерение вернулось главным',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'восстановление намерения главным с каскадом объявляет оба результата',
    (tester) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final accepted = harness.startRestore();
      harness.completeIntentionCascade(
        accepted,
        RestoreCascadeComposition(
          restored: [testDetailsIntentionId(2)],
          returnedAsMain: testDetailsIntentionId(1),
          restoredRelationCount: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Восстановление — «Намерение»: Восстановлено как главное вместе с 1 вспомогательным',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('архивирование без других намерений не показывает сообщение', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final accepted = harness.startArchive();
    harness.completeIntentionCascade(
      accepted,
      ArchiveCascadeComposition(
        departing: [],
        promoted: [],

        archivedRelationCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final (count, promoted, archived) in [
    (1, '1 намерение стало главным', 'ушло 1 намерение'),
    (2, '2 намерения стали главными', 'ушли 2 намерения'),
    (5, '5 намерений стали главными', 'ушли 5 намерений'),
    (21, '21 намерение стало главным', 'ушло 21 намерение'),
  ]) {
    testWidgets('числа ставших главными и архивированных согласуются: $count', (
      tester,
    ) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final accepted = harness.startDelete(index: 1, title: 'Намерение');
      harness.completeDeleted(
        accepted,
        composition: DeleteCascadeComposition(
          departing: [],
          promoted: [
            for (var i = 0; i < count; i++) testDetailsIntentionId(i + 2),
          ],
          archivedByInvariant: [
            for (var i = 0; i < count; i++) testDetailsIntentionId(i + 100),
          ],
          mainsLosingRelation: [],
          deletedRelationCount: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Удаление — «Намерение»: Намерение удалено, $promoted; в архив $archived',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('восстановление связи считает все возвращённые намерения', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final accepted = harness.startRelationRestore();
    harness.completeRelationRestored(
      accepted,
      composition: RestoreCascadeComposition(
        restored: [testDetailsIntentionId(1), testDetailsIntentionId(2)],
        returnedAsMain: testDetailsIntentionId(1),
        restoredRelationCount: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Восстановление — «связь»: Связь восстановлена вместе с 2 намерениями, одно из них главным',
      ),
      findsOneWidget,
    );
  });

  testWidgets('сообщение каскада локализуется на английский', (tester) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('en'));
    final accepted = harness.startArchive();
    harness.completeIntentionCascade(
      accepted,
      ArchiveCascadeComposition(
        departing: [testDetailsIntentionId(2)],
        promoted: [],

        archivedRelationCount: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Archive — “Намерение”: Archived with 1 supporting intention'),
      findsOneWidget,
    );
  });

  testWidgets(
    'поздний результат ждёт закрытия текущего сообщения без вытеснения',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final first = harness.startDelete(index: 1, title: 'Первое');
      final second = harness.startDelete(index: 2, title: 'Второе');
      harness.completeDeleted(first);
      harness.completeDeleted(second);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Первое')), findsOneWidget);
      expect(find.text(_deleted('Второе')), findsNothing);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: _deleted('Первое'),
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );

      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_deleted('Первое')), findsOneWidget);
      expect(find.text(_deleted('Второе')), findsNothing);

      await _closeMessage(tester);
      expect(find.text(_deleted('Первое')), findsNothing);
      expect(find.text(_deleted('Второе')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'серия успехов объединяется с доступным счётчиком и прежним сроком, ${locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(tester, locale: locale);
        final current = harness.startDelete(index: 1, title: 'Текущее');
        harness.completeDeleted(current);
        await tester.pumpAndSettle();
        final currentMessage = locale.languageCode == 'ru'
            ? 'Удаление — «Текущее»: Намерение удалено.'
            : _deleted('Текущее');

        for (var index = 2; index <= 6; index += 1) {
          final success = harness.startDelete(
            index: index,
            title: 'Намерение $index',
          );
          harness.completeDeleted(success);
        }
        await tester.pumpAndSettle();
        expect(find.text(currentMessage), findsOneWidget);

        await _closeMessage(tester);
        final message = locale.languageCode == 'ru'
            ? 'Удаление — «Намерение 6»: Намерение удалено. · ещё 4'
            : '${_deleted('Намерение 6')} · 4 more';
        expect(find.text(message), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: message,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );

        final late = harness.startDelete(index: 7, title: 'Позднее');
        harness.completeDeleted(late);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(find.text(message), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text(message), findsNothing);
        expect(
          find.text(
            locale.languageCode == 'ru'
                ? 'Удаление — «Позднее»: Намерение удалено.'
                : _deleted('Позднее'),
          ),
          findsOneWidget,
        );
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets(
    'сообщение смахивается в обе стороны, а вниз остаётся на поверхности',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final current = harness.startDelete(index: 1, title: 'Текущее');
      harness.completeDeleted(current);
      await tester.pumpAndSettle();
      final second = harness.startDelete(index: 2, title: 'Второе');
      final third = harness.startDelete(index: 3, title: 'Третье');
      harness.completeDeleted(second);
      harness.completeDeleted(third);
      await tester.pumpAndSettle();

      await tester.dragFrom(
        tester.getCenter(find.byType(SnackBar)),
        const Offset(0, 150),
      );
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Текущее')), findsOneWidget);
      await tester.dragFrom(
        tester.getCenter(find.byType(SnackBar)),
        const Offset(600, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('${_deleted('Третье')} · 1 more'), findsOneWidget);

      final late = harness.startDelete(index: 4, title: 'Позднее');
      harness.completeDeleted(late);
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getCenter(find.byType(SnackBar)),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Позднее')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'Scaffold модальной панели, появившийся и снятый во время показа, '
    'получает текущее сообщение без повтора, перезапуска и вытеснения '
    'следующим результатом',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final first = harness.startDelete(index: 1, title: 'Первое');
      final second = harness.startDelete(index: 2, title: 'Второе');
      harness.completeDeleted(first);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Первое')), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      const sheet = ValueKey('modal-sheet');
      final navigator = Navigator.of(tester.element(find.byType(Scaffold)));
      unawaited(
        navigator.push(
          PageRouteBuilder<void>(
            opaque: false,
            pageBuilder: (_, _, _) => const Scaffold(
              key: sheet,
              backgroundColor: Colors.transparent,
              body: SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Модальная поверхность показывает то же сообщение, а не второе.
      expect(
        find.descendant(
          of: find.byKey(sheet),
          matching: find.text(_deleted('Первое')),
        ),
        findsOneWidget,
      );
      harness.completeDeleted(second);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Второе')), findsNothing);

      // Появление поверхности не перезапустило срок текущего сообщения.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Первое')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(sheet),
          matching: find.text(_deleted('Второе')),
        ),
        findsOneWidget,
      );

      // Снятие модальной поверхности не повторяет и не перезапускает
      // следующее сообщение.
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Второе')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  // Обычное время показа — 4 с. Лист без сообщений поверх и диалог
  // перекрывают страницу без собственного Scaffold; лист закрывается и после
  // этого времени, и до его конца.
  for (final scenario
      in <
        ({
          String route,
          Duration openFor,
          Future<void> Function(BuildContext) open,
        })
      >[
        (
          route: 'листе',
          openFor: const Duration(seconds: 10),
          open: _openSheet,
        ),
        (
          route: 'диалоге',
          openFor: const Duration(seconds: 10),
          open: (context) => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('Диалог')),
          ),
        ),
        (route: 'листе', openFor: const Duration(seconds: 3), open: _openSheet),
      ]) {
    testWidgets('результат, пришедший при открытом ${scenario.route}, ждёт '
        '${scenario.openFor.inSeconds} с его закрытия и затем показывается над '
        'страницей один раз на обычное время с доступной семантикой', (
      tester,
    ) async {
      final harness = await _pumpPresenterApp(tester);
      final page = tester.element(find.byType(Scaffold));
      final navigator = Navigator.of(page);
      unawaited(scenario.open(page));
      await tester.pumpAndSettle();

      final covered = harness.startDelete(index: 1, title: 'Перекрытое');
      harness.completeDeleted(covered);
      await tester.pumpAndSettle();
      await tester.pump(scenario.openFor);
      await tester.pumpAndSettle();

      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Перекрытое')), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: _deleted('Перекрытое'),
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Перекрытое')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  for (final (name, openMessagesSheet) in [
    ('content', _openContentMessagesSheet),
    ('expandable', _openExpandableMessagesSheet),
  ]) {
    testWidgets('ожидающий результат показан над нижней частью открытого '
        'листа $name с сообщениями поверх и предъявлен, пока лист '
        'открыт', (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final first = harness.startDelete(index: 1, title: 'Первое');
      final second = harness.startDelete(index: 2, title: 'Второе');
      unawaited(openMessagesSheet(tester.element(find.byType(Scaffold))));
      await tester.pumpAndSettle();

      harness.completeDeleted(first);
      harness.completeDeleted(second);
      await tester.pumpAndSettle();
      final message = find.descendant(
        of: find.byType(Sheet),
        matching: find.text(_deleted('Первое')),
      );
      expect(message, findsOneWidget);
      expect(
        tester
            .getRect(
              find.descendant(
                of: find.byType(Sheet),
                matching: find.byType(SnackBar),
              ),
            )
            .bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Готово')).top),
      );

      // Неподтверждённое сообщение не закрывается по времени, а следующее
      // показывается только после предъявленного.
      await _closeMessage(tester);
      expect(find.byType(Sheet), findsOneWidget);
      expect(find.text(_deleted('Первое')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(Sheet),
          matching: find.text(_deleted('Второе')),
        ),
        findsOneWidget,
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets(
    'success с живым инициатором и fallback-ошибка используют одну очередь',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final success = harness.startDelete(
        index: 1,
        title: 'Успешное',
        releaseInitiator: false,
      );
      final failure = harness.startDelete(index: 2, title: 'Отказное');
      harness.completeDeleted(success);
      harness.completeUnavailable(failure);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Успешное')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.text(_notDeleted('Отказное')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final (locale, live, late) in [
    (
      const Locale('ru'),
      'Создание — «Полное намерение»: Намерение создано и отмечено.',
      'Создание — «Полное намерение»: Намерение создано.',
    ),
    (
      const Locale('en'),
      'Create — “Полное намерение”: Intention created and selected.',
      'Create — “Полное намерение”: Intention created.',
    ),
  ]) {
    for (final released in [false, true]) {
      testWidgets('создание для поиска сообщает исход с учётом ухода, '
          '${locale.languageCode}, освобождено: $released', (tester) async {
        final harness = await _pumpPresenterApp(tester, locale: locale);
        final creation = harness.startFullCreation(
          releaseInitiator: released,
          target: const CreatingIntentionForSearchOperationTarget(),
        );
        harness.completeFullCreated(creation);
        await tester.pumpAndSettle();

        expect(find.text(released ? late : live), findsOneWidget);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      });
    }
  }

  for (final (locale, live, late) in [
    (
      const Locale('ru'),
      'Создание — «Полное намерение»: Намерение создано и выбрано началом пути.',
      'Создание — «Полное намерение»: Намерение создано.',
    ),
    (
      const Locale('en'),
      'Create — “Полное намерение”: Intention created and selected as the start of the path.',
      'Create — “Полное намерение”: Intention created.',
    ),
  ]) {
    for (final released in [false, true]) {
      testWidgets(
        'создание начала пути сообщает исход с учётом ухода, ${locale.languageCode}, освобождено: $released',
        (tester) async {
          final harness = await _pumpPresenterApp(tester, locale: locale);
          final creation = harness.startFullCreation(
            releaseInitiator: released,
            target: const CreatingIntentionForPathStartOperationTarget(),
          );
          harness.completeFullCreated(creation);
          await tester.pumpAndSettle();
          expect(find.text(released ? late : live), findsOneWidget);
          await _closeMessage(tester);
        },
      );
    }
  }

  // Язык не меняет путь предъявления, поэтому достаточно русского.
  const fullCreation = (
    locale: Locale('ru'),
    created: 'Создание — «Полное намерение»: Намерение создано.',
    invalid: 'Создание — «новое намерение»: Проверьте введённые данные.',
  );
  for (final releaseInitiator in [false, true]) {
    final initiator = releaseInitiator
        ? 'после ухода формы'
        : 'при живой форме';
    testWidgets(
      'успех полного создания $initiator предъявляется одним сообщением без '
      'отдельных исходов назначений, '
      '${fullCreation.locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: fullCreation.locale,
        );
        final creation = harness.startFullCreation(
          releaseInitiator: releaseInitiator,
        );
        harness.completeFullCreated(creation);
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(fullCreation.created), findsOneWidget);

        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('отказ отсутствующих тегов живой формы не дублируется общей '
      'поверхностью, а после её ухода предъявляется ею один раз, '
      '${fullCreation.locale.languageCode}', (tester) async {
    final harness = await _pumpPresenterApp(
      tester,
      locale: fullCreation.locale,
    );
    final creation = harness.startFullCreation(releaseInitiator: false);
    harness.completeFailure(
      creation,
      IntentionCreationTagsMissingFailure([_tagId]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);

    harness.releaseInitiatorPresentation(creation.token);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(fullCreation.invalid), findsOneWidget);
    expect(find.textContaining(_tagId.toCanonicalString()), findsNothing);

    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('отказ изменения вида предъявляется общей поверхностью', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final operation = harness.startKindChange();
    harness.completeFailure(
      operation,
      const IntentionMissingIncomingRelationFailure(),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Изменение вида — «Намерение»: Не удалось изменить состояние намерения.',
      ),
      findsOneWidget,
    );
  });

  for (final scenario in [
    (
      operation: CascadeOperation.archive,
      cause: const CascadePreviewUnavailable(),
      text:
          'Архивирование — «Намерение»: Не удалось изменить состояние '
          'намерения. Повторите попытку.',
    ),
    (
      operation: CascadeOperation.restore,
      cause: const CascadePreviewSubjectNotFound(),
      text:
          'Восстановление — «Намерение»: Намерение больше не существует. '
          'Его состояние не изменено.',
    ),
    (
      operation: CascadeOperation.delete,
      cause: const CascadePreviewCorruption(),
      text:
          'Удаление — «Намерение»: Сохранённые данные повреждены. Намерение '
          'не удалено.',
    ),
  ]) {
    testWidgets(
      'отказ предпросмотра операции ${scenario.operation.name} предъявляется '
      'общей поверхностью как отказ этой операции один раз',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: const Locale('ru'),
        );

        harness.startPreviewFailure(scenario.operation, scenario.cause);
        await tester.pumpAndSettle();

        expect(find.text(scenario.text), findsOneWidget);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('конфликт состава каскада предъявляется общей поверхностью '
      'текстом о конфликте актуального состояния', (tester) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final archive = harness.startArchive();
    harness.completeFailure(archive, const IntentionCascadeConflictFailure());
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Архивирование — «Намерение»: Состояние намерения не изменено: '
        'связанные намерения изменились, и операция затронула бы их иначе. '
        'Попробуйте снова.',
      ),
      findsOneWidget,
    );
    await _closeMessage(tester);

    final relationArchive = harness.startRelationArchive();
    harness.completeRelationFailure(
      relationArchive,
      const LongTermRelationCascadeConflictFailure(),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Связь не удалось архивировать из-за конфликта актуального состояния.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'отказ предпросмотра, принятый без фокуса на странице, после ухода с '
    'неё ждёт возвращения фокуса и предъявляется один раз',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final navigator = Navigator.of(tester.element(find.byType(Scaffold)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Страница намерения')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

      harness.startPreviewFailure(
        CascadeOperation.archive,
        const CascadePreviewUnexpected(),
      );
      await tester.pump();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Archive — “Намерение”: The intention state couldn’t be changed '
          'because of an unexpected error.',
        ),
        findsOneWidget,
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final kind in TagCommandKind.values) {
    testWidgets(
      'отказ операции тега ${kind.name} показывается общей поверхностью без '
      'ухода инициатора',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: const Locale('ru'),
        );
        final accepted = harness.startTag(kind);
        harness.completeTagFailure(accepted, const TagUnavailableFailure());
        await tester.pumpAndSettle();

        final message = switch (kind) {
          TagCommandKind.create =>
            'Создание — «тег»: Не удалось выполнить действие с тегом. '
                'Повторите попытку.',
          TagCommandKind.update =>
            'Изменение — «тег»: Не удалось выполнить действие с тегом. '
                'Повторите попытку.',
          TagCommandKind.delete =>
            'Удаление — «тег»: Не удалось выполнить действие с тегом. '
                'Повторите попытку.',
          TagCommandKind.move =>
            'Перестановка — «тег»: Не удалось выполнить действие с тегом. '
                'Повторите попытку.',
          TagCommandKind.assign =>
            'Назначение — «назначение тега»: Не удалось изменить назначение '
                'тега. Повторите попытку.',
          TagCommandKind.removeAssignment =>
            'Снятие — «назначение тега»: Не удалось изменить назначение '
                'тега. Повторите попытку.',
        };
        expect(find.text(message), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: message,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  for (final scenario in <({TagCommandFailure failure, String ru})>[
    (
      failure: const TagNameInputFailure(
        TagNameFailureReason.invalidUnicodeRepertoire,
      ),
      ru: 'Название тега содержит недопустимые символы.',
    ),
    (
      failure: const TagNameInputFailure(TagNameFailureReason.empty),
      ru: 'Введите название тега.',
    ),
    (
      failure: const TagNameInputFailure(TagNameFailureReason.tooLong),
      ru: 'Название тега должно содержать не более 255 отображаемых символов.',
    ),
    (
      failure: const TagNameInputFailure(TagNameFailureReason.nonCanonical),
      ru: 'Удалите пробелы по краям названия тега.',
    ),
    (
      failure: TagNameOccupiedFailure(_tagId),
      ru: 'Тег с таким названием уже есть.',
    ),
    (
      failure: TagNotFoundFailure(_tagId),
      ru: 'Этого тега больше нет. Обновите каталог.',
    ),
    (
      failure: const TagUnavailableFailure(),
      ru: 'Не удалось выполнить действие с тегом. Повторите попытку.',
    ),
    (
      failure: const TagCorruptionFailure(),
      ru: 'Сохранённые данные тега повреждены. Тег не изменён.',
    ),
    (
      failure: const TagUnexpectedFailure(),
      ru: 'Действие с тегом не выполнено из-за непредвиденной ошибки.',
    ),
  ]) {
    testWidgets('отказ тега ${scenario.failure.runtimeType} безопасен', (
      tester,
    ) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final accepted = harness.startTag(TagCommandKind.create);
      harness.completeTagFailure(accepted, scenario.failure);
      await tester.pumpAndSettle();

      final message = 'Создание — «тег»: ${scenario.ru}';
      expect(find.text(message), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('отказ перестановки тега называет перестановку по-английски', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final accepted = harness.startTag(TagCommandKind.move);
    harness.completeTagFailure(accepted, const TagUnavailableFailure());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Move — “tag”: Could not complete the tag operation. Try again.',
      ),
      findsOneWidget,
    );
    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('исключение хранилища тега не попадает в сообщение', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final accepted = harness.startTag(TagCommandKind.create);
    harness.failTagWithException(accepted, StateError('личные данные'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Create — “tag”: The tag operation failed because of an unexpected error.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('личные данные'), findsNothing);
    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'отказы остаются у инициаторов и передаются оболочке без вытеснения успеха',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final success = harness.startDelete(
        index: 1,
        title: 'Успешное',
        releaseInitiator: false,
      );
      final inline = harness.startDelete(
        index: 2,
        title: 'Инлайн',
        releaseInitiator: false,
      );
      final handed = harness.startDelete(
        index: 3,
        title: 'Переданное',
        releaseInitiator: false,
      );
      harness.completeDeleted(success);
      harness.completeUnavailable(inline);
      harness.completeUnavailable(handed);
      await tester.pumpAndSettle();

      // Успех сразу принадлежит оболочке, а ошибки — открытым инициаторам.
      expect(find.text(_deleted('Успешное')), findsOneWidget);

      // Инлайн-renderer подтверждает свой кадр, а вторая сессия уходит до
      // кадра и передаёт ошибку оболочке, не вытесняя текущее сообщение.
      harness.confirmPresentation(harness.claimInitiatorFailure(inline.token)!);
      harness.releaseInitiatorPresentation(handed.token);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Успешное')), findsOneWidget);
      expect(find.text(_notDeleted('Переданное')), findsNothing);

      await _closeMessage(tester);
      expect(find.text(_deleted('Успешное')), findsNothing);
      expect(find.text(_notDeleted('Переданное')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(_notDeleted('Инлайн')), findsNothing);
    },
  );

  testWidgets('отказ тега ждёт текущего сообщения графа и не вытесняет его', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final intention = harness.startDelete(index: 1, title: 'Граф');
    final tag = harness.startTag(TagCommandKind.create);
    harness.completeDeleted(intention);
    harness.completeTagFailure(tag, const TagUnavailableFailure());
    await tester.pumpAndSettle();

    expect(find.text(_deleted('Граф')), findsOneWidget);
    await _closeMessage(tester);
    expect(
      find.text(
        'Create — “tag”: Could not complete the tag operation. Try again.',
      ),
      findsOneWidget,
    );
    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final scenario in <({TagCommandFailure failure, String ru})>[
    (
      failure: TagNotFoundFailure(_tagId),
      ru: 'Этого тега больше нет. Обновите каталог.',
    ),
    (
      failure: TagIntentionNotFoundFailure(testDetailsIntentionId(1)),
      ru: 'Этого намерения больше нет. Обновите подробности.',
    ),
    (
      failure: const TagUnavailableFailure(),
      ru: 'Не удалось изменить назначение тега. Повторите попытку.',
    ),
    (
      failure: const TagCorruptionFailure(),
      ru: 'Сохранённые данные назначения тега повреждены. Назначение не изменено.',
    ),
    (
      failure: const TagUnexpectedFailure(),
      ru: 'Назначение тега не изменено из-за непредвиденной ошибки.',
    ),
  ]) {
    testWidgets('отказ назначения ${scenario.failure.runtimeType}', (
      tester,
    ) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final accepted = harness.startTag(TagCommandKind.assign);
      harness.completeTagFailure(accepted, scenario.failure);
      await tester.pumpAndSettle();

      final message = 'Назначение — «назначение тега»: ${scenario.ru}';
      expect(find.text(message), findsOneWidget);
      await _closeMessage(tester);
    });
  }

  testWidgets('создание действия и конфликт пути предъявляются безопасно', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final creation = harness.startActionCreation();
    harness.completeActionCreated(creation);
    await tester.pumpAndSettle();
    expect(
      find.text('Создание — «действие»: Действие создано.'),
      findsOneWidget,
    );
    await _closeMessage(tester);
    final conflict = harness.startActionCreation();
    harness.completeActionFailure(conflict, const ActionPathConflictFailure());
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Создание — «действие»: Путь больше не совпадает с графом. Проверьте путь и попробуйте снова.',
      ),
      findsOneWidget,
    );
    await _closeMessage(tester);
  });

  testWidgets('действие предъявляет удаление лишь после подтверждения записи', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final deletion = harness.startActionDelete();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    harness.completeActionDeleted(deletion);
    await tester.pumpAndSettle();

    expect(
      find.text('Удаление — «действие»: Действие удалено.'),
      findsOneWidget,
    );
    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('сообщение об удалении действия локализуется', (tester) async {
    final harness = await _pumpPresenterApp(tester);
    final deletion = harness.startActionDelete();

    harness.completeActionDeleted(deletion);
    await tester.pumpAndSettle();

    expect(find.text('Delete — “action”: Action deleted.'), findsOneWidget);
    await _closeMessage(tester);
  });

  for (final scenario in <({ActionCommandFailure failure, String ru})>[
    (
      failure: const ActionNotFoundFailure(),
      ru: 'Действие больше не существует.',
    ),
    (
      failure: const ActionConflictFailure(),
      ru: 'Данные изменились. Обновите их и подтвердите снова.',
    ),
    (
      failure: const ActionUnavailableFailure(),
      ru: 'Не удалось выполнить операцию с действием. Повторите попытку.',
    ),
    (
      failure: const ActionCorruptionFailure(),
      ru: 'Сохранённые данные повреждены. Действие не изменено.',
    ),
    (
      failure: const ActionUnexpectedFailure(),
      ru: 'Операция с действием не выполнена из-за непредвиденной ошибки.',
    ),
  ]) {
    testWidgets('отказ действия ${scenario.failure.runtimeType} объяснён', (
      tester,
    ) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final update = harness.startActionUpdate();
      harness.completeActionFailure(update, scenario.failure);
      await tester.pumpAndSettle();

      expect(
        find.text('Изменение — «действие»: ${scenario.ru}'),
        findsOneWidget,
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets(
    'успех изменения действия не объявляется сообщением и не занимает '
    'очередь',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 1, title: 'Намерение');
      final update = harness.startActionUpdate();
      harness.completeDeleted(intention);
      harness.completeActionUpdated(update);
      await update.future;
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Намерение')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final scenario in <({Locale locale, String message})>[
    (
      locale: const Locale('ru'),
      message:
          'Изменение — «связь»: Связь архивирована, поэтому её тип нельзя '
          'изменить.',
    ),
    (
      locale: const Locale('en'),
      message: _relationUpdateOutcome(
        'This relation is archived, so its type can’t be changed.',
      ),
    ),
  ]) {
    testWidgets('отказ смены типа архивированной связи назван для '
        '${scenario.locale.languageCode}', (tester) async {
      final harness = await _pumpPresenterApp(tester, locale: scenario.locale);
      final update = harness.startRelationUpdate();
      harness.completeRelationFailure(
        update,
        LongTermRelationArchivedTypeChangeFailure(_relationId),
      );
      await tester.pumpAndSettle();

      expect(find.text(scenario.message), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  // Все состояния, кроме resumed, удерживают результат одной ветвью; берём
  // полный уход в фон и возврат через промежуточные состояния.
  const lifecycle = (
    state: AppLifecycleState.paused,
    away: [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ],
    back: [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ],
  );
  testWidgets(
    '${lifecycle.state.name} удерживает результат до возвращения в resumed',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      for (final state in lifecycle.away) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      final operation = harness.startDelete(index: 1, title: 'Фоновое');
      harness.completeDeleted(operation);
      await tester.pump();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);

      for (final state in lifecycle.back) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Фоновое')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('неизвестное исходное lifecycle state не разрешает показ', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    tester.binding.resetInternalState();
    final operation = harness.startDelete(index: 1, title: 'Неизвестное');
    harness.completeDeleted(operation);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(_deleted('Неизвестное')), findsOneWidget);
  });

  testWidgets(
    'потеря фокуса до кадра сохраняет весь набор, а повторный показ использует текущую локализацию',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      harness.presenterGeneration.value = _withoutPresenter;
      await tester.pumpAndSettle();
      final first = harness.startDelete(index: 1, title: 'Первое');
      final second = harness.startDelete(index: 2, title: 'Отложенное');
      harness.completeDeleted(first);
      harness.completeDeleted(second);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      harness.presenterGeneration.value = 1;
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // Сообщение подготовлено, но ни одного пригодного кадра ещё нет.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('${_deleted('Отложенное')} · 1 more'), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);

      harness.locale.value = const Locale('ru');
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Удаление — «Отложенное»: Намерение удалено. · ещё 1'),
        findsOneWidget,
      );

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'пересоздание до подтверждения снимает прежнее сообщение и показывает результат один раз',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final operation = harness.startDelete(index: 1, title: 'Пересоздание');
      final second = harness.startDelete(index: 2, title: 'Второе');
      harness.completeDeleted(operation);
      harness.completeDeleted(second);
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text(_deleted('Пересоздание')), findsOneWidget);

      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('${_deleted('Второе')} · 1 more'), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'пересоздание после подтверждения снимает поверхность без повтора и продолжает очередь',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final first = harness.startDelete(index: 1, title: 'Предъявленное');
      final second = harness.startDelete(index: 2, title: 'Следующее');
      harness.completeDeleted(first);
      harness.completeDeleted(second);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Предъявленное')), findsOneWidget);

      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Предъявленное')), findsNothing);
      expect(find.text(_deleted('Следующее')), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'новый presenter получает накопленные результаты с приоритетом отказа',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      harness.presenterGeneration.value = _withoutPresenter;
      await tester.pumpAndSettle();

      final first = harness.startDelete(index: 1, title: 'Первое');
      final second = harness.startDelete(index: 2, title: 'Второе');
      harness.completeDeleted(first);
      harness.completeUnavailable(second);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      harness.presenterGeneration.value = 1;
      await tester.pumpAndSettle();
      expect(find.text(_notDeleted('Второе')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.text(_deleted('Первое')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'досрочное снятие подтверждённого сообщения не возвращает результат',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final first = harness.startDelete(index: 1, title: 'Снятое');
      final second = harness.startDelete(index: 2, title: 'Следующее');
      harness.completeDeleted(first);
      harness.completeDeleted(second);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Снятое')), findsOneWidget);

      // Имитирует закрытие сообщения пользователем после предъявления.
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Снятое')), findsNothing);
      expect(find.text(_deleted('Следующее')), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'успех изменения, архивирования и восстановления связи не объявляется '
    'сообщением и не занимает очередь',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 1, title: 'Намерение');
      final update = harness.startRelationUpdate();
      harness.completeDeleted(intention);
      harness.completeRelationUpdated(update);
      await update.future;

      final archive = harness.startRelationArchive();
      harness.completeRelationArchived(archive);
      await archive.future;

      final restore = harness.startRelationRestore();
      harness.completeRelationRestored(restore);
      await restore.future;
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Намерение')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final scenario in _relationDeleteFailures) {
    testWidgets(
      'переданная ошибка удаления связи «${scenario.name}» предъявляется безопасным текстом',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        final deletion = harness.startRelationDelete();
        harness.completeRelationFailure(deletion, scenario.failure);
        await tester.pumpAndSettle();

        expect(
          find.text(_relationDeleteOutcome(scenario.outcome)),
          findsOneWidget,
        );

        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('удаление связи предъявляется на русском языке', (tester) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final deletion = harness.startRelationDelete();
    harness.completeRelationDeleted(deletion);
    await tester.pumpAndSettle();

    expect(find.text('Удаление — «связь»: Связь удалена.'), findsOneWidget);

    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('восстановление связи предъявляется на русском языке', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final restore = harness.startRelationRestore();
    harness.completeRelationFailure(
      restore,
      const LongTermRelationCascadeConflictFailure(),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Восстановление — «связь»: Связь не удалось восстановить из-за '
        'конфликта актуального состояния.',
      ),
      findsOneWidget,
    );
  });

  for (final scenario in [
    (
      locale: 'ru',
      count: 1,
      message: 'Добавление — «связи»: Добавлена 1 связь.',
    ),
    (
      locale: 'ru',
      count: 3,
      message: 'Добавление — «связи»: Добавлено 3 связи.',
    ),
    (
      locale: 'ru',
      count: 5,
      message: 'Добавление — «связи»: Добавлено 5 связей.',
    ),
    (locale: 'en', count: 1, message: 'Add — “relations”: 1 relation added.'),
    (locale: 'en', count: 3, message: 'Add — “relations”: 3 relations added.'),
  ]) {
    testWidgets(
      'успех добавления называет число из результата: ${scenario.locale} ${scenario.count}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: Locale(scenario.locale),
        );
        final accepted = harness.startRelationsAddition(
          count: scenario.count,
          releaseInitiator: false,
        );
        harness.completeRelationsAdded(accepted, scenario.count);
        await tester.pumpAndSettle();
        expect(find.text(scenario.message), findsOneWidget);
      },
    );
  }

  testWidgets(
    'поздний отказ добавления появляется один раз после ухода поиска',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final accepted = harness.startRelationsAddition();
      harness.completeRelationFailure(
        accepted,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Add — “relations”: No relations were created. Try again.'),
        findsOneWidget,
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  test('отказы добавления объясняют отсутствие всех связей на обоих языках', () {
    final scenarios = [
      (
        failure: LongTermRelationPairOccupiedFailure(_relationId),
        ru: 'Некоторые выбранные намерения уже связаны с этим намерением. Связи не созданы.',
        en: 'Some selected intentions are already linked to this intention. No relations were created.',
      ),
      (
        failure: LongTermRelationParticipantNotFoundFailure(
          role: RelationParticipantRole.related,
          intentionId: testDetailsIntentionId(2),
        ),
        ru: 'Одно из выбранных намерений больше не существует. Связи не созданы.',
        en: 'A selected intention no longer exists. No relations were created.',
      ),
      (
        failure: LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.source,
          intentionId: testDetailsIntentionId(1),
        ),
        ru: 'Связать можно только активные намерения. Связи не созданы.',
        en: 'Only active intentions can be linked. No relations were created.',
      ),
      (
        failure: const LongTermRelationUnavailableFailure(),
        ru: 'Связи не созданы. Повторите попытку.',
        en: 'No relations were created. Try again.',
      ),
      (
        failure: const LongTermRelationCorruptionFailure(),
        ru: 'Сохранённые данные повреждены. Связи не созданы.',
        en: 'Stored data is damaged. No relations were created.',
      ),
      (
        failure: const LongTermRelationUnexpectedFailure(),
        ru: 'Связи не созданы из-за непредвиденной ошибки.',
        en: 'No relations were created because of an unexpected error.',
      ),
    ];
    for (final scenario in scenarios) {
      for (final locale in [const Locale('ru'), const Locale('en')]) {
        expect(
          longTermRelationCommandFailureMessage(
            lookupAppLocalizations(locale),
            LongTermRelationCommandKind.add,
            scenario.failure,
          ),
          locale.languageCode == 'ru' ? scenario.ru : scenario.en,
        );
      }
    }
  });

  for (final scenario in _relationUpdateFailures) {
    testWidgets(
      'переданная ошибка изменения связи «${scenario.name}» предъявляется безопасным текстом',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        final relation = harness.startRelationUpdate();
        harness.completeRelationFailure(relation, scenario.failure);
        await tester.pumpAndSettle();

        expect(
          find.text(_relationUpdateOutcome(scenario.outcome)),
          findsOneWidget,
        );

        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('изменение связи предъявляется на русском языке', (tester) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final relation = harness.startRelationUpdate();
    harness.completeRelationFailure(
      relation,
      const LongTermRelationUnavailableFailure(),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Изменение — «связь»: Не удалось изменить связь. Повторите попытку.',
      ),
      findsOneWidget,
    );
  });

  for (final scenario in [
    (
      locale: const Locale('ru'),
      saved: 'Данные сохранены в файл',
      failed: 'Не удалось сохранить файл',
      existingFile: 'Такой файл уже есть. Сохраните копию под новым именем',
      retry: 'Повторить',
    ),
    (
      locale: const Locale('en'),
      saved: 'Data saved to a file',
      failed: _exportFailed,
      existingFile: 'That file already exists. Save the copy under a new name',
      retry: 'Try again',
    ),
  ]) {
    testWidgets(
      'успех экспорта предъявляется текстом, а отказ — текстом и кнопкой '
      '«Повторить», которая запускает повтор один раз, '
      '${scenario.locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: scenario.locale,
        );
        final success = harness.startExport();
        harness.completeExport(success, GraphExportOutcome.succeeded);
        await tester.pumpAndSettle();

        expect(find.text(scenario.saved), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: scenario.saved,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        expect(find.byType(SnackBarAction), findsNothing);
        await _closeMessage(tester);

        final failure = harness.startExport();
        harness.completeExport(failure, GraphExportOutcome.failed);
        await tester.pumpAndSettle();

        expect(find.text(scenario.failed), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: scenario.failed,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        expect(
          tester.getSemantics(find.text(scenario.retry)),
          isSemantics(
            label: scenario.retry,
            isButton: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        expect(harness.exportRetries, 0);

        await tester.tap(find.text(scenario.retry));
        await tester.pump();
        await tester.tap(find.text(scenario.retry), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(harness.exportRetries, 1);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'выбор файла с данными предъявляется текстом и кнопкой «Повторить», '
      'которая запускает повтор экспорта, ${scenario.locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: scenario.locale,
        );
        final export = harness.startExport();
        harness.completeExport(export, GraphExportOutcome.existingFile);
        await tester.pumpAndSettle();

        expect(find.text(scenario.existingFile), findsOneWidget);

        await tester.tap(find.text(scenario.retry));
        await tester.pumpAndSettle();
        expect(harness.exportRetries, 1);
      },
    );
  }

  for (final accessibleNavigation in [false, true]) {
    testWidgets('отказ экспорта закрывается через обычное время показа и при '
        'accessibleNavigation $accessibleNavigation, а затем предъявляется '
        'успех команды, ставший ожидающим во время показа', (tester) async {
      if (accessibleNavigation) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(accessibleNavigation: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      }
      final harness = await _pumpPresenterApp(tester);
      final export = harness.startExport();
      harness.completeExport(export, GraphExportOutcome.failed);
      await tester.pumpAndSettle();
      expect(find.text(_exportFailed), findsOneWidget);

      final command = harness.startDelete(index: 1, title: 'Ожидающее');
      harness.completeDeleted(command);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(_exportFailed), findsOneWidget);
      expect(find.text(_deleted('Ожидающее')), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(_exportFailed), findsNothing);
      expect(find.text(_deleted('Ожидающее')), findsOneWidget);
      expect(harness.exportRetries, 0);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  for (final scenario in [
    (
      locale: const Locale('ru'),
      restored: 'Копия восстановлена',
      failed: 'Не удалось восстановить копию. Ничего не изменено',
      storageFull:
          'Недостаточно места на устройстве. Освободите место и повторите. '
          'Ничего не изменено',
    ),
    (
      locale: const Locale('en'),
      restored: 'Copy restored',
      failed: 'Couldn’t restore the copy. Nothing was changed',
      storageFull:
          'Not enough space on the device. Free up space and try again. '
          'Nothing was changed',
    ),
  ]) {
    testWidgets(
      'успех восстановления копии сразу предъявляется общей поверхностью, а '
      'отказ сначала принадлежит инициатору и без его права предъявляется '
      'общей поверхностью, ${scenario.locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: scenario.locale,
        );
        final success = harness.startBackupRestore();
        harness.completeBackupRestored(success);
        await tester.pumpAndSettle();

        expect(find.text(scenario.restored), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: scenario.restored,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        await _closeMessage(tester);

        for (final (outcome, message) in [
          (const GraphBackupRestoreFailed(), scenario.failed),
          (const GraphBackupRestoreStorageFull(), scenario.storageFull),
        ]) {
          final failure = harness.startBackupRestore();
          harness.completeBackupRestore(failure, outcome);
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing);
          final claim = harness.claimInitiatorFailure(failure.token);
          expect(claim, isNotNull);

          harness.releaseInitiatorClaim(claim!);
          await tester.pumpAndSettle();
          expect(find.text(message), findsOneWidget);
          expect(
            tester.getSemantics(
              find.byKey(const ValueKey('graph-operation-message')),
            ),
            matchesSemantics(
              label: message,
              isLiveRegion: true,
              textDirection: TextDirection.ltr,
            ),
          );
          await _closeMessage(tester);
        }
      },
    );
  }

  for (final scenario in [
    (
      locale: const Locale('ru'),
      imported: 'Данные импортированы',
      failures: {
        GraphImportFailure.invalidFile:
            'Не удалось импортировать файл. Это не экспорт Doable, или он '
            'повреждён. Ничего не изменено',
        GraphImportFailure.newerFormatVersion:
            'Файл создан более новой версией Doable. Обновите приложение, '
            'чтобы импортировать его. Ничего не изменено',
        GraphImportFailure.storageFull:
            'Недостаточно места на устройстве. Освободите место и повторите. '
            'Ничего не изменено',
        GraphImportFailure.documentUnreadable:
            'Не удалось прочитать файл. Проверьте доступ к нему и повторите. '
            'Ничего не изменено',
        GraphImportFailure.unknown:
            'Не удалось импортировать данные. Ничего не изменено',
      },
    ),
    (
      locale: const Locale('en'),
      imported: 'Data imported',
      failures: {
        GraphImportFailure.invalidFile:
            'Couldn’t import the file. It isn’t a Doable export, or it’s '
            'damaged. Nothing was changed',
        GraphImportFailure.newerFormatVersion:
            'The file was created by a newer version of Doable. Update the '
            'app to import it. Nothing was changed',
        GraphImportFailure.storageFull:
            'Not enough space on the device. Free up space and try again. '
            'Nothing was changed',
        GraphImportFailure.documentUnreadable:
            'Couldn’t read the file. Check that you can access it and try '
            'again. Nothing was changed',
        GraphImportFailure.unknown:
            'Couldn’t import the data. Nothing was changed',
      },
    ),
  ]) {
    testWidgets(
      'успех импорта сразу предъявляется общей поверхностью, а отказ каждого '
      'вида сначала принадлежит инициатору и без его права предъявляется '
      'общей поверхностью своим текстом без действия, '
      '${scenario.locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: scenario.locale,
        );
        harness.startImported();
        await tester.pumpAndSettle();

        expect(find.text(scenario.imported), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: scenario.imported,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        await _closeMessage(tester);

        for (final MapEntry(key: failure, value: message)
            in scenario.failures.entries) {
          final accepted = harness.startImportFailed(failure);
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing, reason: '$failure');
          final claim = harness.claimInitiatorFailure(accepted.token);
          expect(claim, isNotNull, reason: '$failure');

          harness.releaseInitiatorClaim(claim!);
          await tester.pumpAndSettle();
          expect(find.text(message), findsOneWidget, reason: '$failure');
          expect(
            tester.getSemantics(
              find.byKey(const ValueKey('graph-operation-message')),
            ),
            matchesSemantics(
              label: message,
              isLiveRegion: true,
              textDirection: TextDirection.ltr,
            ),
          );
          expect(find.byType(SnackBarAction), findsNothing, reason: '$failure');
          await _closeMessage(tester);
        }
      },
    );
  }

  for (final scenario in [
    (locale: const Locale('ru'), failed: 'Не удалось сделать копию'),
    (locale: const Locale('en'), failed: 'Couldn’t back up'),
  ]) {
    testWidgets(
      'отказ ручной копии сразу предъявляется общей поверхностью текстом без '
      'действия, ${scenario.locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: scenario.locale,
        );
        harness.startManualBackup(ManualGraphBackupOutcome.failed);
        await tester.pumpAndSettle();

        expect(find.text(scenario.failed), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('graph-operation-message')),
          ),
          matchesSemantics(
            label: scenario.failed,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        expect(find.byType(SnackBarAction), findsNothing);
        await _closeMessage(tester);
      },
    );
  }
}

const _withoutPresenter = -1;

const _exportFailed = 'Couldn’t save the file';

String _deleted(String title) => 'Delete — “$title”: Intention deleted.';

String _notDeleted(String title) =>
    'Delete — “$title”: The intention couldn’t be deleted. Try again.';

String _relationUpdateOutcome(String outcome) => 'Edit — “relation”: $outcome';

String _relationDeleteOutcome(String outcome) =>
    'Delete — “relation”: $outcome';

const _relationUpdateUnexpected =
    'The relation couldn’t be updated because of an unexpected error.';

final _relationUpdateFailures =
    <({String name, LongTermRelationCommandFailure failure, String outcome})>[
      (
        name: 'pair conflict',
        failure: LongTermRelationPairOccupiedFailure(_otherRelationId),
        outcome: _relationUpdateUnexpected,
      ),
      (
        name: 'relation not found',
        failure: LongTermRelationNotFoundFailure(_relationId),
        outcome: 'This relation no longer exists.',
      ),
      (
        name: 'participant not found',
        failure: LongTermRelationParticipantNotFoundFailure(
          role: RelationParticipantRole.related,
          intentionId: testDetailsIntentionId(2),
        ),
        outcome: _relationUpdateUnexpected,
      ),
      (
        name: 'participant archived',
        failure: LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.source,
          intentionId: testDetailsIntentionId(1),
        ),
        outcome: _relationUpdateUnexpected,
      ),
      (
        name: 'unavailable',
        failure: const LongTermRelationUnavailableFailure(),
        outcome: 'The relation couldn’t be updated. Try again.',
      ),
      (
        name: 'corruption',
        failure: const LongTermRelationCorruptionFailure(),
        outcome: 'Stored data is damaged. The relation wasn’t updated.',
      ),
      (
        name: 'unexpected',
        failure: const LongTermRelationUnexpectedFailure(),
        outcome: _relationUpdateUnexpected,
      ),
    ];

final _relationDeleteFailures =
    <({String name, LongTermRelationCommandFailure failure, String outcome})>[
      (
        name: 'pair conflict',
        failure: LongTermRelationPairOccupiedFailure(_otherRelationId),
        outcome:
            'The relation couldn’t be deleted because its current state '
            'conflicts with the operation.',
      ),
      (
        name: 'notFound',
        failure: LongTermRelationNotFoundFailure(_relationId),
        outcome: 'This relation no longer exists.',
      ),
      (
        name: 'unavailable',
        failure: const LongTermRelationUnavailableFailure(),
        outcome: 'The relation couldn’t be deleted. Try again.',
      ),
      (
        name: 'corruption',
        failure: const LongTermRelationCorruptionFailure(),
        outcome: 'Stored data is damaged. The relation wasn’t deleted.',
      ),
      (
        name: 'unexpected',
        failure: const LongTermRelationUnexpectedFailure(),
        outcome:
            'The relation couldn’t be deleted because of an unexpected error.',
      ),
    ];

final _relationId = switch (LongTermRelationId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789ab',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  InvalidLongTermRelationIdDecoding() => throw StateError(
    'Некорректный fixture связи.',
  ),
};

final _otherRelationId = switch (LongTermRelationId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789ac',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  InvalidLongTermRelationIdDecoding() => throw StateError(
    'Некорректный fixture связи.',
  ),
};

final _actionId = switch (ActionId.decode(
  '018f1400-0000-7000-8000-000000000005',
)) {
  ActionIdDecodingSuccess(:final id) => id,
  InvalidActionIdDecoding() => throw StateError('Некорректный ID действия.'),
};

final _tagId = switch (TagId.decode('018f1400-0000-7000-8000-000000000003')) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
};

final _otherTagId = switch (TagId.decode(
  '018f1400-0000-7000-8000-000000000004',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
};

final class _CreatedCatalogEntrySnapshot
    implements IntentionCatalogEntrySnapshot {
  const _CreatedCatalogEntrySnapshot(this.summary);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

Future<void> _openSheet(BuildContext context) => showDoableSheet<void>(
  context: context,
  builder: (_, sheet) =>
      Sheet(sheet, title: 'Лист', child: const SizedBox(height: 120)),
);

Future<void> _openContentMessagesSheet(BuildContext context) =>
    showDoableSheet<void>(
      context: context,
      hostsMessages: true,
      builder: (_, sheet) => Sheet(
        sheet,
        title: 'Лист',
        footer: const SizedBox(height: 44, child: Text('Готово')),
        child: const SizedBox(height: 120),
      ),
    );

Future<void> _openExpandableMessagesSheet(BuildContext context) =>
    showDoableSheet<void>(
      context: context,
      hostsMessages: true,
      builder: (_, sheet) => Sheet.expandable(
        sheet,
        title: 'Лист',
        text: 'Пояснение',
        pinned: const SizedBox(height: 44),
        slivers: const [SliverToBoxAdapter(child: SizedBox(height: 120))],
        footer: const SizedBox(height: 44, child: Text('Готово')),
        expandLabel: 'Раскрыть',
        collapseLabel: 'Свернуть',
        compactHeight: SheetCompactHeight.limit,
      ),
    );

Future<void> _closeMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

final class _PresenterHarness {
  _PresenterHarness(
    this.container,
    this.repository,
    this.presenterGeneration,
    this.locale,
  );

  final ProviderContainer container;
  final ControlledDetailsRepository repository;
  final ValueNotifier<int> presenterGeneration;
  final ValueNotifier<Locale> locale;
  final _commandIndexes = <IntentionCommandAccepted, int>{};
  final _titles = <IntentionCommandAccepted, (int, String)>{};
  final _relationIndexes = <LongTermRelationCommandAccepted, int>{};
  final _actionIndexes = <ActionCommandAccepted, int>{};
  final _tagIndexes = <TagCommandAccepted, int>{};
  final _exports = <GraphExportAccepted, Completer<GraphExportOutcome>>{};
  final _restores =
      <
        GraphBackupRestoreAccepted,
        Completer<
          Future<GraphBackupRestoreOutcome> Function(
            GraphExclusiveReplacement<GraphBackupRestored>,
          )
        >
      >{};
  var exportRetries = 0;

  GraphCommandCoordinator get _coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  TagCommandAccepted startTag(TagCommandKind kind) {
    final commandIndex = repository.tagCommands.length;
    final accepted = switch (kind) {
      TagCommandKind.create => _coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(
          name: TagName.fromInput('Планы'),
          color: null,
          placement: TagPlacement.first,
        ),
      ),
      TagCommandKind.update => _coordinator.acceptTagUpdate(
        UpdateTag(
          tagId: _tagId,
          name: TagName.fromInput('Новое имя'),
          color: null,
        ),
      ),
      TagCommandKind.delete => _coordinator.acceptTagDelete(DeleteTag(_tagId)),
      TagCommandKind.move => _coordinator.acceptTagMove(
        MoveTag(tagId: _tagId, placement: TagPlacement.first),
      ),
      TagCommandKind.assign => _coordinator.acceptTagAssign(
        AssignTag(tagId: _tagId, intentionId: testDetailsIntentionId(1)),
      ),
      TagCommandKind.removeAssignment => _coordinator.acceptTagRemoveAssignment(
        RemoveTagAssignment(
          tagId: _tagId,
          intentionId: testDetailsIntentionId(1),
        ),
      ),
    } as TagCommandAccepted;
    _tagIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeTagFailure(
    TagCommandAccepted accepted,
    TagCommandFailure failure,
  ) => repository.completeTagCommand(
    _tagIndexes[accepted]!,
    TagCommandFailed(failure),
  );

  void failTagWithException(TagCommandAccepted accepted, Object error) =>
      repository.failTagCommand(_tagIndexes[accepted]!, error);

  void releaseInitiatorPresentation(GraphOperationToken token) =>
      _coordinator.releaseInitiatorPresentation(token);

  ActionCommandAccepted startActionCreation() {
    final commandIndex = repository.actionCommands.length;
    final accepted = _coordinator.acceptActionCreation(
      ActionCreationFormKey(),
      CreateAction(
        title: ActionTitle('Пробежка'),
        description: null,
        path: ActionPath([testDetailsIntentionId(1)]),
        date: CalendarDate.fromParts(2026, 9, 23),
        schedule: const ActionAllDay(),
        priority: ActionPriority.p4,
      ),
    ) as ActionCommandAccepted;
    _coordinator.releaseInitiatorPresentation(accepted.token);
    _actionIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeActionCreated(ActionCommandAccepted accepted) {
    const revision = TestDetailsRevision(7);
    final action = _action();
    repository.completeActionCommand(
      _actionIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: ActionCreated(
            action: action,
            changes: [ActionCreatedChange(revision: revision, action: action)],
          ),
        ),
      ),
    );
  }

  ActionCommandAccepted startActionUpdate() {
    final commandIndex = repository.actionCommands.length;
    final accepted = _coordinator.acceptActionUpdate(
      UpdateActionFields(
        actionId: _actionId,
        patch: const ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
      ),
    ) as ActionCommandAccepted;
    _coordinator.releaseInitiatorPresentation(accepted.token);
    _actionIndexes[accepted] = commandIndex;
    return accepted;
  }

  ActionCommandAccepted startActionDelete() {
    final commandIndex = repository.actionCommands.length;
    final accepted = _coordinator.acceptActionDelete(
      DeleteAction(_actionId),
    ) as ActionCommandAccepted;
    _coordinator.releaseInitiatorPresentation(accepted.token);
    _actionIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeActionUpdated(ActionCommandAccepted accepted) {
    const revision = TestDetailsRevision(7);
    final action = _action();
    repository.completeActionCommand(
      _actionIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: ActionFieldsUpdated(
            action: action,
            changes: [
              ActionUpdatedChange(
                revision: revision,
                before: action,
                after: action,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void completeActionDeleted(ActionCommandAccepted accepted) {
    const revision = TestDetailsRevision(7);
    final action = _action();
    repository.completeActionCommand(
      _actionIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: ActionDeleted(
            action: action,
            changes: [ActionDeletedChange(revision: revision, action: action)],
          ),
        ),
      ),
    );
  }

  action_domain.Action _action() => action_domain.Action(
    id: _actionId,
    title: ActionTitle('Пробежка'),
    description: null,
    path: ActionPath([testDetailsIntentionId(1)]),
    date: CalendarDate.fromParts(2026, 9, 23),
    schedule: const ActionAllDay(),
    priority: ActionPriority.p4,
    isCompleted: false,
    creationSequence: action_domain.ActionCreationSequence(1),
    createdAt: action_domain.ActionTimestamp(DateTime.utc(2026, 9, 23)),
    updatedAt: action_domain.ActionTimestamp(DateTime.utc(2026, 9, 23)),
  );

  void completeActionFailure(
    ActionCommandAccepted accepted,
    ActionCommandFailure failure,
  ) => repository.completeActionCommand(
    _actionIndexes[accepted]!,
    GraphCommandFailed(failure),
  );

  IntentionCommandAccepted startKindChange() {
    final commandIndex = repository.commands.length;
    final accepted = _coordinator.acceptExisting(
      ChangeIntentionKind(testDetailsIntentionId(1), IntentionKind.supporting),
      presentationTitle: 'Намерение',
    ) as IntentionCommandAccepted;
    _commandIndexes[accepted] = commandIndex;
    return accepted;
  }

  IntentionCommandAccepted startArchive() {
    final commandIndex = repository.commands.length;
    final accepted = _coordinator.acceptExisting(
      givenArchiveIntention(testDetailsIntentionId(1)),
      presentationTitle: 'Намерение',
    ) as IntentionCommandAccepted;
    _coordinator.releaseInitiatorPresentation(accepted.token);
    _commandIndexes[accepted] = commandIndex;
    return accepted;
  }

  IntentionCommandAccepted startRestore() {
    final commandIndex = repository.commands.length;
    final accepted = _coordinator.acceptExisting(
      givenRestoreIntention(testDetailsIntentionId(1)),
      presentationTitle: 'Намерение',
    ) as IntentionCommandAccepted;
    _coordinator.releaseInitiatorPresentation(accepted.token);
    _commandIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeIntentionCascade(
    IntentionCommandAccepted accepted,
    CascadeComposition composition,
  ) {
    const revision = TestDetailsRevision(0);
    repository.completeCommand(
      _commandIndexes[accepted]!,
      testDetailsSavedResult(
        testDetailsIntention(),
        additionalChanges: [
          CascadeOutcome(revision: revision, executed: composition),
        ],
      ),
    );
  }

  /// Операция страницы намерения, предпросмотр каскада которой не прочитан.
  void startPreviewFailure(
    CascadeOperation operation,
    CascadePreviewFailure failure,
  ) => _coordinator.acceptIntentionPreviewFailure(
    intentionId: testDetailsIntentionId(1),
    operation: operation,
    failure: failure,
    presentationTitle: 'Намерение',
  );

  IntentionCommandAccepted startDelete({
    required int index,
    required String title,
    bool releaseInitiator = true,
  }) {
    final intention = testDetailsIntention(index: index, title: title);
    final commandIndex = repository.commands.length;
    final accepted = _coordinator.acceptExisting(
      givenDeleteIntention(intention.id),
      presentationTitle: title,
    ) as IntentionCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _commandIndexes[accepted] = commandIndex;
    _titles[accepted] = (index, title);
    return accepted;
  }

  /// Создание с двумя тегами из отдельной формы.
  IntentionCommandAccepted startFullCreation({
    required bool releaseInitiator,
    IntentionCreationOperationTarget target =
        const CreatingIntentionOperationTarget(),
  }) {
    final commandIndex = repository.commands.length;
    final accepted = _coordinator.acceptCreation(
      IntentionCreationFormKey(),
      CreateIntention.withInitialState(
        title: 'Полное намерение',
        description: null,
        tagIds: [_tagId, _otherTagId],
      ),
      target: target,
    ) as IntentionCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _commandIndexes[accepted] = commandIndex;
    return accepted;
  }

  /// Подтверждает полное создание одним пакетом: каталожная мутация нового
  /// намерения и факт каждого назначения на одной ревизии.
  void completeFullCreated(IntentionCommandAccepted accepted) {
    const revision = TestDetailsRevision(10);
    final intention = testDetailsIntention(
      index: 7,
      title: 'Полное намерение',
      description: null,
    );
    repository.completeCommand(
      _commandIndexes[accepted]!,
      ResultSuccess(
        IntentionSaved(
          intention,
          catalogMutation: IntentionCatalogCreated(
            revision: revision,
            entry: _CreatedCatalogEntrySnapshot(testDetailsSummary(intention)),
          ),
          additionalChanges: [
            for (final tagId in [_tagId, _otherTagId])
              TagAssignmentChangedChange(
                revision: revision,
                assignment: TagAssignment(
                  tagId: tagId,
                  intentionId: intention.id,
                ),
                state: TagAssignmentState.assigned,
              ),
          ],
        ),
      ),
    );
  }

  void completeFailure(
    IntentionCommandAccepted accepted,
    IntentionFailure failure,
  ) => repository.completeCommand(
    _commandIndexes[accepted]!,
    ResultFailure(failure),
  );

  void completeDeleted(
    IntentionCommandAccepted accepted, {
    DeleteCascadeComposition? composition,
  }) {
    final (index, title) = _titles[accepted]!;
    final original = testDetailsDeletedResult(
      testDetailsIntention(index: index, title: title),
    ) as ResultSuccess<IntentionCommandSuccess>;
    repository.completeCommand(
      _commandIndexes[accepted]!,
      composition == null
          ? original
          : ResultSuccess(
              IntentionDeleted(
                (original.value as IntentionDeleted).id,
                catalogMutation: original.value.catalogMutation,
                additionalChanges: [
                  CascadeOutcome(
                    revision: const TestDetailsRevision(0),
                    executed: composition,
                  ),
                ],
              ),
            ),
    );
  }

  void completeUnavailable(IntentionCommandAccepted accepted) {
    repository.completeCommand(
      _commandIndexes[accepted]!,
      const ResultFailure(IntentionUnavailableFailure()),
    );
  }

  LongTermRelationCommandAccepted startRelationsAddition({
    int count = 1,
    bool releaseInitiator = true,
  }) {
    final commandIndex = repository.relationCommands.length;
    final accepted = _coordinator.acceptRelationsAddition(
      RelationsAdditionSearchKey(),
      AddLongTermRelations(
        pageIntentionId: testDetailsIntentionId(1),
        group: IntentionRelationGroup.needs,
        candidateIds: [
          for (var i = 0; i < count; i++) testDetailsIntentionId(i + 2),
        ],
      ),
    ) as LongTermRelationCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _relationIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeRelationsAdded(
    LongTermRelationCommandAccepted accepted,
    int count,
  ) {
    const revision = TestDetailsRevision(1);
    final relations = [
      for (var i = 0; i < count; i++)
        testDetailsRelationRow(
          ownerId: testDetailsIntentionId(1),
          index: i + 1,
          neighborId: testDetailsIntentionId(i + 2),
        ).relation,
    ];
    repository.completeRelationCommand(
      _relationIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationsAdded(
            relations: relations,
            changes: [
              for (final relation in relations)
                LongTermRelationCreatedChange(
                  revision: revision,
                  relation: relation,
                ),
            ],
          ),
        ),
      ),
    );
  }

  LongTermRelationCommandAccepted startRelationUpdate({
    bool releaseInitiator = true,
  }) {
    final commandIndex = repository.relationCommands.length;
    final accepted = _coordinator.acceptRelationUpdate(
      UpdateLongTermRelation(
        relationId: _relationId,
        patch: const LongTermRelationPatch(
          priority: LongTermRelationFieldSet(RelationPriority.p1),
        ),
      ),
    ) as LongTermRelationCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _relationIndexes[accepted] = commandIndex;
    return accepted;
  }

  LongTermRelationCommandAccepted startRelationArchive({
    bool releaseInitiator = true,
  }) => _startExistingRelationCommand(
    givenArchiveRelation(_relationId),
    releaseInitiator: releaseInitiator,
  );

  LongTermRelationCommandAccepted startRelationRestore({
    bool releaseInitiator = true,
  }) => _startExistingRelationCommand(
    givenRestoreRelation(_relationId),
    releaseInitiator: releaseInitiator,
  );

  LongTermRelationCommandAccepted startRelationDelete({
    bool releaseInitiator = true,
  }) => _startExistingRelationCommand(
    givenDeleteRelation(_relationId),
    releaseInitiator: releaseInitiator,
  );

  LongTermRelationCommandAccepted _startExistingRelationCommand(
    LongTermRelationCommand command, {
    required bool releaseInitiator,
  }) {
    final commandIndex = repository.relationCommands.length;
    final accepted = switch (command) {
      ArchiveLongTermRelation() => _coordinator.acceptRelationArchive(command),
      RestoreLongTermRelation() => _coordinator.acceptRelationRestore(command),
      DeleteLongTermRelation() => _coordinator.acceptRelationDelete(command),
      _ => throw ArgumentError.value(command, 'command'),
    } as LongTermRelationCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _relationIndexes[accepted] = commandIndex;
    return accepted;
  }

  GraphInitiatorPresentationClaim? claimInitiatorFailure(
    GraphOperationToken token,
  ) => _coordinator.claimInitiatorFailure(token);

  void releaseInitiatorClaim(GraphInitiatorPresentationClaim claim) =>
      _coordinator.releaseInitiatorClaim(claim);

  /// Подтверждает кадр инлайн-renderer, который владеет [claim].
  void confirmPresentation(GraphInitiatorPresentationClaim claim) =>
      _coordinator.confirmPresentation(claim);

  void completeRelationUpdated(LongTermRelationCommandAccepted accepted) {
    const revision = TestDetailsRevision(2);
    final before = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
      createdAt: RelationTimestamp(DateTime.utc(2026)),
      updatedAt: RelationTimestamp(DateTime.utc(2026)),
    );
    final after = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p1,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
      createdAt: RelationTimestamp(DateTime.utc(2026)),
      updatedAt: RelationTimestamp(DateTime.utc(2026)),
    );
    repository.completeRelationCommand(
      _relationIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationUpdated(
            before: before,
            relation: after,
            description: null,
            changes: <GraphChange>[
              LongTermRelationUpdatedChange(
                revision: revision,
                before: before,
                after: after,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void completeRelationArchived(
    LongTermRelationCommandAccepted accepted, {
    ArchiveCascadeComposition? composition,
  }) => _completeRelationScopeChanged(
    accepted,
    beforeScope: RelationScope.active,
    afterScope: RelationScope.archived,
    revision: 3,
    composition: composition,
  );

  void completeRelationRestored(
    LongTermRelationCommandAccepted accepted, {
    RestoreCascadeComposition? composition,
  }) => _completeRelationScopeChanged(
    accepted,
    beforeScope: RelationScope.archived,
    afterScope: RelationScope.active,
    revision: 4,
    composition: composition,
  );

  void completeRelationDeleted(
    LongTermRelationCommandAccepted accepted, {
    DeleteCascadeComposition? composition,
  }) {
    const revision = TestDetailsRevision(5);
    final relation = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
      createdAt: RelationTimestamp(DateTime.utc(2026)),
      updatedAt: RelationTimestamp(DateTime.utc(2026)),
    );
    repository.completeRelationCommand(
      _relationIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationDeleted(
            relation: relation,
            changes: <GraphChange>[
              LongTermRelationDeletedChange(
                revision: revision,
                relation: relation,
              ),
              if (composition != null)
                CascadeOutcome(revision: revision, executed: composition),
            ],
          ),
        ),
      ),
    );
  }

  void _completeRelationScopeChanged(
    LongTermRelationCommandAccepted accepted, {
    required RelationScope beforeScope,
    required RelationScope afterScope,
    required int revision,
    CascadeComposition? composition,
  }) {
    final graphRevision = TestDetailsRevision(revision);
    final before = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: beforeScope,
      creationSequence: RelationCreationSequence(1),
      createdAt: RelationTimestamp(DateTime.utc(2026)),
      updatedAt: RelationTimestamp(DateTime.utc(2026)),
    );
    final after = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: afterScope,
      creationSequence: RelationCreationSequence(1),
      createdAt: RelationTimestamp(DateTime.utc(2026)),
      updatedAt: RelationTimestamp(DateTime.utc(2026)),
    );
    repository.completeRelationCommand(
      _relationIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: LongTermRelationUpdated(
            before: before,
            relation: after,
            description: null,
            changes: <GraphChange>[
              LongTermRelationUpdatedChange(
                revision: graphRevision,
                before: before,
                after: after,
              ),
              if (composition != null)
                CascadeOutcome(revision: graphRevision, executed: composition),
            ],
          ),
        ),
      ),
    );
  }

  void completeRelationFailure(
    LongTermRelationCommandAccepted accepted,
    LongTermRelationCommandFailure failure,
  ) => repository.completeRelationCommand(
    _relationIndexes[accepted]!,
    GraphCommandFailed(failure),
  );

  GraphExportAccepted startExport() {
    final outcome = Completer<GraphExportOutcome>();
    final accepted = _coordinator.acceptExport(
      export: () => outcome.future,
      retry: () => exportRetries += 1,
    ) as GraphExportAccepted;
    _exports[accepted] = outcome;
    return accepted;
  }

  void completeExport(
    GraphExportAccepted accepted,
    GraphExportOutcome outcome,
  ) => _exports[accepted]!.complete(outcome);

  GraphBackupRestoreAccepted startBackupRestore() {
    final finish =
        Completer<
          Future<GraphBackupRestoreOutcome> Function(
            GraphExclusiveReplacement<GraphBackupRestored>,
          )
        >();
    final accepted = _coordinator.acceptBackupRestore(
      (exclusive) async => (await finish.future)(exclusive),
    ) as GraphBackupRestoreAccepted;
    _restores[accepted] = finish;
    return accepted;
  }

  void completeBackupRestored(GraphBackupRestoreAccepted accepted) =>
      _restores[accepted]!.complete(
        (GraphExclusiveReplacement<GraphBackupRestored> exclusive) =>
            exclusive.replace(
              () async => ConfirmedGraphReplacement(
                const TestDetailsRevision(0, epoch: 1),
              ),
            ),
      );

  void completeBackupRestore(
    GraphBackupRestoreAccepted accepted,
    GraphBackupRestoreOutcome outcome,
  ) => _restores[accepted]!.complete((_) async => outcome);

  void startManualBackup(ManualGraphBackupOutcome outcome) =>
      _coordinator.acceptManualBackup(() async => outcome);

  void startImported() => _coordinator.acceptImport(
    (exclusive) => exclusive.replace(
      () async =>
          ConfirmedGraphReplacement(const TestDetailsRevision(0, epoch: 1)),
    ),
  );

  GraphImportAccepted startImportFailed(GraphImportFailure failure) =>
      _coordinator.acceptImport((_) async => GraphImportFailed(failure))
          as GraphImportAccepted;
}

Future<_PresenterHarness> _pumpPresenterApp(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  bool alteredDeletionPunctuation = false,
}) async {
  final repository = ControlledDetailsRepository();
  final container = ProviderContainer(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  final presenterGeneration = ValueNotifier<int>(0);
  addTearDown(presenterGeneration.dispose);
  final currentLocale = ValueNotifier<Locale>(locale);
  addTearDown(currentLocale.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<Locale>(
        valueListenable: currentLocale,
        builder: (context, locale, _) => MaterialApp(
          locale: locale,
          localizationsDelegates: [
            if (alteredDeletionPunctuation) const _AlteredRussianDelegate(),
            ...AppLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ValueListenableBuilder<int>(
            valueListenable: presenterGeneration,
            builder: (context, generation, _) {
              final content = child ?? const SizedBox.shrink();
              return generation == _withoutPresenter
                  ? content
                  : GraphOperationPresenter(
                      key: ValueKey(generation),
                      child: content,
                    );
            },
          ),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    ),
  );
  await tester.pump();
  return _PresenterHarness(
    container,
    repository,
    presenterGeneration,
    currentLocale,
  );
}

class _AlteredRussianLocalizations extends AppLocalizationsRu {
  @override
  String get detailsDeleted => 'Намерение удалено!';

  @override
  String get relationDeleted => 'Связь удалена!';
}

class _AlteredRussianDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AlteredRussianDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ru';

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      _AlteredRussianLocalizations();

  @override
  bool shouldReload(_AlteredRussianDelegate old) => false;
}
