import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/presentation/panel/action_time_sheet.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/components/time_dial.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('на 24-часовом устройстве лист показывает два кольца часов, а '
      'час закрывает его целым часом', (tester) async {
    final app = await _pump(
      tester,
      const ActionAllDay(),
      use24HourFormat: true,
    );
    await app.open(tester);

    expect(find.byType(TimeDial), findsOneWidget);
    expect(find.byType(Tabs<TimeDialHalf>), findsNothing);
    expect(find.text('18'), findsOneWidget);
    expect(app.result, isNull);

    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();

    expect(find.byType(TimeDial), findsNothing);
    expect(app.result, ActionAtHour(18));
  });

  testWidgets('«Весь день» закрывает лист и возвращает его вариант', (
    tester,
  ) async {
    final app = await _pump(tester, ActionAtHour(7), use24HourFormat: true);
    await app.open(tester);

    await tester.tap(find.text('Весь день'));
    await tester.pumpAndSettle();

    expect(find.byType(TimeDial), findsNothing);
    expect(app.result, const ActionAllDay());
  });

  testWidgets('закрытие без выбора ничего не возвращает', (tester) async {
    final app = await _pump(tester, ActionAtHour(7), use24HourFormat: true);
    await app.open(tester);

    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();

    expect(find.byType(TimeDial), findsNothing);
    expect(app.closedWithoutChoice, isTrue);
    expect(app.result, isNull);
  });

  testWidgets('отмечен текущий час или «Весь день»', (tester) async {
    final handle = tester.ensureSemantics();
    for (final (schedule, selected) in [
      (ActionAtHour(18), '18:00'),
      (const ActionAllDay(), 'Весь день'),
    ]) {
      final app = await _pump(tester, schedule, use24HourFormat: true);
      await app.open(tester);

      for (final label in ['18:00', '19:00', 'Весь день']) {
        expect(
          _isSelected(tester, label),
          label == selected ? Tristate.isTrue : Tristate.isFalse,
          reason: '$schedule: $label',
        );
      }
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
    }
    handle.dispose();
  });

  testWidgets('лист называется временем действия', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await _pump(
      tester,
      const ActionAllDay(),
      use24HourFormat: true,
    );
    await app.open(tester);

    expect(find.bySemanticsLabel('Время действия'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('на 12-часовом устройстве лист открывается на половине суток '
      'сохранённого времени, а час второй половины даёт час от 12 до 23', (
    tester,
  ) async {
    final app = await _pump(
      tester,
      ActionAtHour(18),
      use24HourFormat: false,
      language: 'en',
    );
    await app.open(tester);

    expect(find.byType(Tabs<TimeDialHalf>), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('00'), findsNothing);

    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();

    expect(app.result, ActionAtHour(18));
  });

  for (final (language, isTwelveHour, selected, other, allDay) in [
    ('ru', false, '18:00', '19:00', 'Весь день'),
    ('en', true, '6:00 PM', '7:00 PM', 'All day'),
  ]) {
    testWidgets('при выключенном 24-часовом времени формат циферблата в '
        'локали $language совпадает с подписями часов, которые собирает та же '
        'функция, что и поле «Время»', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await _pump(
        tester,
        ActionAtHour(18),
        use24HourFormat: false,
        language: language,
      );
      await app.open(tester);

      expect(
        tester.widget<TimeDial>(find.byType(TimeDial)).clock,
        isTwelveHour ? isA<TimeDialClock12>() : isA<TimeDialClock24>(),
      );
      expect(_isSelected(tester, selected), Tristate.isTrue);
      expect(_isSelected(tester, other), Tristate.isFalse);
      expect(_isSelected(tester, allDay), Tristate.isFalse);
      handle.dispose();
    });
  }
}

Tristate _isSelected(WidgetTester tester, String label) => tester
    .getSemantics(find.bySemanticsLabel(label))
    .getSemanticsData()
    .flagsCollection
    .isSelected;

/// Страница с кнопкой, которая открывает лист времени и запоминает результат.
final class _App {
  ActionSchedule? result;
  var closedWithoutChoice = false;

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
  }
}

Future<_App> _pump(
  WidgetTester tester,
  ActionSchedule current, {
  required bool use24HourFormat,
  String language = 'ru',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = _App();
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: doableTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(alwaysUse24HourFormat: use24HourFormat),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await showActionTimeSheet(context, current);
                app.result = result;
                app.closedWithoutChoice = result == null;
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  return app;
}
