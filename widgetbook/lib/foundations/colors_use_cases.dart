import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// Все цвета модуля основ оформления в выбранной теме каталога.
List<WidgetbookUseCase> colorsUseCases() => [
  WidgetbookUseCase(
    name: 'Палитра',
    builder: (context) {
      final colors = Theme.of(context).extension<DoableColors>()!;
      final entries = colors.entries;
      return Scaffold(
        body: ListView.separated(
          padding: const EdgeInsets.all(DoableMetrics.space6),
          itemCount: entries.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: DoableMetrics.space4),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: entry.color,
                    border: Border.all(color: colors.hairline),
                    borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
                  ),
                ),
                const SizedBox(width: DoableMetrics.space4),
                Expanded(child: Text(entry.name)),
              ],
            );
          },
        ),
      );
    },
  ),
];
