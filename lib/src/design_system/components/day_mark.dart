import 'package:flutter/material.dart';

import '../doable_colors.dart';

/// Визуальное состояние отметки дня, подготовленное потребителем.
enum DayMark { none, todo, done }

/// Отметка с постоянным местом под неё, в том числе у пустого дня.
/// Доступное описание состояния входит в название кнопки дня.
final class DayMarkIndicator extends StatelessWidget {
  const DayMarkIndicator({
    super.key,
    required this.mark,
    this.onAccent = false,
  });

  final DayMark mark;

  /// Отметка на акцентной заливке выбранного дня месяца.
  final bool onAccent;

  static const double height = 5;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return SizedBox(
      width: 8,
      height: height,
      child: switch (mark) {
        DayMark.none => null,
        DayMark.todo => Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: onAccent ? colors.onAccent : colors.muted,
              shape: BoxShape.circle,
            ),
          ),
        ),
        DayMark.done => Center(
          child: CustomPaint(
            size: const Size(7, 5),
            painter: _CheckPainter(onAccent ? colors.onAccent : colors.grip),
          ),
        ),
      },
    );
  }
}

final class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Геометрия значка из макета: viewBox 8×6 внутри области 7×5.
    canvas
      ..save()
      ..translate((size.width - size.height * 8 / 6) / 2, 0)
      ..scale(size.height / 6);
    canvas.drawPath(
      Path()
        ..moveTo(1, 3.2)
        ..lineTo(3, 5.2)
        ..lineTo(7, 1),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}
