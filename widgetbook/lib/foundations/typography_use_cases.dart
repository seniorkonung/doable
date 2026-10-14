import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// Все стили модуля основ оформления с образцами на двух языках.
List<WidgetbookUseCase> typographyUseCases() => [
  WidgetbookUseCase(
    name: 'Стили текста',
    builder: (context) => Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.all(DoableMetrics.space6),
        itemCount: DoableType.entries.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: DoableMetrics.space6),
        itemBuilder: (context, index) {
          final entry = DoableType.entries[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: DoableMetrics.space2),
              Text('Быть здоровым и учиться новому', style: entry.style),
              Text('Be healthy and learn something new', style: entry.style),
            ],
          );
        },
      ),
    ),
  ),
];
