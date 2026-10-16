import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import '../text_metrics.dart';

/// Готовые данные позиции выбора; периодом управляет потребитель.
///
/// [semanticLabel] включает признак текущего периода, если он есть;
/// показанность передаётся отдельно как состояние выбранности.
final class PeriodPickerCell {
  const PeriodPickerCell({
    required this.text,
    required this.semanticLabel,
    required this.onTap,
    this.isShown = false,
    this.isCurrent = false,
  });

  final String text;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool isShown;
  final bool isCurrent;
}

/// Геометрия сетки, рассчитанная через [PeriodPicker.layoutFor].
final class PeriodPickerLayout {
  const PeriodPickerLayout._(this.rowHeight);

  final double rowHeight;

  /// Четыре строки, включая пустые позиции, и верхний отступ сетки.
  double get height => rowHeight * 4 + _gridPadding.vertical;
}

/// Двенадцать позиций по три в ряд; null оставляет пустое место без команды.
///
/// Шапка и ручка добавляются потребителем. Сетка не листается и не хранит
/// состояние выбора. Размеры растут от минимальных при увеличении текста.
final class PeriodPicker extends StatelessWidget {
  const PeriodPicker({super.key, required this.cells, this.layout})
    : assert(cells.length == 12);

  final List<PeriodPickerCell?> cells;

  /// Общая геометрия страниц при тех же ширине и настройках текста.
  /// Без неё сетка измеряет только собственные ячейки.
  final PeriodPickerLayout? layout;

  /// Измеряет сетку по всем подписям, которые должны помещаться на страницах.
  /// Пересчитывается при изменении ширины, локали или настроек текста.
  static PeriodPickerLayout layoutFor(
    BuildContext context, {
    required double width,
    required Iterable<String> texts,
  }) => PeriodPickerLayout._(
    math.max(
      48.0,
      tallestTextHeight(
            context,
            texts: texts,
            style: _cellStyle(const FontWeight(650)),
            maxWidth: width / 3 - _boxPadding.horizontal,
          ) +
          _boxPadding.vertical +
          _inset.vertical,
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final geometry =
          layout ??
          layoutFor(
            context,
            width: constraints.maxWidth,
            texts: cells.nonNulls.map((cell) => cell.text),
          );
      // Фиксированное число колонок и высота строки без внутренней прокрутки:
      // https://api.flutter.dev/flutter/widgets/GridView/GridView.count.html
      return GridView.count(
        crossAxisCount: 3,
        mainAxisExtent: geometry.rowHeight,
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: _gridPadding,
        children: [
          for (final cell in cells)
            if (cell == null) const SizedBox.shrink() else _Cell(cell: cell),
        ],
      );
    },
  );
}

final class _Cell extends StatelessWidget {
  const _Cell({required this.cell});

  final PeriodPickerCell cell;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    const radius = BorderRadius.all(Radius.circular(DoableMetrics.radiusSm));
    // Одна кнопка с готовым названием, без дублирования текста:
    // https://api.flutter.dev/flutter/widgets/Semantics-class.html
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      selected: cell.isShown,
      label: cell.semanticLabel,
      onTap: cell.onTap,
      child: Material(
        type: MaterialType.transparency,
        // Ink сохраняет отклик нажатия поверх заливки:
        // https://api.flutter.dev/flutter/material/InkWell-class.html
        child: InkWell(
          borderRadius: radius,
          onTap: cell.onTap,
          child: Padding(
            padding: _inset,
            child: Center(
              child: Ink(
                decoration: BoxDecoration(
                  color: cell.isShown ? colors.fill : null,
                  borderRadius: radius,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 88,
                    minHeight: 36,
                  ),
                  child: Padding(
                    padding: _boxPadding,
                    child: Text(
                      cell.text,
                      textAlign: TextAlign.center,
                      style:
                          _cellStyle(
                            cell.isShown || cell.isCurrent
                                ? const FontWeight(650)
                                : FontWeight.w500,
                          ).copyWith(
                            color: cell.isCurrent ? colors.accent : colors.ink,
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

const _inset = EdgeInsets.symmetric(vertical: 6);
const _boxPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 7);
const _gridPadding = EdgeInsets.only(top: DoableMetrics.space1);

TextStyle _cellStyle(FontWeight weight) => DoableType.title.copyWith(
  fontWeight: weight,
  letterSpacing: 0,
  fontFeatures: const [FontFeature.tabularFigures()],
);
