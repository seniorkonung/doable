import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';

/// Выбор приоритета четырьмя пилюлями P1–P4: кольцо пилюли цвета приоритета,
/// выбранная лежит на `fill`. Выбрана всегда одна пилюля: нажатие на выбранную
/// ничего не делает, поэтому приоритет нельзя снять.
///
/// Цвет приоритета не заливает пилюлю и не красит подпись. Пилюли, которым не
/// хватает ширины, например при крупном шрифте, переносятся и прижаты к концу
/// строки. Видимые подписи пилюль, название группы и доступное название каждой
/// пилюли задаёт потребитель.
final class PriorityPicker extends StatelessWidget {
  const PriorityPicker({
    required this.value,
    required this.onChange,
    required this.label,
    required this.name,
    required this.itemLabel,
    super.key,
  });

  final DoablePriority value;

  /// Без обработчика пилюли недоступны: экранный диктор объявляет
  /// недоступность их состоянием.
  final ValueChanged<DoablePriority>? onChange;

  /// Доступное название группы.
  final String label;

  /// Видимая подпись пилюли.
  final String Function(DoablePriority priority) name;

  /// Доступное название пилюли: оно называет порядок приоритетов, например
  /// «Приоритет P1, высший». Выбор диктору объявляет состояние `selected`,
  /// поэтому название от него не зависит.
  final String Function(DoablePriority priority) itemLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: label,
    child: Wrap(
      alignment: WrapAlignment.end,
      children: [
        for (final priority in DoablePriority.values)
          _Pill(
            priority: priority,
            chosen: priority == value,
            name: name(priority),
            semanticLabel: itemLabel(priority),
            onChange: onChange,
          ),
      ],
    ),
  );
}

final class _Pill extends StatefulWidget {
  const _Pill({
    required this.priority,
    required this.chosen,
    required this.name,
    required this.semanticLabel,
    required this.onChange,
  });

  final DoablePriority priority;
  final bool chosen;
  final String name;
  final String semanticLabel;
  final ValueChanged<DoablePriority>? onChange;

  @override
  State<_Pill> createState() => _PillState();
}

final class _PillState extends State<_Pill> {
  var _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_handleHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_handleHighlightMode);
    super.dispose();
  }

  // Кольцо фокуса нужно только при управлении с клавиатуры.
  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final chosen = widget.chosen;
    final onChange = widget.onChange;
    final priorityColor = widget.priority.color(colors);
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onChange != null,
        selected: chosen,
        inMutuallyExclusiveGroup: true,
        label: widget.semanticLabel,
        // Отклик нажатия рисуется на собственном Material пилюли, поэтому
        // область прокрутки обрезает его вместе с пилюлей:
        // https://api.flutter.dev/flutter/material/InkWell-class.html
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: switch (onChange) {
              null => null,
              final onChange => () {
                if (!chosen) onChange(widget.priority);
              },
            },
            customBorder: const StadiumBorder(),
            focusColor: Colors.transparent,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DoableMetrics.tapMin,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  // Плоскость пилюли прозрачна, поэтому тень `focus-ring` легла
                  // бы на неё сплошным слоем: кольцо рисуется только снаружи.
                  child: CustomPaint(
                    foregroundPainter: showsFocus
                        ? _FocusRingPainter(ring: colors.accent, gap: colors.bg)
                        : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: DoableMetrics.controlHeightSm,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: chosen ? colors.fill : null,
                          borderRadius: BorderRadius.circular(
                            DoableMetrics.radiusFull,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 7,
                            end: DoableMetrics.space2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: DoableMetrics.space1,
                            children: [
                              _Ring(
                                color: priorityColor,
                                tinted: widget.priority != DoablePriority.p4,
                              ),
                              Text(
                                widget.name,
                                style:
                                    (chosen
                                            ? DoableType.label
                                            : DoableType.caption)
                                        .copyWith(
                                          color: chosen
                                              ? colors.ink
                                              : colors.muted,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                              ),
                            ],
                          ),
                        ),
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

/// Кольцо 16 с рамкой 2 цвета приоритета; P1–P3 подкрашены им на 12%, P4 пусто.
final class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.tinted});

  final Color color;
  final bool tinted;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: tinted ? color.withValues(alpha: .12) : null,
      border: Border.all(color: color, width: 2),
    ),
    child: const SizedBox.square(dimension: 16),
  );
}

/// `focus-ring` дизайн-системы вокруг пилюли: зазор `bg` в 2, затем `accent`
/// в 2.
final class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({required this.ring, required this.gap});

  final Color ring;
  final Color gap;

  static const double _width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final pill = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas
      ..drawRRect(
        pill.inflate(_width / 2),
        Paint()
          ..color = gap
          ..style = PaintingStyle.stroke
          ..strokeWidth = _width,
      )
      ..drawRRect(
        pill.inflate(_width * 1.5),
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = _width,
      );
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) =>
      ring != oldDelegate.ring || gap != oldDelegate.gap;
}
