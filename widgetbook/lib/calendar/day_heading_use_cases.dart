import 'package:doable/src/design_system/components/day_heading.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

List<WidgetbookUseCase> dayHeadingUseCases() => [
  WidgetbookUseCase(
    name: 'Сегодня и другой день',
    builder: (context) => Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 390,
          child: ListView(
            padding: const EdgeInsets.all(DoableMetrics.space5),
            children: [
              DayHeading(
                weekday: context.knobs.string(
                  label: 'День недели',
                  initialValue: 'Четверг',
                ),
                date: context.knobs.string(
                  label: 'Дата',
                  initialValue: '8 октября 2026',
                ),
                todayLabel: 'Сегодня',
              ),
              const SizedBox(height: DoableMetrics.space6),
              const DayHeading(weekday: 'Среда', date: '7 октября 2026'),
            ],
          ),
        ),
      ),
    ),
  ),
];
