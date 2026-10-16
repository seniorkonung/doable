import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';

/// Ручка календаря; состоянием раскрытия и названием управляет потребитель.
final class CalendarHandle extends StatefulWidget {
  const CalendarHandle({
    super.key,
    required this.isExpanded,
    required this.expansionProgress,
    required this.semanticLabel,
    required this.onTap,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
  }) : assert(expansionProgress >= 0 && expansionProgress <= 1);

  final bool isExpanded;
  final double expansionProgress;
  final String semanticLabel;
  final VoidCallback onTap;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;

  @override
  State<CalendarHandle> createState() => _CalendarHandleState();
}

final class _CalendarHandleState extends State<CalendarHandle> {
  bool _showFocusHighlight = false;
  bool _isPointerCanceled = false;

  void _endDrag(DragEndDetails details) {
    // Принятый жест Flutter завершает через onEnd даже при PointerCancelEvent:
    // https://api.flutter.dev/flutter/gestures/DragGestureRecognizer/didStopTrackingLastPointer.html
    if (_isPointerCanceled) {
      widget.onVerticalDragCancel?.call();
    } else {
      widget.onVerticalDragEnd?.call(details);
    }
  }

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
        child: Listener(
          onPointerDown: (_) => _isPointerCanceled = false,
          onPointerCancel: (_) => _isPointerCanceled = true,
          child: GestureDetector(
            // Вся полоса принимает нажатие, включая пустое место у краёв:
            // https://api.flutter.dev/flutter/widgets/GestureDetector/behavior.html
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            // Нажатие и перетягивание конкурируют в одной арене жестов:
            // https://api.flutter.dev/flutter/widgets/GestureDetector-class.html
            onVerticalDragStart: widget.onVerticalDragStart,
            onVerticalDragUpdate: widget.onVerticalDragUpdate,
            onVerticalDragEnd:
                widget.onVerticalDragEnd != null ||
                    widget.onVerticalDragCancel != null
                ? _endDrag
                : null,
            onVerticalDragCancel: widget.onVerticalDragCancel,
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
                      painter: _HandlePainter(
                        widget.expansionProgress,
                        colors.grip,
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

final class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final edgeY = 3 + 4 * progress;
    final middleY = 7 - 4 * progress;
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
      progress != oldDelegate.progress || color != oldDelegate.color;
}
