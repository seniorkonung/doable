import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';
import 'choice_check.dart';
import 'reason_chain.dart';

/// Один дневной выбор в списке: флажок, исходное намерение, цепочка шагов
/// пути, выбранное действие и описание.
///
/// Строка — две кнопки рядом. Флажок шириной 52 на всю высоту строки
/// вызывает [onToggle], остальная строка — [onOpen]. Нажатие на флажок
/// выбор не открывает. Без [onToggle] флажок выключен, а раскладка та же.
/// Тексты, в том числе готовые доступные названия обеих кнопок, и ключи
/// кнопок задаёт потребитель; даты и времени строка не показывает.
///
/// Исходное намерение занимает одну строку и обрезается многоточием,
/// действие переносится, описание не длиннее двух строк. У выполненного
/// выбора цепочка серая, а действие `muted` и зачёркнуто.
final class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    required this.goal,
    required this.action,
    required this.priority,
    required this.reasons,
    required this.checkLabel,
    required this.label,
    required this.onOpen,
    this.note,
    this.done = false,
    this.onToggle,
    this.checkKey,
    this.openKey,
    super.key,
  }) : assert(note != '');

  /// Исходное намерение пути.
  final String goal;

  /// Выбранное действие.
  final String action;

  /// Описание выбора; без него последней строки нет.
  final String? note;

  /// Приоритет выбора: цвет кольца флажка и концов цепочки.
  final DoablePriority priority;

  /// Число шагов сохранённого пути от исходного намерения до действия, не
  /// меньше 1.
  final int reasons;

  /// Выбор выполнен.
  final bool done;

  /// Доступное название флажка.
  final String checkLabel;

  /// Доступное название кнопки, открывающей выбор.
  final String label;

  /// Переключает выполнение; без него флажок выключен.
  final VoidCallback? onToggle;

  final VoidCallback onOpen;

  /// Ключ кнопки флажка.
  final Key? checkKey;

  /// Ключ кнопки, открывающей выбор.
  final Key? openKey;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(DoableMetrics.radiusLg),
  );
  static const double _checkWidth = 52;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final note = this.note;

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.fill, borderRadius: _radius),
      // Отклик нажатия рисуется на плоскости строки, а не под ней:
      // https://api.flutter.dev/flutter/material/InkWell-class.html
      child: Material(
        type: MaterialType.transparency,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Button(
                key: checkKey,
                label: checkLabel,
                checked: done,
                onTap: onToggle,
                builder: (showsFocus) => SizedBox(
                  width: _checkWidth,
                  child: Padding(
                    // Кольцо по центру остальных 48 справа от поля в 4.
                    padding: const EdgeInsetsDirectional.only(
                      start: DoableMetrics.space1,
                    ),
                    child: Center(
                      child: _FocusRing(
                        radius: DoableMetrics.checkSize / 2,
                        shown: showsFocus,
                        child: ChoiceCheck(priority: priority, done: done),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _Button(
                  key: openKey,
                  label: label,
                  onTap: onOpen,
                  builder: (showsFocus) => _FocusRing(
                    radius: DoableMetrics.radiusLg,
                    shown: showsFocus,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        0,
                        9,
                        DoableMetrics.space4,
                        10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 2,
                        children: [
                          Text(
                            goal,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DoableType.caption.copyWith(
                              color: colors.muted,
                            ),
                          ),
                          // Цепочка отстоит от действия на 5: 2 между
                          // элементами и 3 в запас под цепочкой.
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: ReasonChain(
                              reasons: reasons,
                              priority: priority,
                              off: done,
                            ),
                          ),
                          Text(
                            action,
                            style: DoableType.action.copyWith(
                              color: done ? colors.muted : colors.ink,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (note != null)
                            Text(
                              note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: DoableType.note.copyWith(
                                color: colors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка строки: одна область нажатия с названием для диктора. Кольцо
/// фокуса клавиатуры рисует содержимое по признаку, который получает от
/// кнопки.
final class _Button extends StatefulWidget {
  const _Button({
    required this.label,
    required this.onTap,
    required this.builder,
    this.checked,
    super.key,
  });

  final String label;

  /// Состояние флажка; у кнопки, не являющейся флажком, его нет.
  final bool? checked;

  /// Без обработчика кнопка не принимает нажатие, а диктор объявляет её
  /// недоступной.
  final VoidCallback? onTap;

  final Widget Function(bool showsFocus) builder;

  @override
  State<_Button> createState() => _ButtonState();
}

final class _ButtonState extends State<_Button> {
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
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    return MergeSemantics(
      child: Semantics(
        label: widget.label,
        button: true,
        checked: widget.checked,
        enabled: widget.onTap != null,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: ChoiceRow._radius,
          focusColor: Colors.transparent,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: ExcludeSemantics(child: widget.builder(showsFocus)),
        ),
      ),
    );
  }
}

/// `focus-ring` дизайн-системы вокруг [child]: зазор `bg` в 2, затем `accent`
/// в 2. Кольцо лежит снаружи содержимого: тень легла бы сплошным слоем на
/// плоскость строки.
final class _FocusRing extends StatelessWidget {
  const _FocusRing({
    required this.radius,
    required this.shown,
    required this.child,
  });

  final double radius;
  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return CustomPaint(
      foregroundPainter: shown
          ? _FocusRingPainter(
              ring: colors.accent,
              gap: colors.bg,
              radius: radius,
            )
          : null,
      child: child,
    );
  }
}

final class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({
    required this.ring,
    required this.gap,
    required this.radius,
  });

  final Color ring;
  final Color gap;
  final double radius;

  static const double _width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final area = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas
      ..drawRRect(
        area.inflate(_width / 2),
        Paint()
          ..color = gap
          ..style = PaintingStyle.stroke
          ..strokeWidth = _width,
      )
      ..drawRRect(
        area.inflate(_width * 1.5),
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = _width,
      );
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) =>
      ring != oldDelegate.ring ||
      gap != oldDelegate.gap ||
      radius != oldDelegate.radius;
}
