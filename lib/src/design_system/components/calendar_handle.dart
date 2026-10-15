import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';

/// Ручка календаря; состоянием раскрытия и названием управляет потребитель.
final class CalendarHandle extends StatelessWidget {
  const CalendarHandle({
    super.key,
    required this.isExpanded,
    required this.semanticLabel,
    required this.onTap,
  });

  final bool isExpanded;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    // Состояние раскрытия доступно отдельно от названия команды:
    // https://api.flutter.dev/flutter/semantics/SemanticsProperties/expanded.html
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      expanded: isExpanded,
      label: semanticLabel,
      onTap: onTap,
      // Material обеспечивает отклик InkWell по всей полосе:
      // https://api.flutter.dev/flutter/material/InkWell-class.html
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: double.infinity,
            height: DoableMetrics.tapMin,
            child: Center(
              child: CustomPaint(
                size: const Size(28, 10),
                painter: _HandlePainter(isExpanded, colors.grip),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.isExpanded, this.color);

  final bool isExpanded;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final edgeY = isExpanded ? 7.0 : 3.0;
    final middleY = isExpanded ? 3.0 : 7.0;
    canvas.drawPath(
      Path()
        ..moveTo(3, edgeY)
        ..lineTo(14, middleY)
        ..lineTo(25, edgeY),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HandlePainter oldDelegate) =>
      isExpanded != oldDelegate.isExpanded || color != oldDelegate.color;
}
