import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';
import '../../support/tag_assignment_changed.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
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

  // Обычное время показа — 4 с. Лист и диалог перекрывают страницу без
  // собственного Scaffold; лист закрывается и после этого времени, и до его
  // конца.
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
      'отдельных исходов готовности и назначений, '
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

  testWidgets(
    'показывает безопасный конфликт блокирующих связей в общей поверхности',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final operation = harness.startDelete(index: 3, title: 'Связанное');
      harness.completeBlockingRelations(operation);
      await tester.pumpAndSettle();

      expect(find.text(_linkedNotDeleted('Связанное')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final scenario in <({TagCommandKind kind, bool unchanged, String ru})>[
    (kind: TagCommandKind.create, unchanged: false, ru: 'Тег создан.'),
    (kind: TagCommandKind.rename, unchanged: false, ru: 'Тег переименован.'),
    (
      kind: TagCommandKind.rename,
      unchanged: true,
      ru: 'Название тега не изменилось.',
    ),
    (
      kind: TagCommandKind.delete,
      unchanged: false,
      ru: 'Тег удалён вместе со всеми назначениями.',
    ),
  ]) {
    testWidgets(
      'успех тега ${scenario.kind.name}, без изменения: ${scenario.unchanged}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: const Locale('ru'),
        );
        final accepted = harness.startTag(scenario.kind);
        harness.completeTagSuccess(
          accepted,
          scenario.kind,
          unchanged: scenario.unchanged,
        );
        await tester.pumpAndSettle();

        final operation = switch (scenario.kind) {
          TagCommandKind.create => 'Создание',
          TagCommandKind.rename => 'Изменение',
          TagCommandKind.delete => 'Удаление',
          TagCommandKind.assign || TagCommandKind.removeAssignment =>
            throw StateError('Сценарий проверяет жизненный цикл тега.'),
        };
        final message = '$operation — «тег»: ${scenario.ru}';
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

  testWidgets('несогласованный результат тега не объявляется успехом', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final accepted = harness.startTag(TagCommandKind.create);
    harness.completeTagSuccess(accepted, TagCommandKind.rename);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Create — “tag”: The tag operation failed because of an unexpected error.',
      ),
      findsOneWidget,
    );
    expect(find.text('Create — “tag”: Tag renamed.'), findsNothing);
    await _closeMessage(tester);
  });

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
      ru: 'Тег с таким названием уже есть. Выберите другое название или используйте существующий тег.',
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

  testWidgets(
    'тег ждёт сообщения графа и передаёт отказ оболочке после закрытия формы',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 1, title: 'Граф');
      final tag = harness.startTag(
        TagCommandKind.create,
        releaseInitiator: false,
      );
      harness.completeDeleted(intention);
      harness.completeTagFailure(tag, const TagUnavailableFailure());
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Граф')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);

      harness.releaseInitiatorPresentation(tag.token);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Create — “tag”: Could not complete the tag operation. Try again.',
        ),
        findsOneWidget,
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final scenario in <({TagCommandKind kind, bool unchanged, String ru})>[
    (kind: TagCommandKind.assign, unchanged: false, ru: 'Тег назначен.'),
    (kind: TagCommandKind.assign, unchanged: true, ru: 'Тег уже назначен.'),
    (
      kind: TagCommandKind.removeAssignment,
      unchanged: false,
      ru: 'Назначение тега снято.',
    ),
    (
      kind: TagCommandKind.removeAssignment,
      unchanged: true,
      ru: 'Назначение тега уже отсутствует.',
    ),
  ]) {
    testWidgets('исход назначения ${scenario.kind.name}, ${scenario.unchanged}', (
      tester,
    ) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final accepted = harness.startTag(scenario.kind);
      harness.completeTagSuccess(
        accepted,
        scenario.kind,
        unchanged: scenario.unchanged,
      );
      await tester.pumpAndSettle();

      final message =
          '${scenario.kind == TagCommandKind.assign ? 'Назначение' : 'Снятие'} — «назначение тега»: ${scenario.ru}';
      expect(find.text(message), findsOneWidget);
      await _closeMessage(tester);
    });
  }

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

  for (final scenario in <({DailyChoiceValidationField field, String ru})>[
    (
      field: DailyChoiceValidationField.sourceIntention,
      ru: 'Проверьте исходное намерение дневного выбора.',
    ),
    (
      field: DailyChoiceValidationField.selectedIntention,
      ru: 'Проверьте выбранное намерение дневного выбора.',
    ),
    (
      field: DailyChoiceValidationField.date,
      ru: 'Проверьте дату дневного выбора.',
    ),
    (
      field: DailyChoiceValidationField.description,
      ru: 'Проверьте описание дневного выбора.',
    ),
  ]) {
    testWidgets('ошибка поля ${scenario.field.name} объяснена', (tester) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final update = harness.startDailyChoiceUpdate();
      harness.completeDailyChoiceFailure(
        update,
        DailyChoiceValidationFailure(scenario.field),
      );
      await tester.pumpAndSettle();

      final message = 'Изменение — «дневной выбор»: ${scenario.ru}';
      expect(find.text(message), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  for (final scenario in <({DailyChoiceCommandFailure failure, String ru})>[
    (
      failure: const DailyChoiceNotFoundFailure(),
      ru: 'Дневной выбор больше не существует.',
    ),
    (
      failure: const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.dependencyChanged,
      ),
      ru: 'Данные изменились. Обновите их и подтвердите снова.',
    ),
    (
      failure: const DailyChoiceUnavailableFailure(),
      ru: 'Не удалось выполнить действие с дневным выбором. Повторите попытку.',
    ),
    (
      failure: const DailyChoiceCorruptionFailure(),
      ru: 'Сохранённые данные повреждены. Дневной выбор не изменён.',
    ),
    (
      failure: const DailyChoiceUnexpectedFailure(),
      ru: 'Действие с дневным выбором не выполнено из-за непредвиденной ошибки.',
    ),
  ]) {
    testWidgets('отказ ${scenario.failure.runtimeType} безопасен', (
      tester,
    ) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final update = harness.startDailyChoiceUpdate();
      harness.completeDailyChoiceFailure(update, scenario.failure);
      await tester.pumpAndSettle();

      final message = 'Изменение — «дневной выбор»: ${scenario.ru}';
      expect(find.text(message), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets(
    'дневной выбор предъявляет успех лишь после подтверждения записи',
    (tester) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final deletion = harness.startDailyChoiceDelete(releaseInitiator: false);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);

      harness.completeDailyChoiceDeleted(deletion);
      await tester.pumpAndSettle();
      expect(
        find.text('Удаление — «дневной выбор»: Дневной выбор удалён.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: 'Удаление — «дневной выбор»: Дневной выбор удалён.',
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final scenario in <({DailyChoiceCommandKind kind, String message})>[
    (
      kind: DailyChoiceCommandKind.create,
      message: 'Create — “daily choice”: Daily choice created.',
    ),
    (
      kind: DailyChoiceCommandKind.update,
      message: 'Edit — “daily choice”: Daily choice updated.',
    ),
    (
      kind: DailyChoiceCommandKind.replace,
      message: 'Edit — “daily choice”: Daily choice path replaced.',
    ),
  ]) {
    testWidgets(
      'успех дневной команды ${scenario.kind.name} предъявляется один раз',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        final accepted = harness.startDailyChoice(scenario.kind);
        harness.completeDailyChoiceSuccess(accepted, scenario.kind);
        await tester.pumpAndSettle();

        expect(find.text(scenario.message), findsOneWidget);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  const pathDependency = (
    locale: Locale('ru'),
    message:
        'Изменение — «связь»: Связь используется в сохранённом дневном '
        'пути. Её тип и участников нельзя изменить.',
  );
  testWidgets(
    'конфликт зависимости пути объяснён для ${pathDependency.locale.languageCode}',
    (tester) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: pathDependency.locale,
      );
      final update = harness.startRelationUpdate();
      harness.completeRelationFailure(
        update,
        LongTermRelationReferencedByDailyPathFailure(_relationId),
      );
      await tester.pumpAndSettle();

      expect(find.text(pathDependency.message), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

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
    'успех изменения связи ждёт сообщение намерения в той же очереди',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 1, title: 'Намерение');
      final relation = harness.startRelationUpdate();
      harness.completeDeleted(intention);
      harness.completeRelationUpdated(relation);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Намерение')), findsOneWidget);
      expect(find.text(_relationUpdated), findsNothing);

      await _closeMessage(tester);
      expect(find.text(_relationUpdated), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'архивирование и восстановление связи используют общую очередь результатов',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 1, title: 'Намерение');
      final archive = harness.startRelationArchive();
      harness.completeDeleted(intention);
      harness.completeRelationArchived(archive);
      await archive.future;

      final restore = harness.startRelationRestore();
      harness.completeRelationRestored(restore);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Намерение')), findsOneWidget);
      expect(find.text(_relationArchived), findsNothing);
      expect(find.text(_relationRestored), findsNothing);

      await _closeMessage(tester);
      expect(find.text(_relationArchived), findsNothing);
      expect(find.text('$_relationRestored · 1 more'), findsOneWidget);

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

  testWidgets('массовый успех на английском называет операцию и намерение', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final deletion = harness.startBlockingRelationsDelete(title: 'Связанное');
    harness.completeBlockingRelationsDeleted(deletion);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Delete selected relations — “Связанное”: Selected relations deleted.',
      ),
      findsOneWidget,
    );
    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'ошибка массовой операции остаётся у открытого инициатора до его ухода',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final deletion = harness.startBlockingRelationsDelete(
        title: 'Связанное',
        releaseInitiator: false,
      );
      harness.completeBlockingRelationsFailure(
        deletion,
        const DeleteBlockingRelationsUnavailableFailure(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      harness.releaseInitiatorClaim(
        harness.claimInitiatorFailure(deletion.token)!,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Delete selected relations — “Связанное”: Selected relations couldn’t be deleted. Try again.',
        ),
        findsOneWidget,
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  // Английский текст массового успеха проверяет отдельный тест выше.
  const massDeleted = (
    locale: Locale('ru'),
    message:
        'Удаление выбранных связей — «Связанное»: Выбранные связи удалены.',
  );
  testWidgets(
    'массовый успех локализуется для ${massDeleted.locale.languageCode}',
    (tester) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: massDeleted.locale,
      );
      final deletion = harness.startBlockingRelationsDelete(title: 'Связанное');
      harness.completeBlockingRelationsDeleted(deletion);
      await tester.pumpAndSettle();
      expect(find.text(massDeleted.message), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'массовый конфликт на русском не раскрывает идентификатор связи',
    (tester) async {
      final harness = await _pumpPresenterApp(
        tester,
        locale: const Locale('ru'),
      );
      final deletion = harness.startBlockingRelationsDelete(title: 'Связанное');
      harness.completeBlockingRelationsFailure(
        deletion,
        DeleteBlockingRelationsSelectionConflictFailure.longTerm(
          relationId: _relationId,
          reason: BlockingRelationConflictReason.relationMissing,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Удаление выбранных связей — «Связанное»: Выбранный набор устарел. Обновите выбор и подтвердите его снова.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('018f47c2'), findsNothing);
      await _closeMessage(tester);
    },
  );

  for (final scenario
      in <({DeleteBlockingRelationsFailure failure, String outcome})>[
        (
          failure: DeleteBlockingRelationsIntentionNotFoundFailure(
            testDetailsIntentionId(1),
          ),
          outcome:
              'This intention no longer exists. Relations weren’t deleted.',
        ),
        (
          failure: const DeleteBlockingRelationsUnavailableFailure(),
          outcome: 'Selected relations couldn’t be deleted. Try again.',
        ),
        (
          failure: const DeleteBlockingRelationsCorruptionFailure(),
          outcome:
              'Stored data is damaged. Selected relations weren’t deleted.',
        ),
        (
          failure: const DeleteBlockingRelationsUnexpectedFailure(),
          outcome: 'Selected relations couldn’t be deleted because of an unexpected error.',
        ),
      ]) {
    testWidgets(
      'массовый отказ ${scenario.failure.runtimeType} безопасен на английском',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        final deletion = harness.startBlockingRelationsDelete(
          title: 'Связанное',
        );
        harness.completeBlockingRelationsFailure(deletion, scenario.failure);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Delete selected relations — “Связанное”: ${scenario.outcome}',
          ),
          findsOneWidget,
        );
        await _closeMessage(tester);
      },
    );
  }

  for (final scenario in <({RelationParticipantRole role, String outcome})>[
    (
      role: RelationParticipantRole.source,
      outcome: 'Restore the source intention before restoring this relation.',
    ),
    (
      role: RelationParticipantRole.related,
      outcome: 'Restore the related intention before restoring this relation.',
    ),
  ]) {
    testWidgets(
      'восстановление объясняет архивного участника ${scenario.role.name}',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        final restore = harness.startRelationRestore();
        harness.completeRelationFailure(
          restore,
          LongTermRelationParticipantArchivedFailure(
            role: scenario.role,
            intentionId: testDetailsIntentionId(1),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(_relationRestoreOutcome(scenario.outcome)),
          findsOneWidget,
        );

        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('восстановление связи предъявляется на русском языке', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester, locale: const Locale('ru'));
    final restore = harness.startRelationRestore();
    harness.completeRelationFailure(
      restore,
      LongTermRelationParticipantArchivedFailure(
        role: RelationParticipantRole.related,
        intentionId: testDetailsIntentionId(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Восстановление — «связь»: Сначала восстановите связанное намерение, '
        'затем восстановите эту связь.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('успех создания связи сразу предъявляется общей поверхностью', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final relation = harness.startRelationCreation(releaseInitiator: false);
    harness.completeRelationCreated(relation);
    await tester.pumpAndSettle();

    expect(find.text(_relationCreated), findsOneWidget);

    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final scenario in _relationFailures) {
    testWidgets(
      'переданная ошибка создания связи «${scenario.name}» предъявляется безопасным текстом',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        final relation = harness.startRelationCreation();
        harness.completeRelationFailure(relation, scenario.failure);
        await tester.pumpAndSettle();

        expect(find.text(_relationOutcome(scenario.outcome)), findsOneWidget);

        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

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

String _linkedNotDeleted(String title) =>
    'Delete — “$title”: The intention wasn’t deleted: its relations still '
    'block deletion. Archived relations and relations that aren’t loaded yet '
    'block it too.';

String _relationOutcome(String outcome) => 'Create — “new relation”: $outcome';

final _relationCreated = _relationOutcome('Relation created.');

String _relationUpdateOutcome(String outcome) => 'Edit — “relation”: $outcome';

final _relationUpdated = _relationUpdateOutcome('Relation updated.');

String _relationArchiveOutcome(String outcome) =>
    'Archive — “relation”: $outcome';

final _relationArchived = _relationArchiveOutcome('Relation archived.');

String _relationRestoreOutcome(String outcome) =>
    'Restore — “relation”: $outcome';

final _relationRestored = _relationRestoreOutcome('Relation restored.');

String _relationDeleteOutcome(String outcome) =>
    'Delete — “relation”: $outcome';

final _relationFailures =
    <({String name, LongTermRelationCommandFailure failure, String outcome})>[
      (
        name: 'validation',
        failure: const LongTermRelationCommandValidationFailure(
          CreateLongTermRelationValidationFailure.sameIntention,
        ),
        outcome: 'Check the selected intentions and relation details.',
      ),
      (
        name: 'conflict',
        failure: LongTermRelationPairOccupiedFailure(_relationId),
        outcome:
            'A relation with this direction already exists between the '
            'selected intentions.',
      ),
      (
        name: 'notFound',
        failure: LongTermRelationParticipantNotFoundFailure(
          role: RelationParticipantRole.related,
          intentionId: testDetailsIntentionId(2),
        ),
        outcome: 'One of the selected intentions no longer exists.',
      ),
      (
        name: 'archived',
        failure: LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.source,
          intentionId: testDetailsIntentionId(1),
        ),
        outcome: 'Only active intentions can be linked.',
      ),
      (
        name: 'unavailable',
        failure: const LongTermRelationUnavailableFailure(),
        outcome: 'The relation couldn’t be created. Try again.',
      ),
      (
        name: 'corruption',
        failure: const LongTermRelationCorruptionFailure(),
        outcome: 'Stored data is damaged. The relation wasn’t created.',
      ),
      (
        name: 'unexpected',
        failure: const LongTermRelationUnexpectedFailure(),
        outcome:
            'The relation couldn’t be created because of an unexpected '
            'error.',
      ),
    ];

final _relationUpdateFailures =
    <({String name, LongTermRelationCommandFailure failure, String outcome})>[
      (
        name: 'validation',
        failure: const LongTermRelationCommandValidationFailure(
          CreateLongTermRelationValidationFailure.sameIntention,
        ),
        outcome: 'Check the selected intentions and relation changes.',
      ),
      (
        name: 'pair conflict',
        failure: LongTermRelationPairOccupiedFailure(_otherRelationId),
        outcome:
            'A relation with this direction already exists between the '
            'selected intentions.',
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
        outcome: 'One of the selected intentions no longer exists.',
      ),
      (
        name: 'participant archived',
        failure: LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.source,
          intentionId: testDetailsIntentionId(1),
        ),
        outcome: 'An active relation can only link active intentions.',
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
        outcome:
            'The relation couldn’t be updated because of an unexpected '
            'error.',
      ),
    ];

final _relationDeleteFailures =
    <({String name, LongTermRelationCommandFailure failure, String outcome})>[
      (
        name: 'validation',
        failure: const LongTermRelationCommandValidationFailure(
          CreateLongTermRelationValidationFailure.sameIntention,
        ),
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

final _dailyChoiceId = switch (DailyChoiceId.decode(
  '018f1400-0000-7000-8000-000000000001',
)) {
  DailyChoiceIdDecodingSuccess(:final id) => id,
  InvalidDailyChoiceIdDecoding() => throw StateError(
    'Некорректный ID дневного выбора.',
  ),
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

final _choicePathStepId = switch (ChoicePathStepId.decode(
  '018f1400-0000-7000-8000-000000000002',
)) {
  ChoicePathStepIdDecodingSuccess(:final id) => id,
  InvalidChoicePathStepIdDecoding() => throw StateError(
    'Некорректный ID шага пути.',
  ),
};

final class _PresentationOnlyChange implements GraphChange {
  const _PresentationOnlyChange(this.revision);

  @override
  final GraphRevision revision;
}

Future<void> _openSheet(BuildContext context) => showDoableSheet<void>(
  context: context,
  builder: (_) => const Sheet(title: 'Лист', child: SizedBox(height: 120)),
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
  final _blockingIndexes = <BlockingRelationsDeleteAccepted, int>{};
  final _dailyChoiceIndexes = <DailyChoiceCommandAccepted, int>{};
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

  TagCommandAccepted startTag(
    TagCommandKind kind, {
    bool releaseInitiator = true,
  }) {
    final commandIndex = repository.tagCommands.length;
    final accepted = switch (kind) {
      TagCommandKind.create => _coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(TagName.fromInput('Планы')),
      ),
      TagCommandKind.rename => _coordinator.acceptTagRename(
        RenameTag(tagId: _tagId, name: TagName.fromInput('Новое имя')),
      ),
      TagCommandKind.delete => _coordinator.acceptTagDelete(DeleteTag(_tagId)),
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
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _tagIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeTagSuccess(
    TagCommandAccepted accepted,
    TagCommandKind kind, {
    bool unchanged = false,
  }) {
    const revision = TestDetailsRevision(8);
    final before = Tag(
      id: _tagId,
      name: TagName.fromInput('Планы'),
      color: null,
    );
    final after = Tag(
      id: _tagId,
      name: TagName.fromInput('Новое имя'),
      color: before.color,
    );
    final success = switch (kind) {
      TagCommandKind.create => TagCreated(
        TagCreatedChange(revision: revision, after: before),
      ),
      TagCommandKind.rename when unchanged => TagUnchanged(
        TagUnchangedChange(revision: revision, tag: before),
      ),
      TagCommandKind.rename => TagRenamed(
        TagRenamedChange(revision: revision, before: before, after: after),
      ),
      TagCommandKind.delete => TagDeleted(
        TagDeletedChange(revision: revision, tagId: _tagId),
      ),
      TagCommandKind.assign || TagCommandKind.removeAssignment =>
        unchanged
            ? TagAssignmentUnchanged(
                TagAssignmentUnchangedChange(
                  revision: revision,
                  assignment: TagAssignment(
                    tagId: _tagId,
                    intentionId: testDetailsIntentionId(1),
                  ),
                  state: kind == TagCommandKind.assign
                      ? TagAssignmentState.assigned
                      : TagAssignmentState.absent,
                ),
              )
            : testTagAssignmentChanged(
                TagAssignmentChangedChange(
                  revision: revision,
                  assignment: TagAssignment(
                    tagId: _tagId,
                    intentionId: testDetailsIntentionId(1),
                  ),
                  state: kind == TagCommandKind.assign
                      ? TagAssignmentState.assigned
                      : TagAssignmentState.absent,
                ),
              ),
    };
    repository.completeTagCommand(
      _tagIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(revision: revision, value: success),
      ),
    );
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

  DailyChoiceCommandAccepted startDailyChoice(DailyChoiceCommandKind kind) =>
      switch (kind) {
        DailyChoiceCommandKind.create => _startDailyChoiceCreate(),
        DailyChoiceCommandKind.update => startDailyChoiceUpdate(),
        DailyChoiceCommandKind.replace => _startDailyChoiceReplace(),
        DailyChoiceCommandKind.delete => startDailyChoiceDelete(),
      };

  ConfirmedChoicePath _confirmedChoicePath() => ConfirmedChoicePath([
    ConfirmedChoicePathStep(
      relationId: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      type: LongTermRelationType.need,
      relatedIntentionId: testDetailsIntentionId(2),
    ),
  ]);

  DailyChoiceCommandAccepted _startDailyChoiceCreate() {
    final commandIndex = repository.dailyChoiceCommands.length;
    final accepted = _coordinator.acceptDailyChoiceCreation(
      DailyChoiceCreationFormKey(),
      CreateDailyChoice(
        sourceIntentionId: testDetailsIntentionId(1),
        selectedIntentionId: testDetailsIntentionId(2),
        path: _confirmedChoicePath(),
        date: CalendarDate.fromParts(2026, 9, 23),
        description: null,
        isCompleted: false,
      ),
    ) as DailyChoiceCommandAccepted;
    _coordinator.releaseInitiatorPresentation(accepted.token);
    _dailyChoiceIndexes[accepted] = commandIndex;
    return accepted;
  }

  DailyChoiceCommandAccepted _startDailyChoiceReplace() {
    final commandIndex = repository.dailyChoiceCommands.length;
    final accepted = _coordinator.acceptDailyChoiceReplace(
      ReplaceDailyChoicePath(
        choiceId: _dailyChoiceId,
        sourceIntentionId: testDetailsIntentionId(1),
        selectedIntentionId: testDetailsIntentionId(2),
        path: _confirmedChoicePath(),
      ),
    ) as DailyChoiceCommandAccepted;
    _coordinator.releaseInitiatorPresentation(accepted.token);
    _dailyChoiceIndexes[accepted] = commandIndex;
    return accepted;
  }

  DailyChoiceCommandAccepted startDailyChoiceUpdate({
    bool releaseInitiator = true,
  }) {
    final commandIndex = repository.dailyChoiceCommands.length;
    final accepted = _coordinator.acceptDailyChoiceUpdate(
      UpdateDailyChoiceFields(
        choiceId: _dailyChoiceId,
        patch: const DailyChoiceFieldsPatch(
          isCompleted: DailyChoiceFieldSet(true),
        ),
      ),
    ) as DailyChoiceCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _dailyChoiceIndexes[accepted] = commandIndex;
    return accepted;
  }

  DailyChoiceCommandAccepted startDailyChoiceDelete({
    bool releaseInitiator = true,
  }) {
    final commandIndex = repository.dailyChoiceCommands.length;
    final accepted = _coordinator.acceptDailyChoiceDelete(
      DeleteDailyChoice(_dailyChoiceId),
    ) as DailyChoiceCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _dailyChoiceIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeDailyChoiceDeleted(DailyChoiceCommandAccepted accepted) {
    const revision = TestDetailsRevision(7);
    repository.completeDailyChoiceCommand(
      _dailyChoiceIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: DailyChoiceDeleted(
            choice: DailyChoice(
              id: _dailyChoiceId,
              sourceIntentionId: testDetailsIntentionId(1),
              selectedIntentionId: testDetailsIntentionId(2),
              date: CalendarDate.fromParts(2026, 9, 23),
              description: null,
              isCompleted: false,
            ),
            changes: const [_PresentationOnlyChange(revision)],
          ),
        ),
      ),
    );
  }

  void completeDailyChoiceSuccess(
    DailyChoiceCommandAccepted accepted,
    DailyChoiceCommandKind kind,
  ) {
    const revision = TestDetailsRevision(7);
    final choice = DailyChoice(
      id: _dailyChoiceId,
      sourceIntentionId: testDetailsIntentionId(1),
      selectedIntentionId: testDetailsIntentionId(2),
      date: CalendarDate.fromParts(2026, 9, 23),
      description: null,
      isCompleted: false,
    );
    final path = StoredChoicePath([
      ChoicePathStep(
        id: _choicePathStepId,
        dailyChoiceId: _dailyChoiceId,
        relationId: _relationId,
        previousStepId: null,
      ),
    ]);
    final changes = <GraphChange>[const _PresentationOnlyChange(revision)];
    final success = switch (kind) {
      DailyChoiceCommandKind.create => DailyChoiceCreated(
        choice: choice,
        path: path,
        changes: changes,
      ),
      DailyChoiceCommandKind.update => DailyChoiceFieldsUpdated(
        before: choice,
        choice: choice,
        path: path,
        changes: changes,
      ),
      DailyChoiceCommandKind.replace => DailyChoicePathReplaced(
        before: choice,
        choice: choice,
        path: path,
        changes: changes,
      ),
      DailyChoiceCommandKind.delete => DailyChoiceDeleted(
        choice: choice,
        changes: changes,
      ),
    };
    repository.completeDailyChoiceCommand(
      _dailyChoiceIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(revision: revision, value: success),
      ),
    );
  }

  void completeDailyChoiceFailure(
    DailyChoiceCommandAccepted accepted,
    DailyChoiceCommandFailure failure,
  ) => repository.completeDailyChoiceCommand(
    _dailyChoiceIndexes[accepted]!,
    GraphCommandFailed(failure),
  );

  BlockingRelationsDeleteAccepted startBlockingRelationsDelete({
    required String title,
    bool releaseInitiator = true,
  }) {
    final commandIndex = repository.blockingRelationsCommands.length;
    final accepted = _coordinator.acceptBlockingRelationsDelete(
      DeleteBlockingRelations.longTerm(
        intentionId: testDetailsIntentionId(1),
        relationIds: {_relationId},
      ),
      presentationTitle: title,
    ) as BlockingRelationsDeleteAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _blockingIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeBlockingRelationsDeleted(
    BlockingRelationsDeleteAccepted accepted,
  ) {
    const revision = TestDetailsRevision(6);
    final relation = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
    );
    final command =
        repository.blockingRelationsCommands[_blockingIndexes[accepted]!];
    repository.completeBlockingRelationsCommand(
      _blockingIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: BlockingRelationsDeleted(
            command: command,
            revision: revision,
            deletedRelations: [relation],
            counts: {
              testDetailsIntentionId(1): testRelationCounts(),
              testDetailsIntentionId(2): testRelationCounts(),
            },
          ),
        ),
      ),
    );
  }

  void completeBlockingRelationsFailure(
    BlockingRelationsDeleteAccepted accepted,
    DeleteBlockingRelationsFailure failure,
  ) => repository.completeBlockingRelationsCommand(
    _blockingIndexes[accepted]!,
    GraphCommandFailed(failure),
  );

  IntentionCommandAccepted startDelete({
    required int index,
    required String title,
    bool releaseInitiator = true,
  }) {
    final intention = testDetailsIntention(index: index, title: title);
    final commandIndex = repository.commands.length;
    final accepted = _coordinator.acceptExisting(
      DeleteIntention(intention.id),
      presentationTitle: title,
    ) as IntentionCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _commandIndexes[accepted] = commandIndex;
    _titles[accepted] = (index, title);
    return accepted;
  }

  /// Создание с готовностью и двумя тегами из отдельной формы.
  IntentionCommandAccepted startFullCreation({required bool releaseInitiator}) {
    final commandIndex = repository.commands.length;
    final accepted = _coordinator.acceptCreation(
      IntentionCreationFormKey(),
      CreateIntention.withInitialState(
        title: 'Полное намерение',
        description: null,
        readiness: IntentionReadiness.ready,
        tagIds: [_tagId, _otherTagId],
      ),
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
      readiness: IntentionReadiness.ready,
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

  void completeDeleted(IntentionCommandAccepted accepted) {
    final (index, title) = _titles[accepted]!;
    repository.completeCommand(
      _commandIndexes[accepted]!,
      testDetailsDeletedResult(
        testDetailsIntention(index: index, title: title),
      ),
    );
  }

  void completeUnavailable(IntentionCommandAccepted accepted) {
    repository.completeCommand(
      _commandIndexes[accepted]!,
      const ResultFailure(IntentionUnavailableFailure()),
    );
  }

  LongTermRelationCommandAccepted startRelationCreation({
    bool releaseInitiator = true,
  }) {
    final commandIndex = repository.relationCommands.length;
    final accepted = _coordinator.acceptRelationCreation(
      LongTermRelationCreationFormKey(),
      CreateLongTermRelation(
        sourceIntentionId: testDetailsIntentionId(1),
        relatedIntentionId: testDetailsIntentionId(2),
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    ) as LongTermRelationCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _relationIndexes[accepted] = commandIndex;
    return accepted;
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
    ArchiveLongTermRelation(_relationId),
    releaseInitiator: releaseInitiator,
  );

  LongTermRelationCommandAccepted startRelationRestore({
    bool releaseInitiator = true,
  }) => _startExistingRelationCommand(
    RestoreLongTermRelation(_relationId),
    releaseInitiator: releaseInitiator,
  );

  LongTermRelationCommandAccepted startRelationDelete({
    bool releaseInitiator = true,
  }) => _startExistingRelationCommand(
    DeleteLongTermRelation(_relationId),
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

  void completeRelationCreated(LongTermRelationCommandAccepted accepted) {
    const revision = TestDetailsRevision(1);
    final relation = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
    );
    repository.completeRelationCommand(
      _relationIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationCreated(
            relation: relation,
            description: null,
            changes: <GraphChange>[
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
    );
    final after = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p1,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
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

  void completeRelationArchived(LongTermRelationCommandAccepted accepted) =>
      _completeRelationScopeChanged(
        accepted,
        beforeScope: RelationScope.active,
        afterScope: RelationScope.archived,
        revision: 3,
      );

  void completeRelationRestored(LongTermRelationCommandAccepted accepted) =>
      _completeRelationScopeChanged(
        accepted,
        beforeScope: RelationScope.archived,
        afterScope: RelationScope.active,
        revision: 4,
      );

  void completeRelationDeleted(LongTermRelationCommandAccepted accepted) {
    const revision = TestDetailsRevision(5);
    final relation = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
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
    );
    final after = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: afterScope,
      creationSequence: RelationCreationSequence(1),
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

  void completeBlockingRelations(IntentionCommandAccepted accepted) {
    final (index, _) = _titles[accepted]!;
    final intentionId = testDetailsIntention(index: index).id;
    repository.completeCommand(
      _commandIndexes[accepted]!,
      ResultFailure(IntentionHasBlockingRelationsFailure(intentionId)),
    );
  }

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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
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
