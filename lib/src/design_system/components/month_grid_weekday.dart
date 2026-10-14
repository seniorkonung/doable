import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_type.dart';
import '../text_metrics.dart';

/// Готовая короткая подпись дня недели над месячной сеткой.
final class MonthGridWeekday extends StatelessWidget {
  const MonthGridWeekday({super.key, required this.text});

  final String text;

  /// Общая высота строки подписей с учётом масштаба и ширины столбца.
  static double rowHeight(
    BuildContext context, {
    required Iterable<String> texts,
    required double columnWidth,
  }) => math.max(
    _minHeight,
    tallestTextHeight(
          context,
          texts: texts,
          style: _style,
          maxWidth: columnWidth,
        ) +
        _padding.vertical,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      height: rowHeight(
        context,
        texts: [text],
        columnWidth: constraints.maxWidth,
      ),
      child: Padding(
        padding: _padding,
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: _style.copyWith(
              color: Theme.of(context).extension<DoableColors>()!.muted,
            ),
          ),
        ),
      ),
    ),
  );
}

const _minHeight = 28.0;
const _padding = EdgeInsets.symmetric(vertical: 6);
final _style = DoableType.caption.copyWith(height: 16 / 13);
