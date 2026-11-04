import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';

/// Сохранённый путь дневного выбора малой меткой: ромб — исходное намерение,
/// кольцо — каждое промежуточное намерение, круг — действие.
///
/// [reasons] — число шагов пути от исходного намерения до действия. Один шаг
/// даёт ромб, линию и круг, каждый следующий добавляет кольцо и линию. До
/// семи шагов цепочка рисуется целиком, от восьми у неё постоянная длина:
/// по три кольца остаются у концов, а середину занимает многоточие.
///
/// Концы цвета приоритета, линии и кольца — он же пополам с `grip`. У
/// выполненного выбора ([off]) вся цепочка `grip`. Узла экранного диктора
/// нет: число шагов называет строка вокруг метки.
final class ReasonChain extends StatelessWidget {
  const ReasonChain({
    required this.reasons,
    required this.priority,
    this.off = false,
    super.key,
  }) : assert(reasons >= 1);

  final int reasons;
  final DoablePriority priority;

  /// Выбор выполнен: все части цепочки `grip`.
  final bool off;

  static const double _height = 11;
  static const int _fullReasons = 7;
  static const int _endRings = 3;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final endColor = off ? colors.grip : priority.color(colors);
    final linkColor = off
        ? colors.grip
        : Color.lerp(endColor, colors.grip, .5)!;

    final marks = [
      _Mark.source,
      if (reasons <= _fullReasons)
        for (var step = 1; step < reasons; step++) _Mark.ring
      else ...[
        for (var ring = 0; ring < _endRings; ring++) _Mark.ring,
        _Mark.ellipsis,
        for (var ring = 0; ring < _endRings; ring++) _Mark.ring,
      ],
      _Mark.action,
    ];

    return SizedBox(
      height: _height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, mark) in marks.indexed) ...[
            // Многоточие отделяют от соседей поля, а не линии.
            if (index > 0 &&
                mark != _Mark.ellipsis &&
                marks[index - 1] != _Mark.ellipsis)
              _Line(
                color: linkColor,
                length: marks[index - 1] == _Mark.source
                    ? _Line.fromSource
                    : _Line.between,
              ),
            switch (mark) {
              _Mark.source => _Source(color: endColor),
              _Mark.ring => _Ring(color: linkColor),
              _Mark.ellipsis => _Ellipsis(color: linkColor),
              _Mark.action => _Action(color: endColor),
            },
          ],
        ],
      ),
    );
  }
}

enum _Mark { source, ring, ellipsis, action }

final class _Source extends StatelessWidget {
  const _Source({required this.color});

  final Color color;

  static const double _side = 7.5;
  static const double _inset = 2;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: _inset),
    child: Transform.rotate(
      angle: math.pi / 4,
      child: SizedBox.square(
        dimension: _side,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(Radius.circular(1)),
          ),
        ),
      ),
    ),
  );
}

final class _Line extends StatelessWidget {
  const _Line({required this.color, required this.length});

  final Color color;
  final double length;

  /// Первая линия начинается под углом ромба.
  static const double fromSource = 11;
  static const double between = 10;
  static const double _thickness = 1.5;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: length,
    height: _thickness,
    child: ColoredBox(color: color),
  );
}

final class _Ring extends StatelessWidget {
  const _Ring({required this.color});

  final Color color;

  static const double _diameter = 7;
  static const double _borderWidth = 1.5;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _diameter,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: _borderWidth),
      ),
    ),
  );
}

final class _Action extends StatelessWidget {
  const _Action({required this.color});

  final Color color;

  static const double _diameter = 9;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _diameter,
    child: DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}

/// Три сплошные точки; поля по бокам занимают место линий.
final class _Ellipsis extends StatelessWidget {
  const _Ellipsis({required this.color});

  final Color color;

  static const double _dot = 3;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space1),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: _gap,
      children: [
        for (var dot = 0; dot < 3; dot++)
          SizedBox.square(
            dimension: _dot,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
      ],
    ),
  );
}
