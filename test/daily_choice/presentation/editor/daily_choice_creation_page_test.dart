import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_detail_fields.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_flow_session.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_view_model.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/design_system/components/time_dial.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_creation_controls.dart';
import '../../../support/daily_choice_detail_fields_controls.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'новый выбор начинается с даты входа, «Весь день» и P4, а закрытие листа '
    'времени без выбора их не меняет',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      expect(shownDailyChoiceCreation(tester), (
        date: CalendarDate.fromParts(2026, 9, 24),
        priority: DailyChoicePriority.p4,
      ));

      await _tapVisible(tester, _timeField);
      expect(find.byType(TimeDial), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(TimeDial), findsNothing);
      expect(find.text('Весь день'), findsOneWidget);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('daily-choice-submit')),
      );
      expect(
        repository.commands.single.date,
        CalendarDate.fromParts(2026, 9, 24),
      );
      expect(repository.commands.single.schedule, const DailyChoiceAllDay());
      expect(repository.commands.single.priority, DailyChoicePriority.p4);
    },
  );

  testWidgets(
    'подтверждённые время и приоритет сохраняются при закрытии листа времени',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      await setDailyChoiceHour(tester, 18);
      await setDailyChoicePriority(tester, DailyChoicePriority.p2);

      await _tapVisible(tester, _timeField);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('18:00'), findsOneWidget);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('daily-choice-submit')),
      );
      expect(
        repository.commands.single.schedule,
        DailyChoiceTime(hour: 18, minute: 0),
      );
      expect(repository.commands.single.priority, DailyChoicePriority.p2);
    },
  );

  testWidgets('смена локали сохраняет выбранные поля', (tester) async {
    final locale = ValueNotifier(const Locale('ru'));
    addTearDown(locale.dispose);
    final repository = _Repository();
    await _pump(tester, repository, localeChanges: locale);

    await setDailyChoiceHour(tester, 18);
    await setDailyChoicePriority(tester, DailyChoicePriority.p1);

    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(shownDailyChoiceCreation(tester), (
      date: CalendarDate.fromParts(2026, 9, 24),
      priority: DailyChoicePriority.p1,
    ));
    await _reveal(tester, find.text('18:00'));
    expect(find.text('18:00'), findsOneWidget);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    expect(
      repository.commands.single.schedule,
      DailyChoiceTime(hour: 18, minute: 0),
    );
    expect(repository.commands.single.priority, DailyChoicePriority.p1);
  });

  // Исход и состояние формы при позднем результате независимы: диагональ
  // покрывает успех и отказ, закрывающуюся и освобождённую форму.
  for (final (succeeds, disposed) in [(true, false), (false, true)]) {
    testWidgets(
      'сессия хранит отправку и поздний ${succeeds ? 'успех' : 'отказ'} ${disposed ? 'после освобождения' : 'во время закрытия'} подтверждения',
      (tester) async {
        final repository = _Repository();
        final navigatorKey = GlobalKey<NavigatorState>();
        await _pump(tester, repository, navigatorKey: navigatorKey);
        final form = tester.state(find.byType(DailyChoiceCreationPage));
        await _reveal(
          tester,
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        navigatorKey.currentState!.pop();
        if (disposed) {
          await tester.pumpAndSettle();
        } else {
          await tester.pump();
        }
        expect(form.mounted, !disposed);

        if (succeeds) {
          repository.succeed(0);
        } else {
          repository.fail(0, const DailyChoiceUnavailableFailure());
        }
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Дневной выбор создан'),
          succeeds ? findsOneWidget : findsNothing,
        );
        expect(repository.commands, hasLength(1));
        expect(find.text('Домашний экран'), findsOneWidget);
        final message = find.byKey(const ValueKey('graph-operation-message'));
        expect(message, findsOneWidget);
        await tester.pump(const Duration(seconds: 8));
        await tester.pumpAndSettle();
        expect(message, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'успех предъявляется после результата команды, затем открыта исходная страница',
    (tester) async {
      final repository = _Repository();
      final navigatorKey = GlobalKey<NavigatorState>();
      await _pump(tester, repository, navigatorKey: navigatorKey);
      await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
      await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
      await tester.pump();
      expect(dailyChoiceDetailFields, findsOneWidget);
      expect(find.text('Домашний экран'), findsNothing);
      expect(repository.commands, hasLength(1));
      repository.succeed(0);
      await tester.pumpAndSettle();
      expect(dailyChoiceDetailFields, findsNothing);
      expect(find.text('Домашний экран'), findsOneWidget);
      expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
    },
  );

  testWidgets('результат после ухода формы предъявляет оболочка', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Домашний экран'), findsOneWidget);
    repository.succeed(0);
    await tester.pumpAndSettle();
    expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
  });

  testWidgets('поздний результат ждёт возвращения фокуса', (tester) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    repository.succeed(0);
    await tester.pumpAndSettle();
    expect(find.textContaining('Дневной выбор создан'), findsNothing);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
  });

  testWidgets('английская семантика сохраняет пользовательские названия', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository, locale: const Locale('en'));
    final semantics = tester.ensureSemantics();
    expect(find.textContaining('Основание'), findsWidgets);
    expect(find.textContaining('Действие'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Step 1:')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('daily-choice-completed')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Already completed'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('ошибка поля показана в форме без потери ввода', (tester) async {
    final repository = _Repository();
    await _pump(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-description')),
      'Сохранить меня',
    );
    await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    repository.fail(
      0,
      const DailyChoiceValidationFailure(
        DailyChoiceValidationField.description,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сохранить меня'), findsOneWidget);
    expect(find.textContaining('Проверьте описание'), findsWidgets);
    expect(find.byKey(const ValueKey('daily-choice-failure')), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-choice-submit')), findsOneWidget);
  });

  testWidgets('временный отказ сохраняет поля для явного повтора', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    const descriptionKey = ValueKey('daily-choice-description');
    const submitKey = ValueKey('daily-choice-submit');

    await setDailyChoiceCreationDate(
      tester,
      CalendarDate.fromParts(2026, 9, 25),
    );
    await tester.enterText(find.byKey(descriptionKey), 'Первый текст');
    await setDailyChoiceHour(tester, 0);
    await setDailyChoiceCreationPriority(tester, DailyChoicePriority.p2);
    await _reveal(tester, find.byKey(const ValueKey('daily-choice-completed')));
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('daily-choice-completed')),
    );
    await _reveal(tester, find.byKey(submitKey));
    await tester.tap(find.byKey(submitKey));
    await tester.pump();

    expect(repository.commands, hasLength(1));
    expect(
      repository.commands.single.date,
      CalendarDate.fromParts(2026, 9, 25),
    );
    expect(repository.commands.single.description?.value, 'Первый текст');
    expect(repository.commands.single.isCompleted, isTrue);
    expect(
      repository.commands.single.schedule,
      DailyChoiceTime(hour: 0, minute: 0),
    );
    expect(repository.commands.single.priority, DailyChoicePriority.p2);
    expect(
      tester.widget<DailyChoiceDetailFields>(dailyChoiceDetailFields).enabled,
      isFalse,
    );
    await _tapVisible(tester, _timeField);
    expect(find.byType(TimeDial), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).enabled,
      isFalse,
    );
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).controller!.text,
      'Первый текст',
    );
    expect(
      tester.widget<FilledButton>(find.byKey(submitKey)).onPressed,
      isNull,
    );

    repository.fail(0, const DailyChoiceUnavailableFailure());
    await tester.pumpAndSettle();
    expect(
      tester.widget<DailyChoiceDetailFields>(dailyChoiceDetailFields).enabled,
      isTrue,
    );
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).enabled,
      isTrue,
    );
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).controller!.text,
      'Первый текст',
    );
    expect(shownDailyChoiceCreation(tester), (
      date: CalendarDate.fromParts(2026, 9, 25),
      priority: DailyChoicePriority.p2,
    ));

    await tester.enterText(find.byKey(descriptionKey), 'Исправленный текст');
    await setDailyChoiceAllDay(tester);
    await setDailyChoiceCreationPriority(tester, DailyChoicePriority.p3);
    await _reveal(tester, find.byKey(submitKey));
    await tester.tap(find.byKey(submitKey));
    await tester.pump();
    expect(repository.commands, hasLength(2));
    expect(repository.commands.last.date, CalendarDate.fromParts(2026, 9, 25));
    expect(repository.commands.last.description?.value, 'Исправленный текст');
    expect(repository.commands.last.isCompleted, isTrue);
    expect(repository.commands.last.schedule, const DailyChoiceAllDay());
    expect(repository.commands.last.priority, DailyChoicePriority.p3);
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).enabled,
      isFalse,
    );
    repository.succeed(1);
    await tester.pumpAndSettle();
    expect(find.text('Домашний экран'), findsOneWidget);
    expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
  });

  testWidgets('подтверждение явно сохраняет показанный путь и поля', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository);
    expect(repository.commands, isEmpty);
    expect(find.textContaining('Основание'), findsWidgets);
    expect(find.textContaining('Действие'), findsWidgets);
    await setDailyChoiceCreationDate(
      tester,
      CalendarDate.fromParts(2026, 10, 2),
    );
    await setDailyChoiceHour(tester, 18);
    expect(
      shownDailyChoiceCreation(tester).date,
      CalendarDate.fromParts(2026, 10, 2),
    );
    expect(find.text('18:00'), findsOneWidget);
    expect(repository.commands, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-description')),
      'Мой текст',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('daily-choice-completed')),
    );
    await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    expect(repository.commands, hasLength(1));
    expect(
      repository.commands.single.date,
      CalendarDate.fromParts(2026, 10, 2),
    );
    expect(
      repository.commands.single.schedule,
      DailyChoiceTime(hour: 18, minute: 0),
    );
    expect(repository.commands.single.description?.value, 'Мой текст');
    expect(repository.commands.single.isCompleted, isTrue);
    expect(repository.commands.single.path.steps.length, 1);
  });

  testWidgets('неверное описание можно исправить без потери ввода', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository, locale: const Locale('en'));
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-description')),
      'x' * 4097,
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    expect(repository.commands, isEmpty);
    expect(find.text('x' * 4097), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-description')),
      'corrected',
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    expect(
      repository.commands.single.date,
      CalendarDate.fromParts(2026, 9, 24),
    );
    expect(repository.commands.single.description?.value, 'corrected');
  });

  testWidgets(
    'нижняя актуализация начинается от прежнего действия и сохраняет поля',
    (tester) async {
      final repository = _Repository();
      final navigatorKey = GlobalKey<NavigatorState>();
      final observer = _RouteObserver();
      await _pump(
        tester,
        repository,
        navigatorKey: navigatorKey,
        navigatorObserver: observer,
        direction: ChoicePathDraftDirection.bottomUp,
      );
      await setDailyChoiceCreationDate(
        tester,
        CalendarDate.fromParts(2026, 9, 25),
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-description')),
        'Прежнее описание',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('daily-choice-completed')),
      );
      await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
      await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
      await tester.pump();
      repository.fail(
        0,
        const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.confirmedPathChanged,
        ),
      );
      await tester.pumpAndSettle();

      await _reveal(
        tester,
        find.text('Вернуться к пути и актуализировать его'),
      );
      await tester.tap(find.text('Вернуться к пути и актуализировать его'));
      await tester.pumpAndSettle();
      final refreshPage = tester.widget<ChoicePathPage>(
        find.byType(ChoicePathPage),
      );
      expect(refreshPage.direction, ChoicePathDraftDirection.bottomUp);
      expect(refreshPage.sourceIntentionId, _intention(2));
      expect(repository.commands, hasLength(1));

      navigatorKey.currentState!.removeRoute(observer.routes.last);
      await tester.pumpAndSettle();
      expect(
        shownDailyChoiceCreation(tester).date,
        CalendarDate.fromParts(2026, 9, 25),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('daily-choice-description')),
            )
            .controller!
            .text,
        'Прежнее описание',
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('daily-choice-completed')),
            )
            .value,
        isTrue,
      );
      expect(repository.commands, hasLength(1));
    },
  );

  for (final olderFirst in [true, false]) {
    testWidgets(
      'два результата актуализации в порядке ${olderFirst ? 'старый–новый' : 'новый–старый'} показывают отправляемый путь',
      (tester) async {
        final repository = _Repository();
        final navigatorKey = GlobalKey<NavigatorState>();
        final observer = _RouteObserver();
        await _pump(
          tester,
          repository,
          navigatorKey: navigatorKey,
          navigatorObserver: observer,
        );
        await setDailyChoiceCreationDate(
          tester,
          CalendarDate.fromParts(2026, 9, 25),
        );
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-description')),
          'Сохранённое описание',
        );
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('daily-choice-completed')),
        );
        await _reveal(
          tester,
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        await tester.pump();
        repository.fail(
          0,
          const DailyChoiceConflictFailure(
            DailyChoiceConflictReason.confirmedPathChanged,
          ),
        );
        await tester.pumpAndSettle();

        final refresh = tester.widget<TextButton>(
          find.widgetWithText(
            TextButton,
            'Вернуться к пути и актуализировать его',
          ),
        );
        refresh.onPressed!();
        final olderRoute = observer.routes.last;
        refresh.onPressed!();
        final newerRoute = observer.routes.last;
        await tester.pumpAndSettle();

        final older = _selection(2, 3, 'Старое действие');
        final newer = _selection(3, 4, 'Новое действие');
        if (olderFirst) {
          navigatorKey.currentState!.removeRoute(olderRoute, older);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.removeRoute(newerRoute, newer);
        } else {
          navigatorKey.currentState!.removeRoute(newerRoute, newer);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.removeRoute(olderRoute, older);
        }
        await tester.pumpAndSettle();

        await _scrollToStart(tester);
        expect(find.textContaining('Новое действие'), findsWidgets);
        expect(find.textContaining('Старое действие'), findsNothing);
        expect(repository.commands, hasLength(1));
        await _reveal(
          tester,
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        await tester.pump();
        expect(repository.commands, hasLength(2));
        expect(
          repository.commands.last.path.steps.map((step) => step.relationId),
          newer.path.steps.map((step) => step.relationId),
        );
        expect(
          repository.commands.last.date,
          CalendarDate.fromParts(2026, 9, 25),
        );
        expect(
          repository.commands.last.description?.value,
          'Сохранённое описание',
        );
        expect(repository.commands.last.isCompleted, isTrue);

        repository.fail(
          1,
          const DailyChoiceConflictFailure(
            DailyChoiceConflictReason.confirmedPathChanged,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Вернуться к пути и актуализировать его'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('daily-choice-submit')),
              )
              .onPressed,
          isNull,
        );
        expect(repository.commands, hasLength(2));
        expect(find.textContaining('Дневной выбор создан'), findsNothing);
      },
    );
  }

  for (final olderFirst in [true, false]) {
    testWidgets(
      'нижняя актуализация в порядке ${olderFirst ? 'старый–новый' : 'новый–старый'} принимает только последнее основание',
      (tester) async {
        final repository = _Repository();
        final navigatorKey = GlobalKey<NavigatorState>();
        final observer = _RouteObserver();
        await _pump(
          tester,
          repository,
          navigatorKey: navigatorKey,
          navigatorObserver: observer,
          direction: ChoicePathDraftDirection.bottomUp,
        );
        await setDailyChoiceCreationDate(
          tester,
          CalendarDate.fromParts(2026, 9, 25),
        );
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-description')),
          'Сохранённое описание',
        );
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('daily-choice-completed')),
        );
        await _reveal(
          tester,
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        await tester.pump();
        repository.fail(
          0,
          const DailyChoiceConflictFailure(
            DailyChoiceConflictReason.confirmedPathChanged,
          ),
        );
        await tester.pumpAndSettle();
        final refresh = tester.widget<TextButton>(
          find.widgetWithText(
            TextButton,
            'Вернуться к пути и актуализировать его',
          ),
        );
        refresh.onPressed!();
        final olderRoute = observer.routes.last;
        refresh.onPressed!();
        final newerRoute = observer.routes.last;
        await tester.pumpAndSettle();

        final older = _bottomSelection(2, 3, 'Старое основание');
        final newer = _bottomSelection(3, 4, 'Новое основание');
        if (olderFirst) {
          navigatorKey.currentState!.removeRoute(olderRoute, older);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.removeRoute(newerRoute, newer);
        } else {
          navigatorKey.currentState!.removeRoute(newerRoute, newer);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.removeRoute(olderRoute, older);
        }
        await tester.pumpAndSettle();

        await _scrollToStart(tester);
        expect(find.textContaining('Новое основание'), findsWidgets);
        expect(find.textContaining('Старое основание'), findsNothing);
        expect(repository.commands, hasLength(1));
        await _reveal(
          tester,
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        await tester.pump();
        expect(repository.commands, hasLength(2));
        expect(
          repository.commands.last.path.steps.map((step) => step.relationId),
          newer.path.steps.map((step) => step.relationId),
        );
        expect(repository.commands.last.selectedIntentionId, _intention(2));
        expect(
          repository.commands.last.date,
          CalendarDate.fromParts(2026, 9, 25),
        );
        expect(
          repository.commands.last.description?.value,
          'Сохранённое описание',
        );
        expect(repository.commands.last.isCompleted, isTrue);
      },
    );
  }

  testWidgets('отмена нового выбора не принимает поздний прежний путь', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RouteObserver();
    await _pump(
      tester,
      repository,
      navigatorKey: navigatorKey,
      navigatorObserver: observer,
    );
    await _reveal(tester, find.byKey(const ValueKey('daily-choice-submit')));
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    repository.fail(
      0,
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.confirmedPathChanged,
      ),
    );
    await tester.pumpAndSettle();

    final refresh = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Вернуться к пути и актуализировать его'),
    );
    refresh.onPressed!();
    final olderRoute = observer.routes.last;
    refresh.onPressed!();
    final newerRoute = observer.routes.last;
    await tester.pumpAndSettle();
    navigatorKey.currentState!.removeRoute(newerRoute);
    await tester.pumpAndSettle();
    navigatorKey.currentState!.removeRoute(
      olderRoute,
      _selection(2, 3, 'Позднее действие'),
    );
    await tester.pumpAndSettle();

    await _scrollToStart(tester);
    expect(find.textContaining('Позднее действие'), findsNothing);
    expect(find.textContaining('Действие'), findsWidgets);
    await _reveal(tester, find.text('Вернуться к пути и актуализировать его'));
    expect(find.text('Вернуться к пути и актуализировать его'), findsOneWidget);
    expect(repository.commands, hasLength(1));
  });
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  Locale locale = const Locale('ru'),
  ValueNotifier<Locale>? localeChanges,
  GlobalKey<NavigatorState>? navigatorKey,
  NavigatorObserver? navigatorObserver,
  ChoicePathDraftDirection direction = ChoicePathDraftDirection.topDown,
}) async {
  final router = RootStackRouter.build(
    navigatorKey: navigatorKey,
    routes: [
      NamedRouteDef(
        name: 'HomeRoute',
        initial: true,
        builder: (_, _) => const Scaffold(body: Text('Домашний экран')),
      ),
      NamedRouteDef(
        name: ChoicePathRoute.name,
        builder: (_, _) => const Scaffold(body: Text('Домашний экран')),
      ),
      AutoRoute(page: DailyChoiceCreationRoute.page),
    ],
  );
  addTearDown(router.dispose);
  final selectedLocale = localeChanges ?? ValueNotifier(locale);
  if (localeChanges == null) addTearDown(selectedLocale.dispose);
  final routerConfig = router.config(
    navigatorObservers: () => [?navigatorObserver],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: ValueListenableBuilder<Locale>(
        valueListenable: selectedLocale,
        builder: (context, locale, _) => MaterialApp.router(
          routerConfig: routerConfig,
          theme: doableTheme(Brightness.light),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: GraphOperationPresenter(child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final history = router.stackData.map((route) => route.matchId).toList();
  unawaited(
    router.push(
      ChoicePathRoute(sourceIntentionId: _intention(1), direction: direction),
    ),
  );
  await tester.pumpAndSettle();
  final session = DailyChoiceCreationFlowSession(
    rootMatchId: router.stackData.last.matchId,
    originalHistory: history,
    pathInstance: ChoicePathPageInstance(),
  );
  unawaited(
    router.push(
      DailyChoiceCreationRoute(
        session: session,
        path: ConfirmedChoicePath([
          ConfirmedChoicePathStep(
            relationId: _relation(1),
            sourceIntentionId: _intention(1),
            relatedIntentionId: _intention(2),
            type: LongTermRelationType.need,
          ),
        ]),
        steps: [DailyChoiceCreationStep.fromSummary(_step())],
        initialDate: CalendarDate.fromParts(2026, 9, 24),
        direction: direction,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToStart(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byType(DailyChoiceCreationPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scrollable, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Кнопка поля «Время» подтверждения.
Finder get _timeField => find.descendant(
  of: find.widgetWithText(DetailRow, 'Время'),
  matching: find.byType(Button),
);

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final commands = <CreateDailyChoice>[];
  final requests = <Completer<DailyChoiceCommandResult>>[];

  void fail(int index, DailyChoiceCommandFailure failure) =>
      requests[index].complete(GraphCommandFailed(failure));

  void succeed(int index) {
    final command = commands[index];
    final id = (DailyChoiceId.decode(
      '00000000-0000-4000-8002-000000000001',
    ) as DailyChoiceIdDecodingSuccess).id;
    final stepId = (ChoicePathStepId.decode(
      '00000000-0000-4000-8003-000000000001',
    ) as ChoicePathStepIdDecodingSuccess).id;
    requests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: const _Revision(),
          value: DailyChoiceCreated(
            choice: DailyChoice(
              id: id,
              sourceIntentionId: command.sourceIntentionId,
              selectedIntentionId: command.selectedIntentionId,
              date: command.date,
              description: command.description,
              isCompleted: command.isCompleted,
            ),
            path: StoredChoicePath([
              ChoicePathStep(
                id: stepId,
                dailyChoiceId: id,
                relationId: command.path.steps.first.relationId,
                previousStepId: null,
              ),
            ]),
            changes: const [_Change()],
          ),
        ),
      ),
    );
  }

  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) async => const DailyChoiceDayStatusesReadError(
    DailyChoiceDayStatusesReadFailure(),
  );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command as CreateDailyChoice);
    final request = Completer<DailyChoiceCommandResult>();
    requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is _Revision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

final class _Change implements GraphChange {
  const _Change();
  @override
  GraphRevision get revision => const _Revision();
}

IntentionId _intention(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relation(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8001-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

LongTermRelationSummary _step() => LongTermRelationSummary(
  relation: LongTermRelation(
    id: _relation(1),
    sourceIntentionId: _intention(1),
    relatedIntentionId: _intention(2),
    type: LongTermRelationType.need,
    priority: RelationPriority.p1,
    scope: RelationScope.active,
    creationSequence: RelationCreationSequence(1),
    createdAt: RelationTimestamp(DateTime.utc(2026)),
    updatedAt: RelationTimestamp(DateTime.utc(2026)),
  ),
  source: RelationParticipantSummary(
    id: _intention(1),
    title: 'Основание',
    archiveState: IntentionArchiveState.active,
  ),
  related: RelationParticipantSummary(
    id: _intention(2),
    title: 'Действие',
    archiveState: IntentionArchiveState.active,
  ),
  hasDescription: false,
);

ChoicePathSelection _selection(int relation, int action, String title) =>
    ChoicePathSelection(
      path: ConfirmedChoicePath([
        ConfirmedChoicePathStep(
          relationId: _relation(relation),
          sourceIntentionId: _intention(1),
          relatedIntentionId: _intention(action),
          type: LongTermRelationType.need,
        ),
      ]),
      steps: [
        DailyChoiceCreationStep(
          relation: LongTermRelation(
            id: _relation(relation),
            sourceIntentionId: _intention(1),
            relatedIntentionId: _intention(action),
            type: LongTermRelationType.need,
            priority: RelationPriority.p1,
            scope: RelationScope.active,
            creationSequence: RelationCreationSequence(relation),
            createdAt: RelationTimestamp(DateTime.utc(2026)),
            updatedAt: RelationTimestamp(DateTime.utc(2026)),
          ),
          sourceTitle: 'Основание',
          relatedTitle: title,
        ),
      ],
    );

ChoicePathSelection _bottomSelection(int relation, int source, String title) =>
    ChoicePathSelection(
      path: ConfirmedChoicePath([
        ConfirmedChoicePathStep(
          relationId: _relation(relation),
          sourceIntentionId: _intention(source),
          relatedIntentionId: _intention(2),
          type: LongTermRelationType.need,
        ),
      ]),
      steps: [
        DailyChoiceCreationStep(
          relation: LongTermRelation(
            id: _relation(relation),
            sourceIntentionId: _intention(source),
            relatedIntentionId: _intention(2),
            type: LongTermRelationType.need,
            priority: RelationPriority.p1,
            scope: RelationScope.active,
            creationSequence: RelationCreationSequence(relation),
            createdAt: RelationTimestamp(DateTime.utc(2026)),
            updatedAt: RelationTimestamp(DateTime.utc(2026)),
          ),
          sourceTitle: title,
          relatedTitle: 'Действие',
        ),
      ],
    );

final class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}
