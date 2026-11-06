import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/design_system/components/action_head.dart';
import 'package:doable/src/design_system/components/sheet.dart';
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

  testWidgets('меню «Действие» предлагает «Удалить действие» с пояснением, что '
      'намерения и связи остаются', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();

    await tester.tap(_options);
    await tester.pumpAndSettle();

    final menu = find.byType(Sheet).last;
    expect(
      find.descendant(of: menu, matching: find.text('Удалить действие')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: menu,
        matching: find.text('Намерения и связи останутся'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  for (final (name, date, phrase) in <(String, CalendarDate, String)>[
    ('сегодняшняя дата словом', CalendarDate.fromParts(2026, 10, 8), 'сегодня'),
    (
      'другая дата числом и месяцем',
      CalendarDate.fromParts(2026, 10, 12),
      '12 октября',
    ),
  ]) {
    testWidgets('вопрос «Удалить действие?» называет $name, необратимость и '
        'то, что намерения и связи остаются', (tester) async {
      final repository = await openActionPanel(tester);
      repository.emit(actionDetailsFixture(date: date));
      await tester.pumpAndSettle();

      await _chooseDelete(tester);

      expect(find.text('Удалить действие?'), findsOneWidget);
      expect(
        _dialogText(tester),
        'Действие Пробежка на $phrase будет удалено. Удаление нельзя '
        'отменить. Намерения и связи его пути останутся.',
      );
      expect(repository.deletions, isEmpty);
    });
  }

  testWidgets('отмена вопроса ничего не меняет: панель остаётся открытой, '
      'команда не отправлена', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();
    await _chooseDelete(tester);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить действие?'), findsNothing);
    expect(actionPanelReady, findsOneWidget);
    expect(repository.deletions, isEmpty);
    expect(find.textContaining('Действие удалено.'), findsNothing);
  });

  for (final (order, missingFirst) in [
    ('снимок без действия приходит до подтверждения', true),
    ('снимок без действия приходит после подтверждения', false),
  ]) {
    testWidgets('подтверждённое удаление закрывает панель с прежним '
        'содержимым и сообщает «Действие удалено» один раз: $order', (
      tester,
    ) async {
      final repository = await openActionPanel(tester);
      repository.emit(actionDetailsFixture(description: 'Пояснение'));
      await tester.pumpAndSettle();
      await _startDeletion(tester);
      expect(repository.deletions.single.actionId, actionIdOf(1));
      _expectHeadLocked(tester);

      if (missingFirst) {
        repository.emitMissing();
        await tester.pump();
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
      expect(find.textContaining('Действие удалено.'), findsOneWidget);
    });
  }

  testWidgets('отказ удаления остаётся в панели, которая открыта', (
    tester,
  ) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();
    await _startDeletion(tester);

    repository.failCommand(const ActionUnavailableFailure());
    await tester.pumpAndSettle();

    expect(actionPanelReady, findsOneWidget);
    expect(
      find.text(
        'Не удалось выполнить операцию с действием. Повторите попытку.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(shownActionHead(tester).onToggle, isNotNull);
  });

  testWidgets('отказ удаления действия, которого тем временем не стало, '
      'оставляет панель открытой с тем, что действия нет', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture());
    await tester.pumpAndSettle();
    await _startDeletion(tester);
    repository.emitMissing();
    await tester.pump();
    expect(find.text(_notFound), findsNothing);

    repository.failCommand(const ActionNotFoundFailure());
    await tester.pumpAndSettle();

    expect(actionPanel, findsOneWidget);
    expect(find.text(_notFound), findsWidgets);
    expect(find.byType(ActionHead), findsNothing);
  });
}

const _notFound = 'Действие больше не существует.';

final _options = find.bySemanticsLabel('Параметры действия');

Future<void> _chooseDelete(WidgetTester tester) async {
  await tester.tap(_options);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Удалить действие'));
  await tester.pumpAndSettle();
}

/// Подтверждает вопрос; запись остаётся незавершённой.
Future<void> _startDeletion(WidgetTester tester) async {
  await _chooseDelete(tester);
  await tester.tap(find.text('Удалить'));
  await tester.pump();
}

/// Текст вопроса одним абзацем.
String _dialogText(WidgetTester tester) => tester
    .widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith('Действие Пробежка'),
      ),
    )
    .text
    .toPlainText();

/// Флажок и кнопки шапки выключены.
void _expectHeadLocked(WidgetTester tester) {
  final head = shownActionHead(tester);
  expect(head.onToggle, isNull);
  expect(head.nameEdit, isA<ActionHeadButtonUnavailable>());
  expect(head.options, isA<ActionHeadButtonUnavailable>());
}

/// Проходит закрытие панели по кадрам: пока она в дереве, в ней прежние шапка
/// и «Обзор» с выключенной шапкой и нет того, что действия нет.
Future<void> _expectClosingKeepsContent(WidgetTester tester) async {
  var frames = 0;
  while (find.byType(Sheet).evaluate().isNotEmpty) {
    expect(frames, lessThan(60), reason: 'Панель не закрылась.');
    expect(find.text('Пробежка'), findsOneWidget);
    expect(find.text('Пояснение'), findsOneWidget);
    expect(find.text(_notFound), findsNothing);
    _expectHeadLocked(tester);
    frames++;
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(frames, greaterThan(2));
}
