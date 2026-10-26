import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import '../text_metrics.dart';

/// Шаг потока; тексты потребитель передаёт готовыми.
final class FlowStep {
  const FlowStep({required this.title, this.note});

  final String title;

  /// Необязательное пояснение под названием.
  final String? note;
}

/// Пронумерованные шаги потока сверху вниз с отметкой текущего шага.
final class FlowSteps extends StatelessWidget {
  const FlowSteps({
    required this.steps,
    required this.current,
    required this.currentMark,
    super.key,
  });

  final List<FlowStep> steps;

  /// Индекс текущего шага в [steps].
  final int current;

  /// Отметка под названием текущего шага, например «Вы здесь».
  final String currentMark;

  @override
  Widget build(BuildContext context) {
    assert(current >= 0 && current < steps.length);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, step) in steps.indexed)
          _FlowStepRow(
            number: '${index + 1}',
            step: step,
            mark: index == current ? currentMark : null,
            isLast: index == steps.length - 1,
          ),
      ],
    );
  }
}

const _circleSize = 28.0;

/// Поля круга 28 вокруг строки `label` высотой 18.
const _circlePadding = 10.0;
const _lineWidth = 2.0;
const _lineMinHeight = 8.0;
const _textGap = 2.0;

TextStyle _numberStyle(Color color) => DoableType.label.copyWith(
  color: color,
  fontFeatures: const [FontFeature.tabularFigures()],
);

final class _FlowStepRow extends StatelessWidget {
  const _FlowStepRow({
    required this.number,
    required this.step,
    required this.mark,
    required this.isLast,
  });

  final String number;
  final FlowStep step;

  /// Отметка есть только у текущего шага.
  final String? mark;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final isCurrent = mark != null;
    final titleStyle =
        (isCurrent
                ? DoableType.section
                : DoableType.row.copyWith(letterSpacing: -0.15))
            .copyWith(color: colors.ink);
    final numberStyle = _numberStyle(
      isCurrent ? colors.onAccent : colors.muted,
    );

    // При крупном тексте круг растёт вместе с номером, сохраняя поля макета,
    // а первая строка названия остаётся по центру круга.
    final numberHeight = tallestTextHeight(
      context,
      texts: [number],
      style: numberStyle,
      maxWidth: double.infinity,
    );
    final circleSize = math.max(_circleSize, numberHeight + _circlePadding);
    final titleLineHeight = tallestTextHeight(
      context,
      texts: const ['0'],
      style: titleStyle,
      maxWidth: double.infinity,
    );
    final circleTop = math.max(0.0, (titleLineHeight - circleSize) / 2);
    final titleTop = math.max(0.0, (circleSize - titleLineHeight) / 2);

    // Шаг читается одним узлом: номер, название, отметка и пояснение.
    return MergeSemantics(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DoableMetrics.space3,
          children: [
            SizedBox(
              width: circleSize,
              child: Padding(
                padding: EdgeInsets.only(top: circleTop),
                child: Column(
                  children: [
                    Container(
                      width: circleSize,
                      height: circleSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCurrent ? colors.accent : null,
                        border: isCurrent
                            ? null
                            : Border.all(color: colors.hairline, width: 1.5),
                      ),
                      child: Text(number, style: numberStyle),
                    ),
                    if (!isLast)
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: _lineMinHeight,
                          ),
                          child: SizedBox(
                            width: _lineWidth,
                            child: ColoredBox(color: colors.hairline),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  top: titleTop,
                  bottom: DoableMetrics.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: _textGap,
                  children: [
                    Text(step.title, style: titleStyle),
                    if (mark case final mark?)
                      Text(
                        mark,
                        style: DoableType.label.copyWith(color: colors.accent),
                      ),
                    if (step.note case final note?)
                      Text(
                        note,
                        style: DoableType.hint.copyWith(color: colors.muted),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
