import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'показывает результаты по одному без вытеснения текущего сообщения',
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

  for (final scenario
      in <({TagCommandKind kind, bool unchanged, String en, String ru})>[
        (
          kind: TagCommandKind.create,
          unchanged: false,
          en: 'Tag created.',
          ru: 'Тег создан.',
        ),
        (
          kind: TagCommandKind.rename,
          unchanged: false,
          en: 'Tag renamed.',
          ru: 'Тег переименован.',
        ),
        (
          kind: TagCommandKind.rename,
          unchanged: true,
          en: 'Tag name unchanged.',
          ru: 'Название тега не изменилось.',
        ),
        (
          kind: TagCommandKind.delete,
          unchanged: false,
          en: 'Tag deleted with all its assignments.',
          ru: 'Тег удалён вместе со всеми назначениями.',
        ),
      ]) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets(
        'успех тега ${scenario.kind.name}, без изменения: ${scenario.unchanged}, ${locale.languageCode}',
        (tester) async {
          final harness = await _pumpPresenterApp(tester, locale: locale);
          final accepted = harness.startTag(scenario.kind);
          harness.completeTagSuccess(
            accepted,
            scenario.kind,
            unchanged: scenario.unchanged,
          );
          await tester.pumpAndSettle();

          final operation = locale.languageCode == 'ru'
              ? switch (scenario.kind) {
                  TagCommandKind.create => 'Создание',
                  TagCommandKind.rename => 'Изменение',
                  TagCommandKind.delete => 'Удаление',
                }
              : switch (scenario.kind) {
                  TagCommandKind.create => 'Create',
                  TagCommandKind.rename => 'Edit',
                  TagCommandKind.delete => 'Delete',
                };
          final message = locale.languageCode == 'ru'
              ? '$operation — «тег»: ${scenario.ru}'
              : '$operation — “tag”: ${scenario.en}';
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

  for (final scenario in <({TagCommandFailure failure, String en, String ru})>[
    (
      failure: const TagNameInputFailure(
        TagNameFailureReason.invalidUnicodeRepertoire,
      ),
      en: 'Tag name contains invalid characters.',
      ru: 'Название тега содержит недопустимые символы.',
    ),
    (
      failure: const TagNameInputFailure(TagNameFailureReason.empty),
      en: 'Enter a tag name.',
      ru: 'Введите название тега.',
    ),
    (
      failure: const TagNameInputFailure(TagNameFailureReason.tooLong),
      en: 'Tag name must contain no more than 255 visible characters.',
      ru: 'Название тега должно содержать не более 255 отображаемых символов.',
    ),
    (
      failure: const TagNameInputFailure(TagNameFailureReason.nonCanonical),
      en: 'Remove whitespace around the tag name.',
      ru: 'Удалите пробелы по краям названия тега.',
    ),
    (
      failure: TagNameOccupiedFailure(_tagId),
      en: 'A tag with this name already exists. Choose another name or use the existing tag.',
      ru: 'Тег с таким названием уже есть. Выберите другое название или используйте существующий тег.',
    ),
    (
      failure: TagNotFoundFailure(_tagId),
      en: 'This tag no longer exists. Refresh the catalog.',
      ru: 'Этого тега больше нет. Обновите каталог.',
    ),
    (
      failure: const TagUnavailableFailure(),
      en: 'Could not complete the tag operation. Try again.',
      ru: 'Не удалось выполнить действие с тегом. Повторите попытку.',
    ),
    (
      failure: const TagCorruptionFailure(),
      en: 'Stored tag data is damaged. The tag was not changed.',
      ru: 'Сохранённые данные тега повреждены. Тег не изменён.',
    ),
    (
      failure: const TagUnexpectedFailure(),
      en: 'The tag operation failed because of an unexpected error.',
      ru: 'Действие с тегом не выполнено из-за непредвиденной ошибки.',
    ),
  ]) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets(
        'отказ тега ${scenario.failure.runtimeType} безопасен для ${locale.languageCode}',
        (tester) async {
          final harness = await _pumpPresenterApp(tester, locale: locale);
          final accepted = harness.startTag(TagCommandKind.create);
          harness.completeTagFailure(accepted, scenario.failure);
          await tester.pumpAndSettle();

          final message = locale.languageCode == 'ru'
              ? 'Создание — «тег»: ${scenario.ru}'
              : 'Create — “tag”: ${scenario.en}';
          expect(find.text(message), findsOneWidget);
          await _closeMessage(tester);
          expect(find.byType(SnackBar), findsNothing);
        },
      );
    }
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

  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets(
      'тег ждёт сообщения графа и передаёт отказ оболочке после закрытия формы, ${locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(tester, locale: locale);
        final intention = harness.startDelete(index: 1, title: 'Граф');
        final tag = harness.startTag(
          TagCommandKind.create,
          releaseInitiator: false,
        );
        harness.completeDeleted(intention);
        harness.completeTagFailure(tag, const TagUnavailableFailure());
        await tester.pumpAndSettle();

        final first = locale.languageCode == 'ru'
            ? 'Удаление — «Граф»: Намерение удалено.'
            : _deleted('Граф');
        expect(find.text(first), findsOneWidget);
        expect(harness.claimInitiatorFailure(tag.token), isNotNull);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);

        harness.releaseInitiatorPresentation(tag.token);
        await tester.pumpAndSettle();
        final fallback = locale.languageCode == 'ru'
            ? 'Создание — «тег»: Не удалось выполнить действие с тегом. Повторите попытку.'
            : 'Create — “tag”: Could not complete the tag operation. Try again.';
        expect(find.text(fallback), findsOneWidget);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  for (final scenario
      in <({DailyChoiceValidationField field, String en, String ru})>[
        (
          field: DailyChoiceValidationField.sourceIntention,
          en: 'Check the source intention of the daily choice.',
          ru: 'Проверьте исходное намерение дневного выбора.',
        ),
        (
          field: DailyChoiceValidationField.selectedIntention,
          en: 'Check the selected intention of the daily choice.',
          ru: 'Проверьте выбранное намерение дневного выбора.',
        ),
        (
          field: DailyChoiceValidationField.date,
          en: 'Check the daily choice date.',
          ru: 'Проверьте дату дневного выбора.',
        ),
        (
          field: DailyChoiceValidationField.description,
          en: 'Check the daily choice description.',
          ru: 'Проверьте описание дневного выбора.',
        ),
        (
          field: DailyChoiceValidationField.path,
          en: 'Check the daily choice path.',
          ru: 'Проверьте путь дневного выбора.',
        ),
      ]) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets(
        'ошибка поля ${scenario.field.name} локализована для ${locale.languageCode}',
        (tester) async {
          final harness = await _pumpPresenterApp(tester, locale: locale);
          final update = harness.startDailyChoiceUpdate();
          harness.completeDailyChoiceFailure(
            update,
            DailyChoiceValidationFailure(scenario.field),
          );
          await tester.pumpAndSettle();

          final message = locale.languageCode == 'ru'
              ? 'Изменение — «дневной выбор»: ${scenario.ru}'
              : 'Edit — “daily choice”: ${scenario.en}';
          expect(find.text(message), findsOneWidget);
          await _closeMessage(tester);
          expect(find.byType(SnackBar), findsNothing);
        },
      );
    }
  }

  for (final scenario
      in <({DailyChoiceCommandFailure failure, String en, String ru})>[
        (
          failure: const DailyChoiceNotFoundFailure(),
          en: 'This daily choice no longer exists.',
          ru: 'Дневной выбор больше не существует.',
        ),
        (
          failure: const DailyChoiceConflictFailure(
            DailyChoiceConflictReason.dependencyChanged,
          ),
          en: 'The data changed. Refresh it and confirm again.',
          ru: 'Данные изменились. Обновите их и подтвердите снова.',
        ),
        (
          failure: const DailyChoiceUnavailableFailure(),
          en: 'Could not complete the daily choice operation. Try again.',
          ru: 'Не удалось выполнить действие с дневным выбором. Повторите попытку.',
        ),
        (
          failure: const DailyChoiceCorruptionFailure(),
          en: 'Stored data is damaged. The daily choice was not changed.',
          ru: 'Сохранённые данные повреждены. Дневной выбор не изменён.',
        ),
        (
          failure: const DailyChoiceUnexpectedFailure(),
          en: 'The daily choice operation failed because of an unexpected error.',
          ru: 'Действие с дневным выбором не выполнено из-за непредвиденной ошибки.',
        ),
      ]) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets(
        'отказ ${scenario.failure.runtimeType} безопасен для ${locale.languageCode}',
        (tester) async {
          final harness = await _pumpPresenterApp(tester, locale: locale);
          final update = harness.startDailyChoiceUpdate();
          harness.completeDailyChoiceFailure(update, scenario.failure);
          await tester.pumpAndSettle();

          final message = locale.languageCode == 'ru'
              ? 'Изменение — «дневной выбор»: ${scenario.ru}'
              : 'Edit — “daily choice”: ${scenario.en}';
          expect(find.text(message), findsOneWidget);
          await _closeMessage(tester);
          expect(find.byType(SnackBar), findsNothing);
        },
      );
    }
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
      expect(harness.claimInitiatorFailure(deletion.token), isNull);
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
      expect(harness.repository.dailyChoiceCommands, hasLength(1));
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
        expect(harness.repository.dailyChoiceCommands, hasLength(1));
      },
    );
  }

  for (final scenario in <({Locale locale, String message})>[
    (
      locale: const Locale('en'),
      message:
          'Edit — “relation”: This relation is used by a saved daily path. '
          'Its type and participants can’t be changed.',
    ),
    (
      locale: const Locale('ru'),
      message:
          'Изменение — «связь»: Связь используется в сохранённом дневном '
          'пути. Её тип и участников нельзя изменить.',
    ),
  ]) {
    testWidgets(
      'конфликт зависимости пути объяснён для ${scenario.locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: scenario.locale,
        );
        final update = harness.startRelationUpdate();
        harness.completeRelationFailure(
          update,
          LongTermRelationReferencedByDailyPathFailure(_relationId),
        );
        await tester.pumpAndSettle();

        expect(find.text(scenario.message), findsOneWidget);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('поздний дневной результат ждёт фокуса и смены presenter', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final deletion = harness.startDailyChoiceDelete();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    harness.completeDailyChoiceDeleted(deletion);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    harness.presenterGeneration.value += 1;
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.text('Delete — “daily choice”: Daily choice deleted.'),
      findsOneWidget,
    );
    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final scenario
      in <
        ({
          AppLifecycleState state,
          List<AppLifecycleState> away,
          List<AppLifecycleState> back,
        })
      >[
        (
          state: AppLifecycleState.inactive,
          away: [AppLifecycleState.inactive],
          back: [AppLifecycleState.resumed],
        ),
        (
          state: AppLifecycleState.hidden,
          away: [AppLifecycleState.inactive, AppLifecycleState.hidden],
          back: [AppLifecycleState.inactive, AppLifecycleState.resumed],
        ),
        (
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
        ),
        (
          state: AppLifecycleState.detached,
          away: [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.detached,
          ],
          back: [AppLifecycleState.resumed],
        ),
      ]) {
    testWidgets(
      '${scenario.state.name} удерживает результат до возвращения в resumed',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        for (final state in scenario.away) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        final operation = harness.startDelete(index: 1, title: 'Фоновое');
        harness.completeDeleted(operation);
        await tester.pump();
        await tester.pump();
        expect(find.byType(SnackBar), findsNothing);

        for (final state in scenario.back) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
        expect(find.text(_deleted('Фоновое')), findsOneWidget);

        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

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
    'потеря фокуса до кадра сохраняет результат, исчезнувший до возвращения',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final operation = harness.startDelete(index: 1, title: 'Отложенное');
      harness.completeDeleted(operation);
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Отложенное')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Отложенное')), findsOneWidget);

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
      harness.completeDeleted(operation);
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text(_deleted('Пересоздание')), findsOneWidget);

      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Пересоздание')), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(harness.repository.commands, hasLength(1));
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
    'новый presenter получает завершения без подписчика в прежнем порядке',
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
      expect(find.text(_deleted('Первое')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.text(_notDeleted('Второе')), findsOneWidget);
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
    'успех создания связи ждёт сообщение намерения в той же очереди',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 1, title: 'Намерение');
      final relation = harness.startRelationCreation();
      harness.completeDeleted(intention);
      harness.completeRelationCreated(relation);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Намерение')), findsOneWidget);
      expect(find.text(_relationCreated), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_deleted('Намерение')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.text(_relationCreated), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: _relationCreated,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );

      await _closeMessage(tester);
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
      expect(find.text(_relationArchived), findsOneWidget);
      expect(find.text(_relationRestored), findsNothing);

      await _closeMessage(tester);
      expect(find.text(_relationRestored), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'удаление связи после ухода ждёт общую поверхность и предъявляется один раз',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 1, title: 'Намерение');
      final deletion = harness.startRelationDelete();
      harness.completeDeleted(intention);
      harness.completeRelationDeleted(deletion);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Намерение')), findsOneWidget);
      expect(find.text(_relationDeleted), findsNothing);
      expect(harness.repository.relationCommands, hasLength(1));

      await _closeMessage(tester);
      expect(find.text(_relationDeleted), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: _relationDeleted,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(harness.repository.relationCommands, hasLength(1));
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
    'массовый успех ждёт занятую поверхность и предъявляется одним кадром',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 2, title: 'Другое');
      final deletion = harness.startBlockingRelationsDelete(title: 'Связанное');
      harness.completeDeleted(intention);
      harness.completeBlockingRelationsDeleted(deletion);
      await tester.pumpAndSettle();

      const message =
          'Delete selected relations — “Связанное”: Selected relations deleted.';
      expect(find.text(_deleted('Другое')), findsOneWidget);
      expect(find.text(message), findsNothing);
      expect(harness.repository.blockingRelationsCommands, hasLength(1));

      await _closeMessage(tester);
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
      expect(harness.repository.blockingRelationsCommands, hasLength(1));
    },
  );

  testWidgets(
    'массовый token переживает потерю фокуса и пересоздание presenter до кадра',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final deletion = harness.startBlockingRelationsDelete(title: 'Связанное');
      harness.completeBlockingRelationsDeleted(deletion);
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      const message =
          'Delete selected relations — “Связанное”: Selected relations deleted.';
      expect(find.text(message), findsOneWidget);
      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      await _closeMessage(tester);
      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(harness.repository.blockingRelationsCommands, hasLength(1));
    },
  );

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
      final claim = harness.claimInitiatorFailure(deletion.token);
      expect(claim, isNotNull);
      harness.releaseInitiatorClaim(claim!);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Delete selected relations — “Связанное”: Selected relations couldn’t be deleted. Try again.',
        ),
        findsOneWidget,
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(harness.repository.blockingRelationsCommands, hasLength(1));
    },
  );

  for (final scenario in <({Locale locale, String message})>[
    (
      locale: const Locale('ru'),
      message:
          'Удаление выбранных связей — «Связанное»: Выбранные связи удалены.',
    ),
    (
      locale: const Locale('fr'),
      message: 'Delete selected relations — “Связанное”: Selected relations deleted.',
    ),
  ]) {
    testWidgets(
      'массовый успех локализуется для ${scenario.locale.languageCode}',
      (tester) async {
        final harness = await _pumpPresenterApp(
          tester,
          locale: scenario.locale,
        );
        final deletion = harness.startBlockingRelationsDelete(
          title: 'Связанное',
        );
        harness.completeBlockingRelationsDeleted(deletion);
        await tester.pumpAndSettle();
        expect(find.text(scenario.message), findsOneWidget);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

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

  testWidgets('успех создания связи не предлагается инлайн-владельцу', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final relation = harness.startRelationCreation(releaseInitiator: false);
    harness.completeRelationCreated(relation);
    await tester.pumpAndSettle();

    expect(harness.claimInitiatorFailure(relation.token), isNull);
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

  testWidgets('результат связи без фокуса ждёт возвращения в resumed', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final relation = harness.startRelationCreation();
    harness.completeRelationCreated(relation);
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(_relationCreated), findsOneWidget);

    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'результат восстановления без фокуса ждёт возвращения в resumed',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final restore = harness.startRelationRestore();
      harness.completeRelationRestored(restore);
      await tester.pump();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_relationRestored), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'пересоздание presenter сохраняет непредъявленный результат связи',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final relation = harness.startRelationCreation();
      harness.completeRelationCreated(relation);
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text(_relationCreated), findsOneWidget);

      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_relationCreated), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(harness.repository.relationCommands, hasLength(1));
    },
  );
}

const _withoutPresenter = -1;

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

final _relationDeleted = _relationDeleteOutcome('Relation deleted.');

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

Future<void> _closeMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

final class _PresenterHarness {
  _PresenterHarness(this.container, this.repository, this.presenterGeneration);

  final ProviderContainer container;
  final ControlledDetailsRepository repository;
  final ValueNotifier<int> presenterGeneration;
  final _commandIndexes = <IntentionCommandAccepted, int>{};
  final _titles = <IntentionCommandAccepted, (int, String)>{};
  final _relationIndexes = <LongTermRelationCommandAccepted, int>{};
  final _blockingIndexes = <BlockingRelationsDeleteAccepted, int>{};
  final _dailyChoiceIndexes = <DailyChoiceCommandAccepted, int>{};
  final _tagIndexes = <TagCommandAccepted, int>{};

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
    final before = Tag(id: _tagId, name: TagName.fromInput('Планы'));
    final after = Tag(id: _tagId, name: TagName.fromInput('Новое имя'));
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

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
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
  );
  await tester.pump();
  return _PresenterHarness(container, repository, presenterGeneration);
}
