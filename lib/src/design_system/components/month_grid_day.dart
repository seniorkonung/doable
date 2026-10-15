import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import '../text_metrics.dart';
import 'day_mark.dart';

/// День месячной сетки: число и отметка.
///
/// [semanticLabel] содержит полное доступное название, включая «сегодня»
/// и состояние отметки. Компонент не форматирует и не локализует тексты.
/// Для строки одинаковой высоты потребитель использует [rowHeight].
final class MonthGridDay extends StatelessWidget {
  const MonthGridDay({
    super.key,
    required this.dayText,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideMonth,
    required this.mark,
    required this.semanticLabel,
    required this.onTap,
  });

  final String dayText;
  final bool isSelected;
  final bool isToday;
  final bool isOutsideMonth;
  final DayMark mark;
  final String semanticLabel;
  final VoidCallback onTap;

  /// Высота строки с учётом переносов при [columnWidth] и выделения любого дня.
  static double rowHeight(
    BuildContext context, {
    required Iterable<String> dayTexts,
    required double columnWidth,
  }) => math.max(
    DoableMetrics.tapMin,
    tallestTextHeight(
          context,
          texts: dayTexts,
          style: _numberStyle(const FontWeight(650)),
          maxWidth: math.min(_boxWidth, columnWidth),
        ) +
        DayMarkIndicator.height +
        _padding.vertical +
        _inset.vertical,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final color = switch ((isSelected, isToday, isOutsideMonth)) {
      (true, _, _) => colors.onAccent,
      (_, true, _) => colors.accent,
      (_, _, true) => colors.muted,
      _ => colors.ink,
    };
    final weight = switch ((isSelected, isToday, isOutsideMonth)) {
      (true, _, _) || (_, true, _) => const FontWeight(650),
      (_, _, true) => FontWeight.w400,
      _ => FontWeight.w500,
    };
    const radius = BorderRadius.all(Radius.circular(DoableMetrics.radiusSm));
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: _boxWidth,
        height: rowHeight(
          context,
          dayTexts: [dayText],
          columnWidth: constraints.maxWidth,
        ),
        // Одна кнопка заменяет дочерние подписи для экранного диктора:
        // https://api.flutter.dev/flutter/widgets/Semantics-class.html
        child: Semantics(
          container: true,
          excludeSemantics: true,
          button: true,
          selected: isSelected,
          label: semanticLabel,
          onTap: onTap,
          // Плашка Ink оставляет отклик нажатия видимым поверх заливки:
          // https://api.flutter.dev/flutter/material/InkWell-class.html
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(
                padding: _inset,
                child: Center(
                  child: SizedBox(
                    width: _boxWidth,
                    height: double.infinity,
                    child: Ink(
                      decoration: BoxDecoration(
                        color: isSelected ? colors.accent : null,
                        borderRadius: radius,
                      ),
                      child: Padding(
                        padding: _padding,
                        child: Column(
                          children: [
                            Text(
                              dayText,
                              textAlign: TextAlign.center,
                              style: _numberStyle(weight)
                                  .copyWith(color: color),
                            ),
                            DayMarkIndicator(mark: mark, onAccent: isSelected),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _boxWidth = 44.0;
const _inset = EdgeInsets.symmetric(vertical: 4);
const _padding = EdgeInsets.only(top: 3, bottom: 6);

TextStyle _numberStyle(FontWeight weight) => DoableType.title.copyWith(
  fontWeight: weight,
  letterSpacing: 0,
  fontFeatures: const [FontFeature.tabularFigures()],
);
