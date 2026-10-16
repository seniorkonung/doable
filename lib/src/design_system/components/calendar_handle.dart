import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';

/// Ручка календаря; состоянием раскрытия и названием управляет потребитель.
final class CalendarHandle extends StatefulWidget {
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
  State<CalendarHandle> createState() => _CalendarHandleState();
}

final class _CalendarHandleState extends State<CalendarHandle> {
  bool _showFocusHighlight = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    // Фокус и штатные команды клавиатуры не зависят от эффекта чернил:
    // https://api.flutter.dev/flutter/widgets/FocusableActionDetector-class.html
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) =>
          setState(() => _showFocusHighlight = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      // Состояние раскрытия доступно отдельно от названия команды:
      // https://api.flutter.dev/flutter/semantics/SemanticsProperties/expanded.html
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        expanded: widget.isExpanded,
        label: widget.semanticLabel,
        onTap: widget.onTap,
        child: GestureDetector(
          // Вся полоса принимает нажатие, включая пустое место у краёв:
          // https://api.flutter.dev/flutter/widgets/GestureDetector/behavior.html
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: double.infinity,
            height: 36,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: _showFocusHighlight
                      ? Border.all(color: colors.ink, width: 2)
                      : null,
                  borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(DoableMetrics.space2),
                  child: CustomPaint(
                    size: const Size(28, 10),
                    painter: _HandlePainter(widget.isExpanded, colors.grip),
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
