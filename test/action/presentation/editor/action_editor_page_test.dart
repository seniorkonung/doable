import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/presentation/editor/action_editor_state.dart';
import 'package:doable/src/design_system/components/time_dial.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_editor_controls.dart';
import '../../../support/action_panel_fixture.dart';

void main() {
  testWidgets('лист показывает поля по порядку и начинает со времени «Весь '
      'день» и P4', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());

    final top = [
      'Новое действие',
      'Добавить описание',
      'Быть здоровым',
      'Много ходить',
      'Сегодня',
      'Весь день',
      'P4',
      'Создать действие',
    ].map((text) => tester.getTopLeft(actionEditorValue(text)).dy).toList();
    expect(top, orderedEquals([...top]..sort()));
    expect(actionEditorCanCreate(tester), isFalse);

    await app.enterTexts(tester, title: '  Силовая тренировка  ');
    expect(actionEditorCanCreate(tester), isTrue);
  });

  testWidgets('без пути «Создать действие» недоступна, а свёрнутый путь '
      'просит выбрать причину', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester);
    await app.enterTexts(tester, title: 'Силовая тренировка');

    expect(actionEditorValue('Выберите причину'), findsOneWidget);
    expect(
      actionEditorValue(
        'Действию нужно хотя бы одно намерение, которому оно служит.',
      ),
      findsOneWidget,
    );
    expect(actionEditorCanCreate(tester), isFalse);
  });

  testWidgets('свёрнутый путь называет корневое и конечное намерения и число '
      'промежуточных', (tester) async {
    final app = await pumpActionEditorPage(tester);
    final path = twoIntentionDraftPath();
    await app.open(
      tester,
      path: ActionDraftPath(
        root: path.root,
        steps: [
          for (var number = 0; number < 3; number++)
            ActionDraftPathStep(
              relation: LongTermRelationType.can,
              intention: ActionDraftIntention(
                id: intentionIdOf(20 + number),
                title: 'Намерение ${number + 2}',
              ),
            ),
        ],
      ),
    );

    expect(actionEditorValue('Быть здоровым'), findsOneWidget);
    expect(actionEditorValue('2 промежуточных намерения'), findsOneWidget);
    expect(actionEditorValue('Намерение 4'), findsOneWidget);
    expect(actionEditorValue('Намерение 2'), findsNothing);
  });

  testWidgets('создание без выбора времени и приоритета сохраняет «Весь день» '
      'и P4 с обрезанным названием', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await app.enterTexts(tester, title: '  Силовая тренировка  ');

    await app.create(tester);

    final command = app.repository.creations.single;
    expect(command.title.value, 'Силовая тренировка');
    expect(command.description, isNull);
    expect(command.path.intentions, [intentionIdOf(11), intentionIdOf(12)]);
    expect(command.date, actionEditorToday);
    expect(command.schedule, const ActionAllDay());
    expect(command.priority, ActionPriority.p4);
  });

  testWidgets('подтверждённое создание очищает текст, оставляет путь, дату, '
      'время и приоритет и создаёт следующее действие', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(
      tester,
      path: twoIntentionDraftPath(),
      date: CalendarDate.fromParts(2026, 10, 12),
    );
    await _pickTime(tester, '18');
    await _pickPriority(tester, 'P2');
    await app.enterTexts(
      tester,
      title: 'Силовая тренировка',
      description: 'Три подхода',
    );

    await app.create(tester);
    app.repository.succeed();
    await tester.pumpAndSettle();

    expect(actionEditor, findsOneWidget);
    expect(_text(tester, actionEditorTitleField), isEmpty);
    expect(_text(tester, actionEditorDescriptionField), isEmpty);
    expect(actionEditorValue('Много ходить'), findsOneWidget);
    expect(actionEditorValue('12 окт.'), findsOneWidget);
    expect(actionEditorValue('18:00'), findsOneWidget);
    expect(actionEditorValue('P2'), findsOneWidget);
    expect(
      find.descendant(
        of: actionEditor,
        matching: find.textContaining('Действие создано.'),
      ),
      findsOneWidget,
    );

    await app.enterTexts(tester, title: 'Растяжка');
    await app.create(tester);

    expect(app.repository.creations, hasLength(2));
    final next = app.repository.creations.last;
    expect(next.title.value, 'Растяжка');
    expect(next.description, isNull);
    expect(next.date, CalendarDate.fromParts(2026, 10, 12));
    expect(next.schedule, ActionAtHour(18));
    expect(next.priority, ActionPriority.p2);
  });

  testWidgets('новая сессия после изменённых времени и приоритета снова '
      'начинается с «Весь день» и P4', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await _pickTime(tester, '18');
    await _pickPriority(tester, 'P1');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(actionEditor, findsNothing);

    await app.open(tester, path: twoIntentionDraftPath());
    await app.enterTexts(tester, title: 'Растяжка');
    await app.create(tester);

    expect(actionEditorValue('Весь день'), findsOneWidget);
    expect(actionEditorValue('P4'), findsOneWidget);
    expect(app.repository.creations.single.schedule, const ActionAllDay());
    expect(app.repository.creations.single.priority, ActionPriority.p4);
  });

  testWidgets('во время создания повтор и правка текста недоступны', (
    tester,
  ) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await app.enterTexts(tester, title: 'Силовая тренировка');

    await app.create(tester);
    await tester.tap(actionEditorCreateButton);
    await tester.pump();

    expect(app.repository.creations, hasLength(1));
    expect(actionEditorCanCreate(tester), isFalse);
    expect(
      tester.widget<EditableText>(actionEditorTitleField).readOnly,
      isTrue,
    );
    expect(
      tester.widget<EditableText>(actionEditorDescriptionField).readOnly,
      isTrue,
    );
  });

  testWidgets('отказ сохраняет поля, снова допускает правку, а повтор '
      'отправляет видимое описание', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await _pickPriority(tester, 'P3');
    await app.enterTexts(
      tester,
      title: 'Силовая тренировка',
      description: 'Три подхода',
    );

    await app.create(tester);
    app.repository.fail(const ActionUnavailableFailure());
    await tester.pumpAndSettle();

    expect(
      actionEditorValue(
        'Не удалось выполнить операцию с действием. Повторите попытку.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(_text(tester, actionEditorTitleField), 'Силовая тренировка');
    expect(actionEditorValue('P3'), findsOneWidget);
    expect(
      tester.widget<EditableText>(actionEditorDescriptionField).readOnly,
      isFalse,
    );

    await app.enterTexts(tester, description: 'Пять подходов');
    await app.create(tester);

    expect(app.repository.creations.last.description?.value, 'Пять подходов');
  });

  testWidgets('слишком длинное название остаётся у поля без отправки команды', (
    tester,
  ) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await app.enterTexts(tester, title: 'а' * 256);

    await app.create(tester);

    expect(app.repository.creations, isEmpty);
    expect(
      actionEditorValue('Используйте не более 255 символов.'),
      findsOneWidget,
    );
    expect(actionEditorCanCreate(tester), isFalse);
  });

  testWidgets('смахивание с введённым текстом спрашивает, «Продолжить ввод» '
      'оставляет лист, а «Сбросить» закрывает его без создания', (
    tester,
  ) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await app.enterTexts(tester, title: 'Силовая тренировка');

    await _swipeDown(tester);

    expect(find.text('Отменить новое действие?'), findsOneWidget);
    expect(
      find.text('Введённые название и описание не будут сохранены.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Продолжить ввод'));
    await tester.pumpAndSettle();
    expect(actionEditor, findsOneWidget);
    expect(_text(tester, actionEditorTitleField), 'Силовая тренировка');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();

    expect(actionEditor, findsNothing);
    expect(find.text('Новое действие'), findsOneWidget);
    expect(app.repository.creations, isEmpty);
  });

  testWidgets('после создания лист с пустым текстом закрывается затемнением '
      'без вопроса', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await _pickPriority(tester, 'P2');
    await app.enterTexts(tester, title: 'Силовая тренировка');
    await app.create(tester);
    app.repository.succeed();
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();

    expect(find.text('Отменить новое действие?'), findsNothing);
    expect(actionEditor, findsNothing);
  });

  testWidgets('закрытие во время создания не спрашивает, а поздний отказ '
      'показывает общая поверхность', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await app.enterTexts(tester, title: 'Силовая тренировка');
    await app.create(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Отменить новое действие?'), findsNothing);
    expect(actionEditor, findsNothing);

    app.repository.fail(const ActionPathConflictFailure());
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Путь больше не совпадает с графом.'),
      findsOneWidget,
    );
  });

  testWidgets('отказ, показанный в листе, не повторяется общей поверхностью '
      'после закрытия', (tester) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await app.enterTexts(tester, title: 'Силовая тренировка');
    await app.create(tester);
    app.repository.fail(const ActionCorruptionFailure());
    await tester.pumpAndSettle();
    expect(
      actionEditorValue('Сохранённые данные повреждены. Действие не изменено.'),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();

    expect(actionEditor, findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('приоритет выбирается в листе P1–P4 с пояснениями крайних', (
    tester,
  ) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());

    await tester.tap(actionEditorValue('P4'));
    await tester.pumpAndSettle();

    expect(find.text('Самый высокий'), findsOneWidget);
    expect(find.text('Самый низкий'), findsOneWidget);
    for (final name in ['P1', 'P2', 'P3']) {
      expect(find.text(name), findsOneWidget);
    }

    await tester.tap(find.text('P1'));
    await tester.pumpAndSettle();

    expect(find.text('Самый высокий'), findsNothing);
    expect(actionEditorValue('P1'), findsOneWidget);
  });

  testWidgets('дата выбирается поверх листа без создания действия', (
    tester,
  ) async {
    final app = await pumpActionEditorPage(tester);
    await app.open(tester, path: twoIntentionDraftPath());
    await app.enterTexts(tester, title: 'Силовая тренировка');

    await tester.tap(actionEditorValue('Сегодня'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();

    expect(actionEditorValue('12 окт.'), findsOneWidget);
    expect(_text(tester, actionEditorTitleField), 'Силовая тренировка');
    expect(app.repository.creations, isEmpty);
  });
}

String _text(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(field).controller.text;

Future<void> _pickTime(WidgetTester tester, String hour) async {
  await tester.tap(actionEditorValue('Весь день'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(TimeDial), matching: find.text(hour)),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickPriority(WidgetTester tester, String priority) async {
  await tester.tap(actionEditorValue('P4'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(priority).last);
  await tester.pumpAndSettle();
}

Future<void> _swipeDown(WidgetTester tester) async {
  await tester.fling(
    actionEditorValue('Новое действие'),
    const Offset(0, 400),
    1500,
  );
  await tester.pumpAndSettle();
}
