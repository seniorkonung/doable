import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';
import '../text_metrics.dart';
import 'day_mark.dart';

/// День недельной полосы: число, день недели и отметка.
///
/// [semanticLabel] — полное доступное название, включая «сегодня» и состояние
/// отметки, если они нужны. Компонент не форматирует и не локализует тексты.
/// Для строки одинаковой высоты потребитель использует [rowHeight].
final class WeekStripDay extends StatelessWidget {
  const WeekStripDay({
    super.key,
    required this.dayText,
    required this.weekdayText,
    required this.isSelected,
    required this.isToday,
    required this.mark,
    required this.semanticLabel,
    required this.onTap,
  });

  final String dayText;
  final String weekdayText;
  final bool isSelected;
  final bool isToday;
  final DayMark mark;
  final String semanticLabel;
  final VoidCallback onTap;

  /// Высота строки, вмещающая все переданные тексты в текущем масштабе.
  /// Учитывает переносы при [columnWidth] и выделение любого дня строки.
  static double rowHeight(
    BuildContext context, {
    required Iterable<String> dayTexts,
    required Iterable<String> weekdayTexts,
    required double columnWidth,
  }) {
    final textWidth =
        math.min(_boxWidth, columnWidth) -
        _padding.horizontal -
        2 * _borderWidth;
    final numberHeight = tallestTextHeight(
      context,
      texts: dayTexts,
      style: _numberStyle(emphasized: true),
      maxWidth: textWidth,
    );
    final weekdayHeight = tallestTextHeight(
      context,
      texts: weekdayTexts,
      style: _weekdayStyle(selected: true),
      maxWidth: textWidth,
    );
    return math.max(
      _minHeight,
      numberHeight +
          weekdayHeight +
          _markGap +
          DayMarkIndicator.height +
          2 * _borderWidth +
          _padding.vertical +
          _inset.vertical,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;
    const radius = BorderRadius.all(Radius.circular(DoableMetrics.radiusMd));
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: math.max(DoableMetrics.tapMin, _boxWidth),
        height: rowHeight(
          context,
          dayTexts: [dayText],
          weekdayTexts: [weekdayText],
          columnWidth: constraints.maxWidth,
        ),
        // Заменяем дочерние подписи одной кнопкой с названием потребителя:
        // https://api.flutter.dev/flutter/widgets/Semantics-class.html
        child: Semantics(
          container: true,
          excludeSemantics: true,
          button: true,
          selected: isSelected,
          label: semanticLabel,
          onTap: onTap,
          // Ink рисует плашку на Material, под откликом всей кнопки:
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
                        color: isSelected ? colors.raised : null,
                        border: Border.all(
                          width: _borderWidth,
                          color: isSelected
                              ? colors.hairline
                              : Colors.transparent,
                        ),
                        borderRadius: radius,
                        boxShadow: isSelected ? shadows.sm : null,
                      ),
                      child: Padding(
                        padding: _padding,
                        child: Column(
                          children: [
                            Text(
                              dayText,
                              textAlign: TextAlign.center,
                              style:
                                  _numberStyle(
                                    emphasized: isSelected || isToday,
                                  ).copyWith(
                                    color: isToday ? colors.accent : colors.ink,
                                  ),
                            ),
                            Text(
                              weekdayText,
                              textAlign: TextAlign.center,
                              style: _weekdayStyle(selected: isSelected)
                                  .copyWith(
                                    color: isSelected
                                        ? colors.ink
                                        : colors.muted,
                                  ),
                            ),
                            const SizedBox(height: _markGap),
                            DayMarkIndicator(mark: mark),
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

const _boxWidth = 48.0;
const _minHeight = 54.0;
const _inset = EdgeInsets.symmetric(vertical: 2);
const _borderWidth = 1.0;
// Ink сам добавляет отступ рамки; здесь только место внутри неё.
const _padding = EdgeInsets.only(top: 1, bottom: 4);
const _markGap = 1.0;

TextStyle _numberStyle({required bool emphasized}) =>
    DoableType.number.copyWith(
      fontWeight: emphasized ? const FontWeight(650) : FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle _weekdayStyle({required bool selected}) =>
    DoableType.caption.copyWith(
      height: 15 / 13,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
