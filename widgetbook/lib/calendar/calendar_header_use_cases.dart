import 'package:doable/src/design_system/components/calendar_header.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

List<WidgetbookUseCase> calendarHeaderUseCases() => [
  WidgetbookUseCase(
    name: 'Соседние месяцы и границы',
    builder: (context) => const _HeaderPreview(),
  ),
];

class _HeaderPreview extends StatefulWidget {
  const _HeaderPreview();

  @override
  State<_HeaderPreview> createState() => _HeaderPreviewState();
}

class _HeaderPreviewState extends State<_HeaderPreview> {
  static const _titles = ['Сентябрь 2026', 'Октябрь 2026', 'Ноябрь 2026'];
  var _month = 1;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 390,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space3),
          children: [
            CalendarHeader(
              title: _titles[_month],
              previousLabel: 'Предыдущий месяц',
              nextLabel: 'Следующий месяц',
              onPrevious: _month == 0 ? null : () => setState(() => _month--),
              onNext: _month == _titles.length - 1
                  ? null
                  : () => setState(() => _month++),
            ),
            const SizedBox(height: DoableMetrics.space4),
            const Text(
              'Сентябрь — ноябрь 2026. На границах соответствующая '
              'стрелка недоступна. Заголовок не выполняет команду.',
            ),
          ],
        ),
      ),
    ),
  );
}
