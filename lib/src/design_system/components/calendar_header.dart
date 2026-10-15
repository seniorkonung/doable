import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Шапка периода с готовым заголовком и командами соседних периодов.
///
/// Отсутствие обработчика делает соответствующую стрелку недоступной.
/// Без [titleAction] заголовок остаётся текстом. Названия команд и состояние
/// выбора задаёт потребитель.
final class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.title,
    required this.previousLabel,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
    this.titleAction,
  });

  final String title;
  final String previousLabel;
  final String nextLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ({String semanticLabel, bool isExpanded, VoidCallback onTap})?
  titleAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    const radius = BorderRadius.all(Radius.circular(DoableMetrics.radiusSm));
    final action = titleAction;
    final titleBox = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Ink(
        decoration: BoxDecoration(
          border: Border.all(
            color: action?.isExpanded == true
                ? colors.hairline
                : Colors.transparent,
          ),
          borderRadius: radius,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: DoableType.title.copyWith(
                    color: colors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: DoableMetrics.space1),
              CustomPaint(
                size: const Size.square(16),
                painter: _ChevronPainter(
                  action?.isExpanded == true ? _Chevron.up : _Chevron.down,
                  colors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        _PeriodArrow(
          direction: _Chevron.previous,
          label: previousLabel,
          onPressed: onPrevious,
        ),
        Expanded(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: action == null
                  ? titleBox
                  // Одна команда с отдельным состоянием раскрытия:
                  // https://api.flutter.dev/flutter/semantics/SemanticsProperties/expanded.html
                  : Semantics(
                      container: true,
                      excludeSemantics: true,
                      button: true,
                      expanded: action.isExpanded,
                      label: action.semanticLabel,
                      value: title,
                      onTap: action.onTap,
                      child: InkWell(
                        borderRadius: radius,
                        onTap: action.onTap,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: DoableMetrics.tapMin,
                          ),
                          child: titleBox,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        _PeriodArrow(
          direction: _Chevron.next,
          label: nextLabel,
          onPressed: onNext,
        ),
      ],
    );
  }
}

final class _PeriodArrow extends StatelessWidget {
  const _PeriodArrow({
    required this.direction,
    required this.label,
    required this.onPressed,
  });

  final _Chevron direction;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    // IconButton сохраняет клавиатурное управление и недоступность при null:
    // https://api.flutter.dev/flutter/material/IconButton-class.html
    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(DoableMetrics.tapMin),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: colors.muted,
        disabledForegroundColor: colors.grip,
      ),
      icon: Semantics(
        label: label,
        child: CustomPaint(
          size: const Size.square(20),
          painter: _ChevronPainter(
            direction,
            onPressed == null ? colors.grip : colors.muted,
          ),
        ),
      ),
    );
  }
}

enum _Chevron { previous, next, down, up }

final class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.direction, this.color);

  final _Chevron direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = switch (direction) {
      _Chevron.previous => const [
        Offset(14.5, 6),
        Offset(8.5, 12),
        Offset(14.5, 18),
      ],
      _Chevron.next => const [
        Offset(9.5, 6),
        Offset(15.5, 12),
        Offset(9.5, 18),
      ],
      _Chevron.down => const [
        Offset(6, 9.5),
        Offset(12, 15.5),
        Offset(18, 9.5),
      ],
      _Chevron.up => const [Offset(6, 14.5), Offset(12, 8.5), Offset(18, 14.5)],
    };
    // Координаты и толщина штриха из значков макета с viewBox 24×24.
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(
        Path()..addPolygon(points, false),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = switch (direction) {
            _Chevron.down || _Chevron.up => 2,
            _ => 1.75,
          }
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      direction != oldDelegate.direction || color != oldDelegate.color;
}
