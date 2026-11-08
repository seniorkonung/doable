import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/design_system/components/action_head.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
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

  for (final (name, description, open, focused)
      in <(String, String?, _Open, _Field)>[
        ('нажатие на название в шапке', 'Пояснение', _tapTitle, _Field.title),
        (
          'нажатие на описание',
          'Пояснение',
          _tapDescription,
          _Field.description,
        ),
        (
          'нажатие на подсказку «Добавить описание»',
          null,
          _tapDescription,
          _Field.description,
        ),
        (
          'пункт «Изменить название и описание»',
          'Пояснение',
          _openByMenu,
          _Field.title,
        ),
      ]) {
    testWidgets('$name открывает изменение на весь экран с сохранёнными '
        'значениями и фокусом на нужном поле', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await openActionPanel(tester);
      repository.emit(actionDetailsFixture(description: description));
      await tester.pumpAndSettle();
      expect(_sheetRect(tester), isNot(_fullScreen(tester)));

      await open(tester);

      expect(_sheetRect(tester), _fullScreen(tester));
      expect(find.widgetWithText(TopBar, 'Изменить действие'), findsOneWidget);
      expect(find.byType(ActionHead), findsNothing);
      expect(_text(tester, _Field.title), 'Пробежка');
      expect(_text(tester, _Field.description), description ?? '');
      expect(_focus(tester, _Field.title).hasFocus, focused == _Field.title);
      expect(
        _focus(tester, _Field.description).hasFocus,
        focused == _Field.description,
      );
      semantics.dispose();
    });
  }

  testWidgets('меню «Действие» содержит пункт изменения названия и описания', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    await tester.tap(_options);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Sheet).last,
        matching: find.text('Изменить название и описание'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('«Сохранить» недоступна без изменений и при пустом после обрезки '
      'названии', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(description: 'Пояснение'));
    await tester.pumpAndSettle();
    await _tapTitle(tester);
    expect(_saveEnabled(tester), isFalse);

    await _enter(tester, _Field.description, 'Новое');
    expect(_saveEnabled(tester), isTrue);

    await _enter(tester, _Field.title, '   ');
    expect(_saveEnabled(tester), isFalse);

    await _enter(tester, _Field.title, 'Пробежка');
    await _enter(tester, _Field.description, 'Пояснение');
    expect(_saveEnabled(tester), isFalse);
    expect(repository.commands, isEmpty);
  });

  testWidgets('сохранение записывает оба поля одним изменением без сообщения '
      'и закрывает изменение только со снимком записанных значений', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(description: 'Пояснение'));
    await tester.pumpAndSettle();
    await _tapTitle(tester);

    await _enter(tester, _Field.title, '  Силовая тренировка ног  ');
    await _enter(tester, _Field.description, '  Первая строка\nвторая  ');
    await tester.tap(_save);
    await tester.pump();

    final patch = repository.sentPatches.single;
    expect(
      (patch.title as ActionFieldSet<ActionTitle>).value,
      ActionTitle('Силовая тренировка ног'),
    );
    expect(
      (patch.description as ActionFieldSet<ActionDescription?>).value,
      ActionDescription.fromInput('  Первая строка\nвторая  '),
    );
    expect(patch.date, isA<ActionFieldUnchanged<Object?>>());
    expect(patch.schedule, isA<ActionFieldUnchanged<Object?>>());
    expect(patch.priority, isA<ActionFieldUnchanged<Object?>>());
    expect(patch.isCompleted, isA<ActionFieldUnchanged<bool>>());
    _expectLocked(tester);

    repository.succeedUpdate();
    await tester.pump();
    expect(find.widgetWithText(TopBar, 'Изменить действие'), findsOneWidget);
    _expectLocked(tester);

    repository.emit(
      actionDetailsFixture(
        title: 'Силовая тренировка ног',
        description: '  Первая строка\nвторая  ',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TopBar), findsNothing);
    expect(shownActionHead(tester).action, 'Силовая тренировка ног');
    expect(find.text('  Первая строка\nвторая  '), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(repository.commands, hasLength(1));
    semantics.dispose();
  });

  testWidgets('пробельное описание записывается как отсутствие описания', (
    tester,
  ) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(description: 'Пояснение'));
    await tester.pumpAndSettle();
    await _tapDescription(tester);

    await _enter(tester, _Field.description, '   ');
    await tester.tap(_save);
    await tester.pump();

    final patch = repository.sentPatches.single;
    expect(
      (patch.description as ActionFieldSet<ActionDescription?>).value,
      isNull,
    );
  });

  testWidgets('название и описание выполненного действия остаются '
      'изменяемыми', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(isCompleted: true));
    await tester.pumpAndSettle();
    await _tapTitle(tester);

    await _enter(tester, _Field.title, 'Бег');
    await tester.tap(_save);
    await tester.pump();

    final patch = repository.sentPatches.single;
    expect(
      (patch.title as ActionFieldSet<ActionTitle>).value,
      ActionTitle('Бег'),
    );
    expect(patch.isCompleted, isA<ActionFieldUnchanged<bool>>());
  });

  for (final (name, field, text, message) in <(String, _Field, String, String)>[
    (
      'название длиннее предела',
      _Field.title,
      'я' * 256,
      'Используйте не более 255 символов.',
    ),
    (
      'описание длиннее предела',
      _Field.description,
      'я' * 4097,
      'Используйте не более 4096 символов.',
    ),
  ]) {
    testWidgets('$name показано отказом у поля без записи, а текст остаётся '
        'в поле до следующего ввода', (tester) async {
      final repository = await openActionPanel(tester);
      repository.emit(actionDetailsFixture(description: 'Пояснение'));
      await tester.pumpAndSettle();
      await _tapTitle(tester);

      await _enter(tester, field, text);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(_text(tester, field), text);
      expect(repository.commands, isEmpty);

      await _enter(tester, field, '$text!');
      expect(find.text(message), findsNothing);
    });
  }

  testWidgets('отказ записи остаётся в панели с введённым текстом, и '
      'сохранение снова доступно', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();
    await _tapTitle(tester);
    await _enter(tester, _Field.title, 'Бег');

    await tester.tap(_save);
    await tester.pump();
    repository.failCommand(const ActionUnavailableFailure());
    await tester.pumpAndSettle();

    expect(find.byType(TopBar), findsOneWidget);
    expect(
      find.text(
        'Не удалось выполнить операцию с действием. Повторите попытку.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(_text(tester, _Field.title), 'Бег');
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('стрелка назад без правок возвращает «Обзор» без вопроса', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();
    await _tapTitle(tester);

    await tester.tap(_back);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TopBar), findsNothing);
    expect(actionPanelReady, findsOneWidget);
    expect(repository.commands, isEmpty);
    semantics.dispose();
  });

  testWidgets('стрелка назад с правками спрашивает подтверждение: «Продолжить '
      'правку» сохраняет текст, «Отменить» возвращает прежние значения', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(description: 'Пояснение'));
    await tester.pumpAndSettle();
    await _tapDescription(tester);
    await _enter(tester, _Field.description, 'Новое');

    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.text('Отменить изменения?'), findsOneWidget);
    expect(
      find.text('Изменения названия и описания не сохранятся.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Продолжить правку'));
    await tester.pumpAndSettle();
    expect(_text(tester, _Field.description), 'Новое');

    await tester.tap(_back);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();

    expect(find.byType(TopBar), findsNothing);
    expect(actionPanelField('Пояснение'), findsOneWidget);
    expect(actionPanelField('Новое'), findsNothing);
    expect(repository.commands, isEmpty);
    semantics.dispose();
  });

  testWidgets('системное «назад» с правками спрашивает подтверждение, а '
      '«Отменить» закрывает панель без записи', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();
    await _tapTitle(tester);
    await _enter(tester, _Field.title, 'Бег');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить правку'));
    await tester.pumpAndSettle();
    expect(_text(tester, _Field.title), 'Бег');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();

    expect(actionPanel, findsNothing);
    expect(repository.commands, isEmpty);
  });

  testWidgets('пока идёт запись поля, название, описание и параметры '
      'недоступны', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(description: 'Пояснение'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(PriorityPicker),
        matching: find.text('P1'),
      ),
    );
    await tester.pump();

    final head = shownActionHead(tester);
    expect(head.nameEdit, isA<ActionHeadButtonUnavailable>());
    expect(head.options, isA<ActionHeadButtonUnavailable>());
    await tester.tap(find.text('Пояснение'));
    await tester.pump();
    expect(find.byType(TopBar), findsNothing);
  });
}

enum _Field { title, description }

/// Открытие изменения так, как его делает человек.
typedef _Open = Future<void> Function(WidgetTester tester);

Future<void> _tapTitle(WidgetTester tester) async {
  await tester.tap(find.text('Пробежка'));
  await tester.pumpAndSettle();
}

Future<void> _tapDescription(WidgetTester tester) async {
  final description = find.descendant(
    of: actionPanel,
    matching: find.textContaining(RegExp('Пояснение|Добавить описание')),
  );
  await tester.tap(description);
  await tester.pumpAndSettle();
}

Future<void> _openByMenu(WidgetTester tester) async {
  await tester.tap(_options);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Изменить название и описание'));
  await tester.pumpAndSettle();
}

final _options = find.bySemanticsLabel('Параметры действия');
final _save = find.widgetWithText(Button, 'Сохранить');
final _back = find.bySemanticsLabel('Назад к действию');

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<Button>(_save).onPressed != null;

EditableText _editable(WidgetTester tester, _Field field) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .elementAt(field.index);

String _text(WidgetTester tester, _Field field) =>
    _editable(tester, field).controller.text;

FocusNode _focus(WidgetTester tester, _Field field) =>
    _editable(tester, field).focusNode;

Future<void> _enter(WidgetTester tester, _Field field, String text) async {
  await tester.enterText(find.byType(EditableText).at(field.index), text);
  await tester.pump();
}

/// Панель, а не страница под ней: на весь экран листа нет строки состояния.
Rect _sheetRect(WidgetTester tester) => tester.getRect(find.byType(Sheet).last);

Rect _fullScreen(WidgetTester tester) =>
    Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;

/// Пока запись идёт, поля, «Сохранить» и стрелка назад недоступны.
void _expectLocked(WidgetTester tester) {
  for (final field in _Field.values) {
    expect(_editable(tester, field).readOnly, isTrue, reason: '$field');
  }
  expect(_saveEnabled(tester), isFalse);
  expect(tester.getSemantics(_back), isSemantics(isEnabled: false));
}
