import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/month_grid_day.dart';
import 'package:doable/src/design_system/components/month_grid_weekday.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

List<WidgetbookUseCase> monthGridDayUseCases() => [
  WidgetbookUseCase(
    name: 'Состояния дня',
    builder: (context) => const _DayStates(),
  ),
  WidgetbookUseCase(
    name: 'Ряд дней и подписей',
    builder: (context) => const _MonthRowPreview(),
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
              for (final outside in [false, true])
                for (final state in _states)
                  SizedBox(
                    width: 128,
                    child: Column(
                      children: [
                        MonthGridDay(
                          dayText: '30',
                          isSelected: state.selected,
                          isToday: state.today,
                          isOutsideMonth: outside,
                          mark: mark,
                          semanticLabel: [
                            'Среда, 30 сентября 2026',
                            if (state.today) 'сегодня',
                            if (mark != DayMark.none) _markLabel(mark),
                          ].join(', '),
                          onTap: () {},
                        ),
                        const SizedBox(height: DoableMetrics.space2),
                        Text(
                          '${state.label}${outside ? ', соседний месяц' : ''}',
                          textAlign: TextAlign.center,
                        ),
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

class _MonthRowPreview extends StatefulWidget {
  const _MonthRowPreview();

  @override
  State<_MonthRowPreview> createState() => _MonthRowPreviewState();
}

class _MonthRowPreviewState extends State<_MonthRowPreview> {
  var selected = 3;
  static const _numbers = ['28', '29', '30', '1', '2', '3', '4'];
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
          padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space3),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: MonthGridWeekday.rowHeight(
                    context,
                    texts: _weekdays,
                    columnWidth: constraints.maxWidth / 7,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final weekday in _weekdays)
                        Expanded(child: MonthGridWeekday(text: weekday)),
                    ],
                  ),
                ),
                SizedBox(
                  height: MonthGridDay.rowHeight(
                    context,
                    dayTexts: _numbers,
                    columnWidth: constraints.maxWidth / 7,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < 7; index++)
                        Expanded(
                          child: MonthGridDay(
                            dayText: _numbers[index],
                            isSelected: selected == index,
                            isToday: index == 3,
                            isOutsideMonth: index < 3,
                            mark: DayMark.values[index % DayMark.values.length],
                            semanticLabel: [
                              '${_fullWeekdays[index]}, ${_numbers[index]} '
                                  '${index < 3 ? 'сентября' : 'октября'} 2026',
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
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
