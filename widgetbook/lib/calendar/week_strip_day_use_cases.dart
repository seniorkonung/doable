import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/week_strip_day.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// Все сочетания выбранности, сегодняшнего дня и отметки из спек-доски.
List<WidgetbookUseCase> weekStripDayUseCases() => [
  WidgetbookUseCase(
    name: 'Состояния дня',
    builder: (context) => const _DayStates(),
  ),
  WidgetbookUseCase(
    name: 'Выбор дня в неделе',
    builder: (context) => const _WeekPreview(),
  ),
];

class _DayStates extends StatelessWidget {
  const _DayStates();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(DoableMetrics.space6),
      children: [
        for (final mark in DayMark.values) ...[
          Text(_markLabel(mark)),
          const SizedBox(height: DoableMetrics.space4),
          Wrap(
            spacing: DoableMetrics.space4,
            runSpacing: DoableMetrics.space4,
            children: [
              for (final state in _states)
                SizedBox(
                  width: 128,
                  child: Column(
                    children: [
                      WeekStripDay(
                        dayText: '8',
                        weekdayText: 'Чт',
                        isSelected: state.selected,
                        isToday: state.today,
                        mark: mark,
                        semanticLabel: [
                          'Четверг, 8 октября 2026',
                          if (state.today) 'сегодня',
                          if (mark != DayMark.none) _markLabel(mark),
                        ].join(', '),
                        onTap: () {},
                      ),
                      const SizedBox(height: DoableMetrics.space2),
                      Text(state.label, textAlign: TextAlign.center),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: DoableMetrics.space8),
        ],
      ],
    ),
  );
}

const _states = [
  (label: 'Обычный', selected: false, today: false),
  (label: 'Сегодня', selected: false, today: true),
  (label: 'Выбран', selected: true, today: false),
  (label: 'Выбран, сегодня', selected: true, today: true),
];

String _markLabel(DayMark mark) => switch (mark) {
  DayMark.none => 'Без отметки',
  DayMark.todo => 'Есть невыполненный',
  DayMark.done => 'Всё выполнено',
};

class _WeekPreview extends StatefulWidget {
  const _WeekPreview();

  @override
  State<_WeekPreview> createState() => _WeekPreviewState();
}

class _WeekPreviewState extends State<_WeekPreview> {
  var selected = 3;
  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _fullWeekdays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DoableMetrics.space3,
            vertical: DoableMetrics.space1,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: WeekStripDay.rowHeight(
                context,
                dayTexts: const ['5', '6', '7', '8', '9', '10', '11'],
                weekdayTexts: _weekdays,
                columnWidth: constraints.maxWidth / 7,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < 7; index++)
                    Expanded(
                      child: WeekStripDay(
                        dayText: '${index + 5}',
                        weekdayText: _weekdays[index],
                        isSelected: index == selected,
                        isToday: index == 3,
                        mark: DayMark.values[index % DayMark.values.length],
                        semanticLabel: [
                          '${_fullWeekdays[index]}, ${index + 5} октября 2026',
                          if (index == 3) 'сегодня',
                          if (index % DayMark.values.length != 0)
                            _markLabel(
                              DayMark.values[index % DayMark.values.length],
                            ),
                        ].join(', '),
                        onTap: () => setState(() => selected = index),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
