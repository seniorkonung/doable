import 'package:doable/src/design_system/components/calendar_header.dart';
import 'package:doable/src/design_system/components/period_picker.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

List<WidgetbookUseCase> periodPickerUseCases() => [
  WidgetbookUseCase(
    name: 'Годы: показанный и текущий',
    builder: (context) => _PeriodPreview(
      title: '2026',
      texts: [for (var year = 2020; year <= 2031; year++) '$year'],
      shownIndex: 6,
      currentIndex: 8,
    ),
  ),
  WidgetbookUseCase(
    name: 'Месяцы: совпадение признаков',
    builder: (context) => const _PeriodPreview(
      title: '2026',
      texts: [
        'Январь',
        'Февраль',
        'Март',
        'Апрель',
        'Май',
        'Июнь',
        'Июль',
        'Август',
        'Сентябрь',
        'Октябрь',
        'Ноябрь',
        'Декабрь',
      ],
      shownIndex: 9,
      currentIndex: 9,
      isMonths: true,
    ),
  ),
  WidgetbookUseCase(
    name: 'Начало диапазона: пустые позиции',
    builder: (context) => const _PeriodPreview(
      title: '1',
      texts: [
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        '1',
        '2',
        '3',
      ],
      shownIndex: 9,
      hasPrevious: false,
    ),
  ),
  WidgetbookUseCase(
    name: 'Конец диапазона: недоступная стрелка',
    builder: (context) => _PeriodPreview(
      title: '9999',
      texts: [for (var year = 9988; year <= 9999; year++) '$year'],
      shownIndex: 11,
      hasNext: false,
    ),
  ),
];

class _PeriodPreview extends StatefulWidget {
  const _PeriodPreview({
    required this.title,
    required this.texts,
    required this.shownIndex,
    this.currentIndex,
    this.isMonths = false,
    this.hasPrevious = true,
    this.hasNext = true,
  });

  final String title;
  final List<String?> texts;
  final int shownIndex;
  final int? currentIndex;
  final bool isMonths;
  final bool hasPrevious;
  final bool hasNext;

  @override
  State<_PeriodPreview> createState() => _PeriodPreviewState();
}

class _PeriodPreviewState extends State<_PeriodPreview> {
  var _lastAction = '—';

  void _report(String action) => setState(() => _lastAction = action);

  @override
  Widget build(BuildContext context) {
    final previous = widget.isMonths ? 'Предыдущий год' : 'Предыдущие годы';
    final next = widget.isMonths ? 'Следующий год' : 'Следующие годы';
    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 390,
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: DoableMetrics.space3,
            ),
            children: [
              CalendarHeader(
                title: widget.title,
                titleAction: (
                  semanticLabel: 'Вернуться к дням месяца',
                  isExpanded: true,
                  onTap: () => _report('Вернуться к дням месяца'),
                ),
                previousLabel: previous,
                nextLabel: next,
                onPrevious: widget.hasPrevious ? () => _report(previous) : null,
                onNext: widget.hasNext ? () => _report(next) : null,
              ),
              PeriodPicker(
                cells: [
                  for (var i = 0; i < widget.texts.length; i++)
                    if (widget.texts[i] case final text?)
                      PeriodPickerCell(
                        text: text,
                        semanticLabel: [
                          widget.isMonths ? '$text ${widget.title}' : text,
                          if (i == widget.currentIndex)
                            widget.isMonths ? 'текущий месяц' : 'текущий год',
                        ].join(', '),
                        isShown: i == widget.shownIndex,
                        isCurrent: i == widget.currentIndex,
                        onTap: () => _report(text),
                      )
                    else
                      null,
                ],
              ),
              const SizedBox(height: DoableMetrics.space4),
              Text('Последняя команда: $_lastAction'),
            ],
          ),
        ),
      ),
    );
  }
}
