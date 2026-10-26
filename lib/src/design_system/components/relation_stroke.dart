import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';

/// Вид связи, который передаёт линия: узор несёт вид, а цвет выбранного
/// вида задаёт потребитель.
sealed class RelationStrokeKind {
  const RelationStrokeKind();

  /// Нужно — сплошная линия `stroke-need`.
  const factory RelationStrokeKind.need(Color color) = RelationStrokeNeed;

  /// Можно — пунктирная линия `stroke-can`.
  const factory RelationStrokeKind.can(Color color) = RelationStrokeCan;

  /// Вид ещё не выбран — сплошная линия 2 цвета `hairline` темы.
  const factory RelationStrokeKind.undetermined() = RelationStrokeUndetermined;
}

final class RelationStrokeNeed extends RelationStrokeKind {
  const RelationStrokeNeed(this.color);

  final Color color;
}

final class RelationStrokeCan extends RelationStrokeKind {
  const RelationStrokeCan(this.color);

  final Color color;
}

final class RelationStrokeUndetermined extends RelationStrokeKind {
  const RelationStrokeUndetermined();
}

/// Направление линии: вертикальная — на рейке пути, горизонтальная —
/// у отметки вида рядом со словом.
enum RelationStrokeAxis {
  vertical(dash: DoableMetrics.strokeDash, gap: DoableMetrics.strokeGap),

  /// Короткий пунктир отметки вида по макету.
  horizontal(dash: 3, gap: 3);

  const RelationStrokeAxis({required this.dash, required this.gap});

  final double dash;
  final double gap;
}

/// Линия связи по оси. Вертикальная занимает высоту родителя и ширину
/// своей толщины; горизонтальная — ширину родителя и проходит по середине
/// его высоты. Узла экранного диктора нет: вид называет слово рядом.
final class RelationStroke extends StatelessWidget {
  const RelationStroke({required this.kind, required this.axis, super.key});

  final RelationStrokeKind kind;
  final RelationStrokeAxis axis;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final (color, width, dashed) = switch (kind) {
      RelationStrokeNeed(:final color) => (
        color,
        DoableMetrics.strokeNeed,
        false,
      ),
      RelationStrokeCan(:final color) => (color, DoableMetrics.strokeCan, true),
      RelationStrokeUndetermined() => (colors.hairline, 2.0, false),
    };
    return CustomPaint(
      size: switch (axis) {
        RelationStrokeAxis.vertical => Size(width, 0),
        RelationStrokeAxis.horizontal => Size(0, width),
      },
      painter: _RelationStrokePainter(
        color: color,
        width: width,
        dashed: dashed,
        axis: axis,
      ),
    );
  }
}

/// Отметка вида 15 × 2 перед словом вида: повторяет линию связи.
final class RelationKindMark extends StatelessWidget {
  const RelationKindMark({required this.kind, super.key});

  final RelationStrokeKind kind;

  static const Size size = Size(15, 2);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: RelationStroke(kind: kind, axis: RelationStrokeAxis.horizontal),
  );
}

/// Пунктир по контурам [source]: штрихи длины [dash] через промежутки
/// [gap]; каждый контур начинается со штриха, последний штрих может быть
/// короче.
Path dashPath(Path source, {required double dash, required double gap}) {
  assert(dash > 0 && gap >= 0);
  final dashed = Path();
  for (final contour in source.computeMetrics()) {
    for (var start = 0.0; start < contour.length; start += dash + gap) {
      dashed.addPath(contour.extractPath(start, start + dash), Offset.zero);
    }
  }
  return dashed;
}

final class _RelationStrokePainter extends CustomPainter {
  const _RelationStrokePainter({
    required this.color,
    required this.width,
    required this.dashed,
    required this.axis,
  });

  final Color color;
  final double width;
  final bool dashed;
  final RelationStrokeAxis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final (start, end) = switch (axis) {
      RelationStrokeAxis.vertical => (
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
      ),
      RelationStrokeAxis.horizontal => (
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
      ),
    };
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (!dashed) {
      canvas.drawLine(start, end, paint);
      return;
    }
    canvas.drawPath(
      dashPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy),
        dash: axis.dash,
        gap: axis.gap,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RelationStrokePainter oldDelegate) =>
      color != oldDelegate.color ||
      width != oldDelegate.width ||
      dashed != oldDelegate.dashed ||
      axis != oldDelegate.axis;
}
