import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_date_sheet.dart';
import 'package:doable/src/design_system/components/date_grid.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/controlled_local_date.dart';

void main() {
  testWidgets('лист называется датой дневного выбора, показывает месяц '
      'текущей даты, отмечает её выбранной, а сегодняшний день — '
      'сегодняшним', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await _pump(tester, current: _date(2026, 10, 8));
    await app.open(tester);

    expect(find.bySemanticsLabel('Дата дневного выбора'), findsOneWidget);
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(
      _isSelected(tester, _full('четверг, 8 октября 2026 г.')),
      Tristate.isTrue,
    );
    expect(
      _isSelected(tester, _full('пятница, 9 октября 2026 г.')),
      Tristate.isFalse,
    );
    expect(
      find.bySemanticsLabel(_full('понедельник, 5 октября 2026 г., Сегодня')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('день соседнего месяца закрывает лист и возвращает свою дату', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final app = await _pump(tester, current: _date(2026, 10, 8));
    await app.open(tester);

    await tester.tap(
      find.bySemanticsLabel(_full('воскресенье, 1 ноября 2026 г.')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DateGrid), findsNothing);
    expect(app.result, _date(2026, 11, 1));
    handle.dispose();
  });

  testWidgets('закрытие без выбора ничего не возвращает', (tester) async {
    final app = await _pump(tester, current: _date(2026, 10, 8));
    await app.open(tester);

    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();

    expect(find.byType(DateGrid), findsNothing);
    expect(app.closedWithoutChoice, isTrue);
    expect(app.result, isNull);
  });

  testWidgets('отметки дней приходят из хранилища, а переход к другому месяцу '
      'передаёт модели новый просмотр', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await _pump(
      tester,
      current: _date(2026, 10, 8),
      marks: {
        _date(2026, 10, 5): ActionDayStatus.allCompleted,
        _date(2026, 10, 6): ActionDayStatus.hasIncomplete,
        _date(2026, 12, 15): ActionDayStatus.hasIncomplete,
      },
    );
    await app.open(tester);

    expect(
      find.bySemanticsLabel(
        _full(
          'понедельник, 5 октября 2026 г., Сегодня, '
          'Все действия выполнены',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        _full('вторник, 6 октября 2026 г., Есть невыполненное действие'),
      ),
      findsOneWidget,
    );

    // Декабрь лежит за окном отметок октября: отметку дня 15 декабря модель
    // читает только по просмотру, который лист передал после перехода.
    await tester.tap(find.bySemanticsLabel('Следующий месяц'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Следующий месяц'));
    await tester.pumpAndSettle();

    expect(find.text('Декабрь 2026'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        _full('вторник, 15 декабря 2026 г., Есть невыполненное действие'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('отказ получения отметок не мешает листу даты', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await _pump(
      tester,
      current: _date(2026, 10, 8),
      marksReadFails: true,
    );
    await app.open(tester);

    await tester.tap(find.bySemanticsLabel('Следующий месяц'));
    await tester.pumpAndSettle();

    expect(find.text('Ноябрь 2026'), findsOneWidget);
    expect(find.text('Отметки дней не загружены.'), findsNothing);

    await tester.tap(
      find.bySemanticsLabel(_full('четверг, 12 ноября 2026 г.')),
    );
    await tester.pumpAndSettle();

    expect(app.result, _date(2026, 11, 12));
    handle.dispose();
  });

  testWidgets('на крайних допустимых месяцах лист открывается, а переход за '
      'диапазон недоступен', (tester) async {
    final handle = tester.ensureSemantics();
    for (final (current, title, fullDate, unavailable) in [
      (
        CalendarDate.earliest,
        'Январь 1',
        _full('понедельник, 1 января 1 г.'),
        'Предыдущий месяц',
      ),
      (
        CalendarDate.latest,
        'Декабрь 9999',
        _full('пятница, 31 декабря 9999 г.'),
        'Следующий месяц',
      ),
    ]) {
      final app = await _pump(tester, current: current);
      await app.open(tester);

      expect(find.text(title), findsOneWidget, reason: '$current');
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(unavailable))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
        reason: '$current',
      );

      await tester.tap(find.bySemanticsLabel(fullDate));
      await tester.pumpAndSettle();

      expect(app.result, current, reason: '$current');
    }
    handle.dispose();
  });
}

/// Подпись дня по-русски отделяет «г.» узким неразрывным пробелом.
String _full(String label) => label.replaceFirst(' г.', '\u202fг.');

CalendarDate _date(int year, int month, int day) =>
    CalendarDate.fromParts(year, month, day);

Tristate _isSelected(WidgetTester tester, String label) => tester
    .getSemantics(find.bySemanticsLabel(label))
    .getSemanticsData()
    .flagsCollection
    .isSelected;

/// Страница с кнопкой, которая открывает лист даты и запоминает результат.
final class _App {
  CalendarDate? result;
  var closedWithoutChoice = false;

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
  }
}

/// Сегодня — 2026-10-05, а хранилище отдаёт [marks] в пределах запрошенного
/// окна или отказ чтения при [marksReadFails].
Future<_App> _pump(
  WidgetTester tester, {
  required CalendarDate current,
  Map<CalendarDate, ActionDayStatus> marks = const {},
  bool marksReadFails = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = _App();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWith(
          (ref) => _Repository(marks, readFails: marksReadFails),
        ),
        ControlledLocalDate(_date(2026, 10, 5)).override,
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: doableTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final result = await showDailyChoiceDateSheet(
                    context,
                    current,
                  );
                  app.result = result;
                  app.closedWithoutChoice = result == null;
                },
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return app;
}

final class _Repository implements PersonalGraphRepository {
  _Repository(this._marks, {required this.readFails});

  final Map<CalendarDate, ActionDayStatus> _marks;
  final bool readFails;

  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) async {
    if (readFails) {
      return const ActionDayStatusesReadError(
        ActionDayStatusesUnexpectedFailure(),
      );
    }
    bool inWindow(CalendarDate date) =>
        _key(date).compareTo(_key(query.firstDate)) >= 0 &&
        _key(date).compareTo(_key(query.lastDate)) <= 0;
    return ActionDayStatusesReadSuccess(
      GraphSnapshot(
        revision: const _Revision(),
        value: ActionDayStatuses(
          query: query,
          statuses: {
            for (final entry in _marks.entries)
              if (inWindow(entry.key)) entry.key: entry.value,
          },
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _key(CalendarDate date) => date.toCanonicalString();

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}
