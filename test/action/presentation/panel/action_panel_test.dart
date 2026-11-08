import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/reason_chain.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_panel_controls.dart';
import '../../../support/action_panel_fixture.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('панель показывает шапку, описание, поля и строку дат', (
    tester,
  ) async {
    final repository = await openActionPanel(tester);
    repository.emit(
      actionDetailsFixture(
        description: 'Пояснение',
        schedule: ActionAtHour(18),
        priority: ActionPriority.p2,
        pathLength: 3,
        updatedAt: DateTime.utc(2026, 10, 8, 9),
      ),
    );
    await tester.pumpAndSettle();

    final head = shownActionHead(tester);
    expect(head.goal, 'Быть здоровым');
    expect(head.action, 'Пробежка');
    expect(head.priority, DoablePriority.p2);
    expect(head.done, isFalse);
    expect(tester.widget<ReasonChain>(find.byType(ReasonChain)).reasons, 3);
    expect(actionPanelField('Пояснение'), findsOneWidget);
    expect(actionPanelField('Сегодня'), findsOneWidget);
    expect(actionPanelField('18:00'), findsOneWidget);
    expect(
      actionPanelField('Создано 6 окт. · Изменено 8 окт.'),
      findsOneWidget,
    );
  });

  for (final (name, change, expected) in <(String, _Change, (String, Object))>[
    ('приоритет', _pickPriority, ('priority', ActionPriority.p1)),
    ('время', _pickHour, ('schedule', ActionAtHour(18))),
    ('дата', _pickDay, ('date', CalendarDate.fromParts(2026, 10, 12))),
    ('выполнение', _toggleCompletion, ('completed', true)),
  ]) {
    testWidgets('$name меняется сразу отдельной записью одного поля, а панель '
        'остаётся открытой', (tester) async {
      final repository = await openActionPanel(tester);
      repository.emit(actionDetailsFixture());
      await tester.pumpAndSettle();

      await change(tester);

      expect(_onlyField(repository.sentPatches.single), expected);
      repository.succeedUpdate();
      await tester.pump();
      expect(actionPanel, findsOneWidget);
    });
  }

  testWidgets('перенос даты показывает новую дату только после подтверждённой '
      'записи и оставляет панель открытой', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    await _pickDay(tester);
    repository.succeedUpdate();
    await tester.pump();
    expect(actionPanelField('Сегодня'), findsOneWidget);

    repository.emit(
      actionDetailsFixture(date: CalendarDate.fromParts(2026, 10, 12)),
    );
    await tester.pumpAndSettle();

    expect(actionPanel, findsOneWidget);
    expect(actionPanelField('12 окт.'), findsOneWidget);
    expect(actionPanelField('Сегодня'), findsNothing);
  });

  testWidgets('закрытие листа даты без выбора ничего не записывает', (
    tester,
  ) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    await tester.tap(_field('Дата'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();

    expect(find.text('Октябрь 2026'), findsNothing);
    expect(repository.commands, isEmpty);
  });

  testWidgets('пока запись идёт и снимок с записанным значением не показан, '
      'флажок и поля недоступны, а прежнее значение остаётся на экране', (
    tester,
  ) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    await _pickPriority(tester);
    _expectLocked(tester);

    repository.succeedUpdate();
    await tester.pump();
    _expectLocked(tester);
    expect(shownActionHead(tester).priority, DoablePriority.p4);

    repository.emit(actionDetailsFixture(priority: ActionPriority.p1));
    await tester.pumpAndSettle();
    expect(shownActionHead(tester).priority, DoablePriority.p1);
    expect(shownActionHead(tester).onToggle, isNotNull);
    expect(_picker(tester).onChange, isNotNull);
  });

  testWidgets('доказанно временный отказ записи остаётся в панели с последним '
      'подтверждённым значением, и поле можно изменить снова', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    await _pickPriority(tester);
    repository.failCommand(const ActionUnavailableFailure());
    await tester.pumpAndSettle();

    expect(
      actionPanelField(
        'Не удалось выполнить операцию с действием. Повторите попытку.',
      ),
      findsOneWidget,
    );
    expect(shownActionHead(tester).priority, DoablePriority.p4);
    expect(shownActionHead(tester).onToggle, isNotNull);
    expect(_picker(tester).onChange, isNotNull);
  });

  testWidgets('после отказа без явного повтора флажок недоступен, пока '
      'действие не обновлено, и отклонённое изменение не отправляется '
      'повторно', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    await _toggleCompletion(tester);
    repository.failCommand(const ActionUnexpectedFailure());
    await tester.pumpAndSettle();

    expect(
      actionPanelField(
        'Операция с действием не выполнена из-за непредвиденной ошибки.',
      ),
      findsOneWidget,
    );
    expect(shownActionHead(tester).onToggle, isNull);
    expect(_picker(tester).onChange, isNotNull);

    await tester.tap(find.text('Обновить действие'));
    await tester.pump();
    expect(shownActionHead(tester).onToggle, isNull);

    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    expect(shownActionHead(tester).onToggle, isNotNull);
    expect(find.text('Обновить действие'), findsNothing);
    expect(repository.commands, hasLength(1));
  });

  for (final (outcome, finish, text)
      in <(String, void Function(ActionPanelRepository), String)>[
        (
          'отсутствие действия',
          (repository) => repository.emitMissing(),
          'Действие больше не существует.',
        ),
        (
          'повреждение',
          (repository) =>
              repository.failRead(const ActionReadCorruptionFailure()),
          'Сохранённое действие повреждено и не может быть показано.',
        ),
        (
          'неизвестный отказ',
          (repository) =>
              repository.failRead(const ActionReadUnexpectedFailure()),
          'Не удалось загрузить действие из-за непредвиденной ошибки.',
        ),
      ]) {
    testWidgets('$outcome чтения называется в панели вместо шапки', (
      tester,
    ) async {
      final repository = await openActionPanel(tester);
      finish(repository);
      await tester.pumpAndSettle();

      expect(actionPanelField(text), findsOneWidget);
      expect(actionPanelReady, findsNothing);
    });
  }

  testWidgets('временная недоступность чтения предлагает повтор, который '
      'показывает действие', (tester) async {
    final repository = await openActionPanel(tester);
    repository.failRead(const ActionReadUnavailableFailure());
    await tester.pumpAndSettle();
    expect(
      actionPanelField('Не удалось загрузить действие. Повторите попытку.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    expect(actionPanelReady, findsOneWidget);
    expect(repository.watchCount, 2);
  });

  testWidgets('закрытие панели снимает подписку на действие', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();
    expect(shownActionId(tester), actionIdOf(1));
    expect(repository.hasListener, isTrue);

    await closeActionPanel(tester);

    expect(repository.hasListener, isFalse);
  });
}

/// Изменение поля или выполнения так, как его делает человек в панели.
typedef _Change = Future<void> Function(WidgetTester tester);

Future<void> _pickPriority(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(PriorityPicker), matching: find.text('P1')),
  );
  await tester.pump();
}

Future<void> _pickHour(WidgetTester tester) async {
  await tester.tap(_field('Время'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('18'));
  await tester.pumpAndSettle();
}

Future<void> _pickDay(WidgetTester tester) async {
  await tester.tap(_field('Дата'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('12'));
  await tester.pumpAndSettle();
}

Future<void> _toggleCompletion(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^Выполнение действия')));
  await tester.pump();
}

/// Пилюля поля с названием [label].
Finder _field(String label) => find.descendant(
  of: find.widgetWithText(DetailRow, label),
  matching: find.byType(Button),
);

PriorityPicker _picker(WidgetTester tester) =>
    tester.widget<PriorityPicker>(find.byType(PriorityPicker));

/// Флажок, дата, время и приоритет не принимают изменений.
void _expectLocked(WidgetTester tester) {
  expect(shownActionHead(tester).onToggle, isNull);
  expect(_picker(tester).onChange, isNull);
  for (final label in ['Дата', 'Время']) {
    expect(
      tester.widget<Button>(_field(label)).onPressed,
      isNull,
      reason: label,
    );
  }
}

/// Единственное поле изменения: его имя и значение. Каждый выбор в панели —
/// отдельная запись одного поля.
(String, Object?) _onlyField(ActionFieldsPatch patch) => [
  if (patch.title case ActionFieldSet(:final value)) ('title', value),
  if (patch.description case ActionFieldSet(:final value))
    ('description', value),
  if (patch.date case ActionFieldSet(:final value)) ('date', value),
  if (patch.schedule case ActionFieldSet(:final value)) ('schedule', value),
  if (patch.priority case ActionFieldSet(:final value)) ('priority', value),
  if (patch.isCompleted case ActionFieldSet(:final value)) ('completed', value),
].single;
