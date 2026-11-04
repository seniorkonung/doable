import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_detail_fields.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_sheet.dart';
import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/choice_head.dart';
import 'package:doable/src/design_system/components/choice_path.dart' as ui;
import 'package:doable/src/design_system/components/date_grid.dart';
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/reason_chain.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/components/time_dial.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/application/intention_details.dart'
    as application;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/daily_choice_detail_fields_controls.dart';
import '../../../support/daily_choice_local_date.dart';
import '../../../support/ordinary_page_test_app.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('меню открывает подтверждение удаления, отмена сохраняет выбор', (
    tester,
  ) async {
    final harness = await _openSheet(tester);
    harness.repository.emit(_details());
    await tester.pumpAndSettle();
    await tester.tap(_options);
    await tester.pumpAndSettle();
    expect(find.text('Дневной выбор'), findsWidgets);
    await tester.tap(find.text('Удалить дневной выбор'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить дневной выбор?'), findsOneWidget);
    expect(
      find.textContaining('2026-10-08', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Действие'), findsOneWidget);
  });

  testWidgets(
    'меню открывает форму, а после возврата панель показывает изменения',
    (tester) async {
      final (repository, router) = await _openOnRouter(tester);
      repository.emit(_details());
      await tester.pumpAndSettle();
      await tester.tap(_options);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Редактировать дневной выбор'));
      await tester.pumpAndSettle();
      expect(router.current.name, DailyChoiceEditRoute.name);
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-edit-description')),
        'Новое описание',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-edit-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-edit-submit')));
      await tester.pump();
      repository.emit(_details(description: 'Новое описание'));
      repository.succeedUpdate();
      await tester.pumpAndSettle();
      expect(find.text('Новое описание'), findsOneWidget);
    },
  );

  for (final (order, missingFirst) in [
    ('снимок без выбора приходит до подтверждения', true),
    ('снимок без выбора приходит после подтверждения', false),
  ]) {
    testWidgets('подтверждённое удаление закрывает панель с прежним '
        'содержимым и сообщает об успехе один раз: $order', (tester) async {
      final harness = await _openSheet(tester);
      final repository = harness.repository;
      repository.emit(_details());
      await tester.pumpAndSettle();
      await _startDeletion(tester);
      _expectHeadLocked(tester);

      if (missingFirst) {
        repository.emitMissing();
        await tester.pump();
        expect(find.text('Пояснение'), findsOneWidget);
        expect(find.text(_notFound), findsNothing);
        _expectHeadLocked(tester);
        repository.succeedDelete();
      } else {
        repository.succeedDelete();
        await tester.pump();
        repository.emitMissing();
      }

      await _expectClosingKeepsContent(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Дневной выбор удалён.'), findsOneWidget);
    });
  }

  testWidgets(
    'панель, перекрытая страницей при подтверждении удаления, сама не '
    'закрывается и при возврате показывает, что выбора нет',
    (tester) async {
      final (repository, router) = await _openOnRouter(tester);
      repository.emit(_details());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Путь'));
      await tester.pumpAndSettle();
      await _startDeletion(tester);
      await tester.tap(find.byKey(const ValueKey('daily-choice-intention-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.current.name, IntentionDetailsRoute.name);

      repository.succeedDelete();
      await tester.pump();
      repository.emitMissing();
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.current.name, IntentionDetailsRoute.name);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Sheet), findsOneWidget);
      expect(find.text(_notFound), findsOneWidget);
      expect(find.byType(ChoiceHead), findsNothing);
      expect(
        find.textContaining('Дневной выбор удалён.').hitTestable(),
        findsOneWidget,
      );
    },
  );

  testWidgets('отказ удаления выбора, который тем временем исчез, оставляет '
      'панель открытой с тем, что выбора нет', (tester) async {
    final harness = await _openSheet(tester);
    harness.repository.emit(_details());
    await tester.pumpAndSettle();
    await _startDeletion(tester);
    harness.repository.emitMissing();
    await tester.pump();
    expect(find.text(_notFound), findsNothing);

    harness.repository.failCommand(const DailyChoiceNotFoundFailure());
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsOneWidget);
    expect(find.text(_notFound), findsOneWidget);
    expect(find.byType(ChoiceHead), findsNothing);
  });

  testWidgets('отказ удаления остаётся в панели', (tester) async {
    final harness = await _openSheet(tester);
    harness.repository.emit(_details());
    await tester.pumpAndSettle();
    await _startDeletion(tester);
    harness.repository.failCommand(const DailyChoiceUnavailableFailure());
    await tester.pumpAndSettle();
    expect(find.text(_commandFailure), findsOneWidget);
    expect(find.text('Действие'), findsOneWidget);
  });

  testWidgets(
    'путь показывает текущие названия, виды связей и архив с доступными ролями',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final harness = await _openSheet(tester);
      harness.repository.emit(
        _details(archived: {_Archived.source, _Archived.relation}),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Путь'));
      await tester.pumpAndSettle();

      final path = tester.widget<ui.ChoicePath>(find.byType(ui.ChoicePath));
      expect(path.source.name, 'Основа');
      expect(path.intermediate.single.step.name, 'Середина');
      expect(
        path.intermediate.single.relation.kind,
        ui.ChoicePathRelationKind.need,
      );
      expect(path.action.step.name, 'Действие');
      expect(path.action.relation.kind, ui.ChoicePathRelationKind.can);
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('daily-choice-intention-1')),
            )
            .label,
        contains('Основание, Основа, Архивировано'),
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('daily-choice-relation-1')))
            .label,
        contains('Нужно'),
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('daily-choice-relation-1')))
            .label,
        contains('Архивировано'),
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('daily-choice-intention-3')),
            )
            .label,
        contains('Выбранное действие'),
      );
      expect(
        find.text('В пути есть архивированные намерения или связи.'),
        findsOneWidget,
      );
      expect(find.textContaining('Готово к действию'), findsNothing);

      harness.repository.emit(_details(middleTitle: 'Новое название'));
      await tester.pumpAndSettle();
      expect(find.text('Новое название'), findsOneWidget);
      expect(find.text('Середина'), findsNothing);
      expect(
        find.text('В пути есть архивированные намерения или связи.'),
        findsNothing,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'возврат со страницы намерения и панели связи показывает вкладку пути',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (repository, router) = await _openOnRouter(tester);
      repository.emit(_details());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Путь'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('daily-choice-relation-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.watchedRelations, [_relationId(2)]);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ui.ChoicePath), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('daily-choice-intention-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        _intentionId(2),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ui.ChoicePath), findsOneWidget);
      expect(
        tester
            .widget<ui.ChoicePath>(find.byType(ui.ChoicePath))
            .intermediate
            .single
            .step
            .name,
        'Середина',
      );
    },
  );

  testWidgets('путь из одной связи ведёт сразу к выбранному действию', (
    tester,
  ) async {
    final harness = await _openSheet(tester);
    harness.repository.emit(_details(oneStep: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Путь'));
    await tester.pumpAndSettle();

    final path = tester.widget<ui.ChoicePath>(find.byType(ui.ChoicePath));
    expect(path.intermediate, isEmpty);
    expect(path.action.step.name, 'Действие');
    expect(path.action.relation.kind, ui.ChoicePathRelationKind.need);
    expect(
      find.byKey(const ValueKey('daily-choice-intention-2')),
      findsOneWidget,
    );
  });

  testWidgets('панель открывается на «Обзоре» с шапкой, описанием с переносами '
      'и полями значений', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);

    harness.repository.emit(
      _details(
        description: 'Первая строка\nВторая строка',
        schedule: DailyChoiceTime(hour: 18, minute: 0),
        priority: DailyChoicePriority.p2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Основа'), findsOneWidget);
    expect(find.text('Действие'), findsOneWidget);
    final chain = tester.widget<ReasonChain>(find.byType(ReasonChain));
    expect(chain.reasons, 2);
    expect(chain.priority, DoablePriority.p2);
    expect(chain.off, isFalse);
    expect(find.text('Первая строка\nВторая строка'), findsOneWidget);
    expect(find.text('Дата'), findsOneWidget);
    expect(find.text('Время'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('Приоритет'), findsOneWidget);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Обзор')),
      isSemantics(hasSelectedState: true, isSelected: true),
    );
    expect(find.bySemanticsLabel('Путь, 2 шага'), findsOneWidget);
    expect(_tabCount(tester), '2');

    final picker = tester.widget<PriorityPicker>(find.byType(PriorityPicker));
    expect(picker.value, DoablePriority.p2);
    expect(picker.onChange, isNotNull);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Время: 18:00. Изменить время'),
      ),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Дата: четверг, 8 октября 2026.*Изменить дату$'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('у выполненного выбора шапка зачёркнута, цепочка серая, а без '
      'описания над полями ничего нет', (tester) async {
    final harness = await _openSheet(tester);

    harness.repository.emit(_details(isCompleted: true, description: ''));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('Действие')).style!.decoration,
      TextDecoration.lineThrough,
    );
    expect(tester.widget<ReasonChain>(find.byType(ReasonChain)).off, isTrue);
    expect(
      tester.getRect(find.text('Дата')).top,
      greaterThan(tester.getRect(_tabs).bottom),
    );
    expect(find.text('Пояснение'), findsNothing);
    expect(find.text('Добавить описание'), findsNothing);
  });

  testWidgets('архивированные исходное намерение и действие несут отметку, а '
      'вкладка «Путь» — значок и название архива', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);

    harness.repository.emit(
      _details(archived: {_Archived.source, _Archived.selected}),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BadgeArchived), findsNWidgets(2));
    expect(find.text('Архив'), findsNWidgets(2));
    expect(_archiveIcon, findsOneWidget);
    expect(
      find.bySemanticsLabel('Путь, 2 шага, в пути есть архив'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  for (final (name, archived) in [
    ('промежуточное намерение', {_Archived.middle}),
    ('связь', {_Archived.relation}),
  ]) {
    testWidgets('архив в середине пути ($name) даёт значок на вкладке без '
        'отметки в шапке', (tester) async {
      final harness = await _openSheet(tester);

      harness.repository.emit(_details(archived: archived));
      await tester.pumpAndSettle();

      expect(find.byType(BadgeArchived), findsNothing);
      expect(_archiveIcon, findsOneWidget);
    });
  }

  testWidgets('путь без архива не несёт значка на вкладке', (tester) async {
    final harness = await _openSheet(tester);

    harness.repository.emit(_details());
    await tester.pumpAndSettle();

    expect(_archiveIcon, findsNothing);
  });

  testWidgets('дата читается относительно сегодня, иначе числом и коротким '
      'месяцем, а год стоит только у другого года', (tester) async {
    final harness = await _openSheet(tester);

    for (final (date, label) in [
      (CalendarDate.fromParts(2026, 10, 8), 'Сегодня'),
      (CalendarDate.fromParts(2026, 10, 9), 'Завтра'),
      (CalendarDate.fromParts(2026, 10, 7), 'Вчера'),
      (CalendarDate.fromParts(2026, 10, 13), '13 окт.'),
      (CalendarDate.fromParts(2027, 1, 5), '5 янв. 2027'),
    ]) {
      harness.repository.emit(_details(date: date));
      await tester.pumpAndSettle();

      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('открытая панель пересчитывает слово даты с наступлением нового '
      'дня', (tester) async {
    final harness = await _openSheet(tester);
    harness.repository.emit(_details());
    await tester.pumpAndSettle();
    expect(find.text('Сегодня'), findsOneWidget);

    harness.localDate.today = CalendarDate.fromParts(2026, 10, 9);
    WidgetsBinding.instance
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Вчера'), findsOneWidget);
  });

  for (final (locale, value) in [
    (const Locale('ru'), '18:30'),
    (const Locale('en'), '6:30 PM'),
  ]) {
    testWidgets('сохранённые минуты показаны как есть в формате часов локали '
        '$locale', (tester) async {
      final harness = await _openSheet(tester, locale: locale);

      harness.repository.emit(
        _details(schedule: DailyChoiceTime(hour: 18, minute: 30)),
      );
      await tester.pumpAndSettle();

      expect(find.text(value), findsOneWidget);
    });
  }

  testWidgets('выбор на весь день показывает «Весь день»', (tester) async {
    final harness = await _openSheet(tester);

    harness.repository.emit(_details(schedule: const DailyChoiceAllDay()));
    await tester.pumpAndSettle();

    expect(find.text('Весь день'), findsOneWidget);
  });

  testWidgets('при загрузке вместо шапки и вкладок стоит состояние, а название '
      'панели и подписи ручки уже постоянны', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);

    expect(find.text('Загружаем дневной выбор…'), findsOneWidget);
    expect(_tabs, findsNothing);
    expect(find.bySemanticsLabel('Дневной выбор'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Раскрыть панель дневного выбора'),
      findsOneWidget,
    );

    harness.repository.emit(_details());
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Дневной выбор'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Раскрыть панель дневного выбора'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Свернуть панель дневного выбора'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  for (final (name, fail, message)
      in <(String, void Function(_Repository), String)>[
        (
          'отсутствие записи',
          (repository) => repository.emitMissing(),
          'Дневной выбор больше не существует.',
        ),
        (
          'повреждение',
          (repository) =>
              repository.fail(const DailyChoiceReadCorruptionFailure()),
          'Сохранённый путь повреждён и не может быть показан.',
        ),
        (
          'непредвиденный отказ',
          (repository) =>
              repository.fail(const DailyChoiceReadUnexpectedFailure()),
          'Не удалось загрузить дневной выбор из-за непредвиденной ошибки.',
        ),
        (
          'пустой путь',
          (repository) => repository.emit(_details(emptyPath: true)),
          'Сохранённый путь повреждён и не может быть показан.',
        ),
      ]) {
    testWidgets('$name заменяет шапку и вкладки отказом без повтора, а лист '
        'сам не закрывается', (tester) async {
      final harness = await _openSheet(tester);
      harness.repository.emit(_details());
      await tester.pumpAndSettle();

      fail(harness.repository);
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.text('Действие'), findsNothing);
      expect(find.text('Обзор'), findsNothing);
      expect(find.text('Повторить'), findsNothing);
      expect(find.byType(Sheet), findsOneWidget);
    });
  }

  testWidgets('только недоступность хранилища предлагает повтор, и он снова '
      'читает выбор', (tester) async {
    final harness = await _openSheet(tester);

    harness.repository.fail(const DailyChoiceReadUnavailableFailure());
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось загрузить дневной выбор. Повторите попытку.'),
      findsOneWidget,
    );
    expect(harness.repository.watchCount, 1);

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.text('Загружаем дневной выбор…'), findsOneWidget);
    expect(harness.repository.watchCount, 2);

    harness.repository.emit(_details());
    await tester.pumpAndSettle();
    expect(find.text('Действие'), findsOneWidget);
  });

  testWidgets('общее сообщение появляется над панелью, а её закрытие снимает '
      'подписку', (tester) async {
    final harness = await _openSheet(tester);
    harness.repository.emit(_details());
    await tester.pumpAndSettle();

    ScaffoldMessenger.of(tester.element(find.byType(Sheet)))
        .showSnackBar(const SnackBar(content: Text('Сообщение')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Sheet), matching: find.text('Сообщение')),
      findsOneWidget,
    );

    expect(harness.repository.controller.hasListener, isTrue);
    Navigator.of(tester.element(find.byType(Sheet))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(harness.repository.controller.hasListener, isFalse);
  });

  testWidgets('флажок отправляет обратное выполнение и выключен на время '
      'записи, а новое состояние приходит из подписки', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);
    final repository = harness.repository;
    repository.emit(_details());
    await tester.pumpAndSettle();
    final options = tester.getRect(_options);

    await tester.tap(_check);
    await tester.pump();

    expect(repository.sentCompletion, [true]);
    expect(
      tester.getSemantics(_check),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
    expect(
      tester.getSemantics(_options),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
    expect(tester.getRect(_options), options);

    repository.succeedUpdate();
    await tester.pumpAndSettle();
    expect(_actionDecoration(tester), isNull);

    repository.emit(_details(isCompleted: true));
    await tester.pumpAndSettle();
    expect(_actionDecoration(tester), TextDecoration.lineThrough);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester.getSemantics(_check),
      isSemantics(hasEnabledState: true, isEnabled: true),
    );

    await tester.tap(_check);
    await tester.pump();
    expect(repository.sentCompletion, [true, false]);
    repository.succeedUpdate();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('приоритет меняется сразу записью одного поля без сообщения, а '
      'пока она идёт, поля недоступны и не открывают листы', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);
    final repository = harness.repository;
    repository.emit(_details());
    await tester.pumpAndSettle();

    await setDailyChoicePriority(tester, DailyChoicePriority.p1);
    await tester.pump();

    expect(repository.sentPatches.map(_onlyField), [
      ('priority', DailyChoicePriority.p1),
    ]);
    expect(_fields(tester).enabled, isFalse);
    expect(_head(tester).onToggle, isNull);
    expect(_head(tester).options, isA<ChoiceHeadOptionsUnavailable>());
    expect(_picker(tester).value, DoablePriority.p4);
    expect(_head(tester).priority, DoablePriority.p4);

    await tester.tap(_fieldButton('Дата'));
    await tester.tap(_fieldButton('Время'));
    await tester.pumpAndSettle();
    expect(find.byType(DateGrid), findsNothing);
    expect(find.byType(TimeDial), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(PriorityPicker),
        matching: find.text('P2'),
      ),
    );
    await tester.pump();
    expect(repository.sentPatches, hasLength(1));

    repository.succeedUpdate();
    repository.emit(_details(priority: DailyChoicePriority.p1));
    await tester.pumpAndSettle();

    expect(_picker(tester).value, DoablePriority.p1);
    expect(_head(tester).priority, DoablePriority.p1);
    expect(
      tester.widget<ReasonChain>(find.byType(ReasonChain)).priority,
      DoablePriority.p1,
    );
    expect(_fields(tester).enabled, isTrue);
    expect(find.byType(Sheet), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    semantics.dispose();
  });

  testWidgets('отказ записи поля оставляет прежнее значение и отказ в панели, '
      'а поле снова меняется', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);
    final repository = harness.repository;
    repository.emit(_details());
    await tester.pumpAndSettle();

    await setDailyChoicePriority(tester, DailyChoicePriority.p1);
    await tester.pump();
    repository.failCommand(const DailyChoiceUnavailableFailure());
    await tester.pumpAndSettle();

    expect(_picker(tester).value, DoablePriority.p4);
    expect(find.text(_commandFailure), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(_fields(tester).enabled, isTrue);

    await setDailyChoicePriority(tester, DailyChoicePriority.p2);
    await tester.pump();
    expect(repository.sentPatches.map(_onlyField), [
      ('priority', DailyChoicePriority.p1),
      ('priority', DailyChoicePriority.p2),
    ]);
    expect(find.text(_commandFailure), findsNothing);
    repository.succeedUpdate();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  for (final use24HourFormat in [false, true]) {
    testWidgets('час на циферблате ${use24HourFormat ? "24" : "12"}-часового '
        'устройства записывается временем без минут, а панель остаётся '
        'открытой', (tester) async {
      tester.platformDispatcher.alwaysUse24HourFormatTestValue =
          use24HourFormat;
      addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
      final harness = await _openSheet(tester);
      final repository = harness.repository;
      repository.emit(_details());
      await tester.pumpAndSettle();

      await setDailyChoiceHour(tester, 18);
      await tester.pump();

      expect(find.byType(TimeDial), findsNothing);
      expect(repository.sentPatches.map(_onlyField), [
        ('schedule', DailyChoiceTime(hour: 18, minute: 0)),
      ]);
      repository.succeedUpdate();
      repository.emit(_details(schedule: DailyChoiceTime(hour: 18, minute: 0)));
      await tester.pumpAndSettle();

      expect(find.text('18:00'), findsOneWidget);
      expect(find.byType(Sheet), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('«Весь день» возвращает выбору время на весь день', (
    tester,
  ) async {
    final harness = await _openSheet(tester);
    final repository = harness.repository;
    repository.emit(_details(schedule: DailyChoiceTime(hour: 18, minute: 0)));
    await tester.pumpAndSettle();

    await setDailyChoiceAllDay(tester);
    await tester.pump();

    expect(repository.sentPatches.map(_onlyField), [
      ('schedule', const DailyChoiceAllDay()),
    ]);
    repository.succeedUpdate();
    await tester.pumpAndSettle();
  });

  testWidgets('сохранённые минуты не отмечают час на циферблате, а выбор часа '
      'заменяет их целым часом', (tester) async {
    final harness = await _openSheet(tester);
    final repository = harness.repository;
    repository.emit(_details(schedule: DailyChoiceTime(hour: 18, minute: 30)));
    await tester.pumpAndSettle();
    expect(find.text('18:30'), findsOneWidget);

    await tester.tap(_fieldButton('Время'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TimeDial>(find.byType(TimeDial)).selection,
      isA<TimeDialNothingSelected>(),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TimeDial), findsNothing);
    expect(repository.sentPatches, isEmpty);

    await setDailyChoiceHour(tester, 19);
    await tester.pump();
    expect(repository.sentPatches.map(_onlyField), [
      ('schedule', DailyChoiceTime(hour: 19, minute: 0)),
    ]);
    repository.succeedUpdate();
    repository.emit(_details(schedule: DailyChoiceTime(hour: 19, minute: 0)));
    await tester.pumpAndSettle();

    expect(find.text('19:00'), findsOneWidget);
    expect(find.text('18:30'), findsNothing);
  });

  testWidgets('дата выбирается в листе месяца и записывается одним полем, а '
      'выбор уже показанных значений ничего не записывает', (tester) async {
    final harness = await _openSheet(tester);
    final repository = harness.repository;
    repository.emit(_details());
    await tester.pumpAndSettle();

    await setDailyChoiceDate(tester, CalendarDate.fromParts(2026, 10, 8));
    await setDailyChoiceAllDay(tester);
    await setDailyChoicePriority(tester, DailyChoicePriority.p4);
    await tester.pump();
    expect(repository.sentPatches, isEmpty);
    expect(find.byType(DateGrid), findsNothing);
    expect(find.byType(TimeDial), findsNothing);

    await setDailyChoiceDate(tester, CalendarDate.fromParts(2026, 11, 12));
    await tester.pump();

    expect(find.byType(DateGrid), findsNothing);
    expect(repository.sentPatches.map(_onlyField), [
      ('date', CalendarDate.fromParts(2026, 11, 12)),
    ]);
    repository.succeedUpdate();
    repository.emit(_details(date: CalendarDate.fromParts(2026, 11, 12)));
    await tester.pumpAndSettle();

    expect(find.text('12 нояб.'), findsOneWidget);
    expect(find.byType(Sheet), findsOneWidget);
  });

  testWidgets('отказ стоит над содержимым обеих вкладок, выбор остаётся '
      'подтверждённым, а флажок снова отправляет запись', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);
    final repository = harness.repository;
    repository.emit(_details());
    await tester.pumpAndSettle();

    await tester.tap(_check);
    await tester.pump();
    repository.failCommand(const DailyChoiceUnavailableFailure());
    await tester.pumpAndSettle();

    final notice = find.text(_commandFailure);
    expect(notice, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(_actionDecoration(tester), isNull);
    expect(
      tester.getRect(notice).top,
      greaterThan(tester.getRect(_tabs).bottom),
    );
    expect(
      tester.getRect(notice).bottom,
      lessThan(tester.getRect(find.text('Пояснение')).top),
    );

    await tester.tap(find.text('Путь'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(notice).bottom,
      lessThan(tester.getRect(find.byType(ui.ChoicePath)).top),
    );

    await tester.tap(_check);
    await tester.pump();
    expect(repository.sentCompletion, [true, true]);
    expect(notice, findsNothing);
    repository.succeedUpdate();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('новый отказ виден без ручной прокрутки, когда тело прокручено '
      'мимо него', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);
    harness.repository.emit(_details(description: _longText));
    await tester.pumpAndSettle();
    await _scrollBodyToEnd(tester);
    expect(find.text('Дата').hitTestable(), findsOneWidget);

    await tester.tap(_check);
    await tester.pump();
    harness.repository.failCommand(const DailyChoiceUnavailableFailure());
    await tester.pumpAndSettle();

    expect(find.text(_commandFailure).hitTestable(), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('новый отказ виден без ручной прокрутки, когда высокая шапка '
      'вытеснила его из видимой части', (tester) async {
    _useLowScreen(tester);
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);
    harness.repository.emit(_details(actionTitle: _longTitle));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_tabs).top,
      greaterThan(tester.getRect(find.byType(Sheet)).bottom),
    );

    tester.widget<ChoiceHead>(find.byType(ChoiceHead)).onToggle!();
    await tester.pump();
    harness.repository.failCommand(const DailyChoiceUnavailableFailure());
    await tester.pumpAndSettle();

    expect(find.text(_commandFailure).hitTestable(), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('перекрытая панель хранит отказ и показывает его при возврате, а '
      'её закрытие отказ не повторяет', (tester) async {
    _useLowScreen(tester);
    final semantics = tester.ensureSemantics();
    final (repository, router) = await _openOnRouter(tester);
    repository.emit(_details(middleTitle: _longTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Путь'));
    await tester.pumpAndSettle();
    await _scrollBodyToEnd(tester);

    await tester.tap(_check);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('daily-choice-intention-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(router.current.name, IntentionDetailsRoute.name);

    repository.failCommand(const DailyChoiceUnavailableFailure());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_commandFailure).hitTestable(), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    semantics.dispose();
  });

  testWidgets('сброс истории над панелью отдаёт отказ общей поверхности один '
      'раз', (tester) async {
    final semantics = tester.ensureSemantics();
    final (repository, _) = await _openOnRouter(tester);
    repository.emit(_details());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Путь'));
    await tester.pumpAndSettle();
    await tester.tap(_check);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('daily-choice-intention-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    repository.failCommand(const DailyChoiceUnavailableFailure());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(appNavigationDestination(AppDestination.home));
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(find.textContaining(_commandFailure), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('закрытие панели до результата отдаёт отказ общей поверхности '
      'один раз', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _openSheet(tester);
    harness.repository.emit(_details());
    await tester.pumpAndSettle();
    await tester.tap(_check);
    await tester.pump();

    Navigator.of(tester.element(find.byType(Sheet))).pop();
    await tester.pumpAndSettle();
    harness.repository.failCommand(const DailyChoiceUnavailableFailure());
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(find.textContaining(_commandFailure), findsOneWidget);
    semantics.dispose();
  });
}

const _commandFailure =
    'Не удалось выполнить действие с дневным выбором. Повторите попытку.';

const _notFound = 'Дневной выбор больше не существует.';

/// Подтверждает удаление из меню; запись остаётся незавершённой.
Future<void> _startDeletion(WidgetTester tester) async {
  await tester.tap(_options);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Удалить дневной выбор'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Удалить'));
  await tester.pump();
}

/// Флажок и кнопка параметров выключены.
void _expectHeadLocked(WidgetTester tester) {
  final head = tester.widget<ChoiceHead>(find.byType(ChoiceHead));
  expect(head.onToggle, isNull);
  expect(head.options, isA<ChoiceHeadOptionsUnavailable>());
}

/// Проходит закрытие панели по кадрам: пока она в дереве, в ней прежние
/// шапка, вкладки и «Обзор» с выключенной шапкой и нет того, что выбора нет.
Future<void> _expectClosingKeepsContent(WidgetTester tester) async {
  var frames = 0;
  while (find.byType(Sheet).evaluate().isNotEmpty) {
    expect(frames, lessThan(60), reason: 'Панель не закрылась.');
    expect(find.text('Действие'), findsOneWidget);
    expect(_tabs, findsOneWidget);
    expect(find.text('Пояснение'), findsOneWidget);
    expect(find.text(_notFound), findsNothing);
    _expectHeadLocked(tester);
    frames++;
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(frames, greaterThan(2));
}

/// Не помещается в тело панели и в полном размере.
final _longText = List.filled(300, 'слово').join(' ');

/// Название наибольшей допустимой длины.
final _longTitle = 'слово ' * 42;

/// Первый жест раскрывает панель, второй прокручивает тело к концу.
Future<void> _scrollBodyToEnd(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await tester.drag(
      find.descendant(
        of: find.byType(Sheet),
        matching: find.byType(CustomScrollView),
      ),
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
  }
}

void _useLowScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(440, 420)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

DailyChoiceDetailFields _fields(WidgetTester tester) =>
    tester.widget<DailyChoiceDetailFields>(dailyChoiceDetailFields);

ChoiceHead _head(WidgetTester tester) =>
    tester.widget<ChoiceHead>(find.byType(ChoiceHead));

PriorityPicker _picker(WidgetTester tester) =>
    tester.widget<PriorityPicker>(find.byType(PriorityPicker));

/// Пилюля поля с названием [label].
Finder _fieldButton(String label) => find.descendant(
  of: find.widgetWithText(DetailRow, label),
  matching: find.byType(Button),
);

/// Единственное поле изменения: его имя и значение. Каждый выбор в панели —
/// отдельная запись одного поля.
(String, Object) _onlyField(DailyChoiceFieldsPatch patch) => [
  if (patch.date case DailyChoiceFieldSet(:final value)) ('date', value),
  if (patch.schedule case DailyChoiceFieldSet(:final value))
    ('schedule', value),
  if (patch.priority case DailyChoiceFieldSet(:final value))
    ('priority', value),
  if (patch.isCompleted case DailyChoiceFieldSet(:final value))
    ('completed', value),
  if (patch.description is! DailyChoiceDescriptionUnchanged)
    ('description', patch.description),
].single;

final _check = find.bySemanticsLabel(RegExp('^Выполнение выбора'));
final _options = find.bySemanticsLabel('Параметры дневного выбора');

TextDecoration? _actionDecoration(WidgetTester tester) =>
    tester.widget<Text>(find.text('Действие')).style!.decoration;

final _tabs = find.byWidgetPredicate((widget) => widget is Tabs);

/// Значок архива на вкладке: у отметок шапки такой же.
final _archiveIcon = find.descendant(
  of: _tabs,
  matching: find.byWidgetPredicate(
    (widget) => widget is DoableIcon && widget.icon == DoableIconData.archive,
  ),
);

/// Число на вкладке «Путь».
String _tabCount(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: _tabs,
        matching: find.textContaining(RegExp(r'^\d+$')),
      ),
    )
    .data!;

enum _Archived { source, middle, selected, relation }

final class _Harness {
  const _Harness(this.repository, this.localDate);

  final _Repository repository;
  final ControlledDailyChoiceLocalDate localDate;
}

/// Открывает панель над страницей; выбор приходит из [_Repository.emit].
Future<_Harness> _openSheet(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
}) async {
  final repository = _Repository();
  addTearDown(repository.dispose);
  final localDate = ControlledDailyChoiceLocalDate(
    CalendarDate.fromParts(2026, 10, 8),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
        dailyChoiceLocalDateSourceProvider.overrideWithValue(localDate.read),
      ],
      child: OrdinaryPageTestApp(
        locale: locale,
        builder: (_, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  unawaited(showDailyChoiceSheet(context, _choice)),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Открыть'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return _Harness(repository, localDate);
}

/// Открывает панель над корневой страницей настоящего [AppRouter].
Future<(_Repository, AppRouter)> _openOnRouter(WidgetTester tester) async {
  final repository = _Repository();
  final router = AppRouter();
  addTearDown(() async {
    router.dispose();
    await repository.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(
    showDailyChoiceSheet(
      tester.element(find.byType(AppNavigationBar)),
      _choice,
    ),
  );
  await tester.pump();
  return (repository, router);
}

String _uuid(int n) =>
    '018f0b5d-6b2e-7c80-8000-${n.toRadixString(16).padLeft(12, '0')}';
final _choice =
    (DailyChoiceId.decode(_uuid(1)) as DailyChoiceIdDecodingSuccess).id;
IntentionId _intentionId(int n) =>
    (IntentionId.decode(_uuid(n)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relationId(int n) => (LongTermRelationId.decode(
  _uuid(n),
) as LongTermRelationIdDecodingSuccess).id;
ChoicePathStepId _stepId(int n) =>
    (ChoicePathStepId.decode(_uuid(n)) as ChoicePathStepIdDecodingSuccess).id;

Intention _intention(int n, String title, {required bool archived}) =>
    Intention(
      id: _intentionId(n),
      title: title,
      description: null,
      readiness: IntentionReadiness.ready,
      archiveState: archived
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
      createdAt: IntentionTimestamp(DateTime.utc(2026)),
      updatedAt: IntentionTimestamp(DateTime.utc(2026)),
    );

DailyChoiceDetails _details({
  CalendarDate? date,
  DailyChoiceSchedule schedule = const DailyChoiceAllDay(),
  DailyChoicePriority priority = DailyChoicePriority.p4,
  String description = 'Пояснение',
  bool isCompleted = false,
  bool emptyPath = false,
  bool oneStep = false,
  Set<_Archived> archived = const {},
  String middleTitle = 'Середина',
  String actionTitle = 'Действие',
}) {
  final source = _intention(
    1,
    'Основа',
    archived: archived.contains(_Archived.source),
  );
  final middle = _intention(
    2,
    middleTitle,
    archived: archived.contains(_Archived.middle),
  );
  final selected = _intention(
    3,
    actionTitle,
    archived: archived.contains(_Archived.selected),
  );
  final choice = DailyChoice(
    id: _choice,
    sourceIntentionId: source.id,
    selectedIntentionId: selected.id,
    date: date ?? CalendarDate.fromParts(2026, 10, 8),
    schedule: schedule,
    priority: priority,
    description: DailyChoiceDescription.fromInput(description),
    isCompleted: isCompleted,
  );
  DailyChoicePathStepDetails step(
    int n,
    Intention from,
    Intention to,
    RelationScope scope,
  ) => DailyChoicePathStepDetails(
    step: ChoicePathStep(
      id: _stepId(n),
      dailyChoiceId: choice.id,
      relationId: _relationId(n),
      previousStepId: n == 1 ? null : _stepId(n - 1),
    ),
    relation: LongTermRelation(
      id: _relationId(n),
      sourceIntentionId: from.id,
      relatedIntentionId: to.id,
      type: n == 1 ? LongTermRelationType.need : LongTermRelationType.can,
      priority: RelationPriority.p2,
      scope: scope,
      creationSequence: RelationCreationSequence(n),
      createdAt: RelationTimestamp(DateTime.utc(2026)),
      updatedAt: RelationTimestamp(DateTime.utc(2026)),
    ),
    description: null,
    source: from,
    related: to,
  );
  return DailyChoiceDetails(
    choice: choice,
    source: source,
    selected: selected,
    path: emptyPath
        ? const []
        : oneStep
        ? [step(1, source, selected, RelationScope.active)]
        : [
            step(
              1,
              source,
              middle,
              archived.contains(_Archived.relation)
                  ? RelationScope.archived
                  : RelationScope.active,
            ),
            step(2, middle, selected, RelationScope.active),
          ],
  );
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    final n = value.compareTo((other as _Revision).value);
    return n < 0
        ? GraphRevisionOrder.older
        : n > 0
        ? GraphRevisionOrder.newer
        : GraphRevisionOrder.same;
  }
}

final class _Change implements GraphChange {
  const _Change(this.revision);

  @override
  final GraphRevision revision;
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final controller = StreamController<DailyChoiceReadResult>.broadcast(
    sync: true,
  );
  var watchCount = 0;
  var _revision = 0;
  final watchedRelations = <LongTermRelationId>[];
  final _commands = <UpdateDailyChoiceFields>[];
  final _requests = <Completer<DailyChoiceCommandResult>>[];

  /// Изменения полей из отправленных команд.
  List<DailyChoiceFieldsPatch> get sentPatches => [
    for (final command in _commands) command.patch,
  ];

  /// Значения выполнения из отправленных команд.
  List<bool> get sentCompletion => [
    for (final command in _commands)
      switch (command.patch.isCompleted) {
        DailyChoiceFieldSet(:final value) => value,
        DailyChoiceFieldUnchanged() => throw StateError(
          'Выполнение не менялось.',
        ),
      },
  ];

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is UpdateDailyChoiceFields) {
      _commands.add(command as UpdateDailyChoiceFields);
    }
    final request = Completer<DailyChoiceCommandResult>();
    _requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void failCommand(DailyChoiceCommandFailure failure) =>
      _requests.last.complete(GraphCommandFailed(failure));

  void succeedDelete() {
    final details = _details();
    _requests.last.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(++_revision),
          value: DailyChoiceDeleted(
            choice: details.choice,
            changes: [_Change(_Revision(_revision))],
          ),
        ),
      ),
    );
  }

  /// Подтверждает запись; новое значение приходит отдельно через [emit].
  void succeedUpdate() {
    final details = _details();
    _requests.last.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(++_revision),
          value: DailyChoiceFieldsUpdated(
            before: details.choice,
            choice: details.choice,
            path: StoredChoicePath(details.path.map((step) => step.step)),
            changes: [_Change(_Revision(_revision))],
          ),
        ),
      ),
    );
  }

  /// Лист даты запрашивает отметки дней; отметок в этих сценариях нет.
  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) async => DailyChoiceDayStatusesReadSuccess(
    GraphSnapshot(
      revision: _Revision(_revision),
      value: DailyChoiceDayStatuses(query: query, statuses: const {}),
    ),
  );

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) {
    watchedRelations.add(id);
    return const Stream.empty();
  }

  @override
  Stream<Result<GraphSnapshot<application.IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => const Stream.empty();

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) {
    watchCount++;
    return controller.stream;
  }

  void emit(DailyChoiceDetails details) => controller.add(
    DailyChoiceReadSuccess(
      GraphSnapshot(value: details, revision: _Revision(++_revision)),
    ),
  );

  void emitMissing() => controller.add(
    DailyChoiceReadSuccess(
      GraphSnapshot<DailyChoiceDetails?>(
        value: null,
        revision: _Revision(++_revision),
      ),
    ),
  );

  void fail(DailyChoiceReadFailure failure) =>
      controller.add(DailyChoiceReadError(failure));

  Future<void> dispose() => controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
