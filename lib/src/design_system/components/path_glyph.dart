import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'relation_stroke.dart';

/// Форма глифа пути: ромб — исходное намерение связи, кольцо — связанное.
enum PathGlyphShape { diamond, ring }

/// Контур глифа: сплошной — место заполнено, пунктирный — ещё не выбрано.
enum PathGlyphOutline { solid, dashed }

/// Глиф пути заданной формы, контура, размера и цвета. Рисуется на сетке
/// 14 макета и масштабируется под [size]. Узла экранного диктора нет:
/// роль места называют слова рядом.
final class PathGlyph extends StatelessWidget {
  const PathGlyph({
    required this.shape,
    required this.outline,
    required this.size,
    required this.color,
    super.key,
  });

  final PathGlyphShape shape;
  final PathGlyphOutline outline;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _PathGlyphPainter(shape: shape, outline: outline, color: color),
  );
}

final class _PathGlyphPainter extends CustomPainter {
  const _PathGlyphPainter({
    required this.shape,
    required this.outline,
    required this.color,
  });

  final PathGlyphShape shape;
  final PathGlyphOutline outline;
  final Color color;

  static const double _grid = 14;
  static const Offset _center = Offset(_grid / 2, _grid / 2);
  static const double _outlineWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _grid;
    final toSize = Matrix4.diagonal3Values(scale, scale, 1).storage;
    final paint = Paint()..color = color;
    switch ((shape, outline)) {
      case (PathGlyphShape.diamond, PathGlyphOutline.dashed):
        final diamond = Path()
          ..moveTo(7, 1.25)
          ..lineTo(12.75, 7)
          ..lineTo(7, 12.75)
          ..lineTo(1.25, 7)
          ..close();
        canvas.drawPath(
          dashPath(
            diamond.transform(toSize),
            dash: 2.4 * scale,
            gap: 2 * scale,
          ),
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = _outlineWidth * scale
            ..strokeJoin = StrokeJoin.round,
        );
      case (PathGlyphShape.ring, PathGlyphOutline.dashed):
        // Окружность — многоугольник из 72 сторон: Skia измеряет конические
        // дуги с погрешностью в несколько процентов, и штрихи вышли бы
        // неровными, а отклонение сторон от окружности меньше 0,01.
        final ring = Path()
          ..addPolygon([
            for (var side = 0; side < 72; side++)
              _center + Offset.fromDirection(side * 2 * math.pi / 72, 5.25),
          ], true);
        canvas.drawPath(
          dashPath(ring.transform(toSize), dash: 2.2 * scale, gap: 2.2 * scale),
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = _outlineWidth * scale,
        );
      case (PathGlyphShape.diamond, PathGlyphOutline.solid):
        // Квадрат 9,5 со скруглением 1,5, повёрнутый на 45°.
        final square = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: _center, width: 9.5, height: 9.5),
              const Radius.circular(1.5),
            ),
          );
        final rotation = Matrix4.identity()
          ..translateByDouble(_center.dx, _center.dy, 0, 1)
          ..rotateZ(math.pi / 4)
          ..translateByDouble(-_center.dx, -_center.dy, 0, 1);
        canvas.drawPath(
          square.transform(rotation.storage).transform(toSize),
          paint..style = PaintingStyle.fill,
        );
      case (PathGlyphShape.ring, PathGlyphOutline.solid):
        // Кольцо 10 с обводкой 1,5 внутрь границы.
        canvas.drawCircle(
          _center * scale,
          (5 - _outlineWidth / 2) * scale,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = _outlineWidth * scale,
        );
    }
  }

  @override
  bool shouldRepaint(_PathGlyphPainter oldDelegate) =>
      shape != oldDelegate.shape ||
      outline != oldDelegate.outline ||
      color != oldDelegate.color;
}
