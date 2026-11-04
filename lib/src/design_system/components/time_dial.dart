import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';
import 'tabs.dart';

/// Половина суток, которую показывает кольцо 12-часового циферблата.
enum TimeDialHalf { am, pm }

/// Подпись половины суток в переключателе: видимый текст и доступное название.
final class TimeDialHalfLabel {
  const TimeDialHalfLabel({required this.text, required this.semanticLabel});

  final String text;
  final String semanticLabel;
}

/// Формат часов циферблата.
sealed class TimeDialClock {
  const TimeDialClock();
}

/// Два кольца двузначных часов: с 00 до 11 снаружи, с 12 до 23 внутри.
final class TimeDialClock24 extends TimeDialClock {
  const TimeDialClock24();
}

/// Одно кольцо с 12 наверху и переключателем половины суток над ним.
///
/// Переключатель меняет только показанную половину суток. Нажатие на час
/// по-прежнему сообщает выбор потребителю, а само переключение выбора не
/// сообщает.
final class TimeDialClock12 extends TimeDialClock {
  const TimeDialClock12({
    required this.initialHalf,
    required this.switchLabel,
    required this.am,
    required this.pm,
  });

  /// Половина суток при первом показе; дальше её хранит циферблат.
  final TimeDialHalf initialHalf;

  /// Доступное название переключателя.
  final String switchLabel;

  final TimeDialHalfLabel am;
  final TimeDialHalfLabel pm;
}

/// Отмеченное значение циферблата.
sealed class TimeDialSelection {
  const TimeDialSelection();
}

/// Отмечен целый час от 0 до 23.
final class TimeDialSelectedHour extends TimeDialSelection {
  const TimeDialSelectedHour(this.hour) : assert(hour >= 0 && hour < 24);

  final int hour;
}

/// Отмечено «Весь день».
final class TimeDialSelectedAllDay extends TimeDialSelection {
  const TimeDialSelectedAllDay();
}

/// Не отмечено ничего: ни час, ни «Весь день». Так выглядит сохранённое время
/// с минутами, которого нет на циферблате.
final class TimeDialNothingSelected extends TimeDialSelection {
  const TimeDialNothingSelected();
}

/// Циферблат листа времени: часы дня по кругу и «Весь день» в центре.
///
/// Циферблат выбирает только целые часы. Нажатие на час или «Весь день»
/// сообщает выбор потребителю; закрытие листа — дело потребителя. Тексты
/// и доступные названия задаёт потребитель, предметных типов у компонента нет.
/// Круг стоит по центру доступной ширины.
final class TimeDial extends StatelessWidget {
  const TimeDial({
    required this.clock,
    required this.selection,
    required this.allDayLabel,
    required this.allDayHint,
    required this.hourLabel,
    required this.onPickHour,
    required this.onAllDay,
    super.key,
  });

  final TimeDialClock clock;
  final TimeDialSelection selection;

  /// Видимый текст центральной пилюли.
  final String allDayLabel;

  /// Доступное название центральной кнопки.
  final String allDayHint;

  /// Доступное название часа от 0 до 23.
  final String Function(int hour) hourLabel;

  final ValueChanged<int> onPickHour;
  final VoidCallback onAllDay;

  @override
  Widget build(BuildContext context) => switch (clock) {
    TimeDialClock24() => _Dial(
      face: _Face.h24,
      selection: selection,
      allDayLabel: allDayLabel,
      allDayHint: allDayHint,
      hourLabel: hourLabel,
      onPickHour: onPickHour,
      onAllDay: onAllDay,
    ),
    final TimeDialClock12 clock12 => _Dial12(
      clock: clock12,
      selection: selection,
      allDayLabel: allDayLabel,
      allDayHint: allDayHint,
      hourLabel: hourLabel,
      onPickHour: onPickHour,
      onAllDay: onAllDay,
    ),
  };
}

final class _Dial12 extends StatefulWidget {
  const _Dial12({
    required this.clock,
    required this.selection,
    required this.allDayLabel,
    required this.allDayHint,
    required this.hourLabel,
    required this.onPickHour,
    required this.onAllDay,
  });

  final TimeDialClock12 clock;
  final TimeDialSelection selection;
  final String allDayLabel;
  final String allDayHint;
  final String Function(int hour) hourLabel;
  final ValueChanged<int> onPickHour;
  final VoidCallback onAllDay;

  @override
  State<_Dial12> createState() => _Dial12State();
}

final class _Dial12State extends State<_Dial12> {
  late var _half = widget.clock.initialHalf;

  @override
  Widget build(BuildContext context) {
    final clock = widget.clock;
    return _Dial(
      face: switch (_half) {
        TimeDialHalf.am => _Face.am,
        TimeDialHalf.pm => _Face.pm,
      },
      period: Tabs<TimeDialHalf>(
        semantics: TabsSemantics.toggle,
        minWidth: _periodMinWidth,
        label: clock.switchLabel,
        value: _half,
        items: [
          TabItem(
            id: TimeDialHalf.am,
            label: clock.am.text,
            semanticLabel: clock.am.semanticLabel,
          ),
          TabItem(
            id: TimeDialHalf.pm,
            label: clock.pm.text,
            semanticLabel: clock.pm.semanticLabel,
          ),
        ],
        onChange: (half) => setState(() => _half = half),
      ),
      selection: widget.selection,
      allDayLabel: widget.allDayLabel,
      allDayHint: widget.allDayHint,
      hourLabel: widget.hourLabel,
      onPickHour: widget.onPickHour,
      onAllDay: widget.onAllDay,
    );
  }
}

/// Кольцо часов: радиус центров часов, первый час и размер цифр.
final class _Ring {
  const _Ring({
    required this.radius,
    required this.firstHour,
    required this.fontSize,
    required this.twelveHour,
  });

  final double radius;
  final int firstHour;
  final double fontSize;

  /// Цифры 12-часового кольца: 12 наверху, затем с 1 до 11.
  final bool twelveHour;

  String text(int position) => twelveHour
      ? '${position == 0 ? 12 : position}'
      : '${firstHour + position}'.padLeft(2, '0');
}

/// Круг циферблата: диаметр и кольца от внешнего к внутреннему.
enum _Face {
  h24(
    size: 316,
    rings: [
      _Ring(radius: 130, firstHour: 0, fontSize: 17, twelveHour: false),
      _Ring(radius: 86, firstHour: 12, fontSize: 15, twelveHour: false),
    ],
  ),
  am(
    size: 264,
    rings: [_Ring(radius: 104, firstHour: 0, fontSize: 17, twelveHour: true)],
  ),
  pm(
    size: 264,
    rings: [_Ring(radius: 104, firstHour: 12, fontSize: 17, twelveHour: true)],
  );

  const _Face({required this.size, required this.rings});

  final double size;
  final List<_Ring> rings;

  /// Ширина свободного места в середине между часами внутреннего кольца.
  double get centerWidth => 2 * (rings.last.radius - DoableMetrics.tapMin / 2);
}

const double _periodMinWidth = 64;
const double _hourCircle = 40;

final class _Dial extends StatelessWidget {
  const _Dial({
    required this.face,
    required this.selection,
    required this.allDayLabel,
    required this.allDayHint,
    required this.hourLabel,
    required this.onPickHour,
    required this.onAllDay,
    this.period,
  });

  final _Face face;
  final Widget? period;
  final TimeDialSelection selection;
  final String allDayLabel;
  final String allDayHint;
  final String Function(int hour) hourLabel;
  final ValueChanged<int> onPickHour;
  final VoidCallback onAllDay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final chosenHour = switch (selection) {
      TimeDialSelectedHour(:final hour) => hour,
      TimeDialSelectedAllDay() || TimeDialNothingSelected() => null,
    };
    final allDayChosen = selection is TimeDialSelectedAllDay;
    final center = face.size / 2;
    return Center(
      heightFactor: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (period case final period?) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DoableMetrics.tapMin,
              ),
              child: Center(child: period),
            ),
            const SizedBox(height: DoableMetrics.space1),
          ],
          Padding(
            padding: const EdgeInsets.only(
              top: 6,
              bottom: DoableMetrics.space1,
            ),
            // Ink нажатий лежит на плоскости круга:
            // https://api.flutter.dev/flutter/material/Ink-class.html
            child: Material(
              color: colors.fill,
              shape: const CircleBorder(),
              child: SizedBox.square(
                dimension: face.size,
                child: Stack(
                  children: [
                    for (final ring in face.rings)
                      for (var position = 0; position < 12; position++)
                        Positioned(
                          left:
                              center +
                              ring.radius * math.sin(position * math.pi / 6) -
                              DoableMetrics.tapMin / 2,
                          top:
                              center -
                              ring.radius * math.cos(position * math.pi / 6) -
                              DoableMetrics.tapMin / 2,
                          child: _HourButton(
                            text: ring.text(position),
                            fontSize: ring.fontSize,
                            label: hourLabel(ring.firstHour + position),
                            chosen: chosenHour == ring.firstHour + position,
                            onTap: () => onPickHour(ring.firstHour + position),
                          ),
                        ),
                    Center(
                      child: _AllDayButton(
                        text: allDayLabel,
                        label: allDayHint,
                        chosen: allDayChosen,
                        maxWidth: face.centerWidth,
                        onTap: onAllDay,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка с областью нажатия не меньше `tap-min` и кольцом фокуса вокруг
/// содержимого, которое рисует [builder].
final class _DialButton extends StatefulWidget {
  const _DialButton({
    required this.label,
    required this.chosen,
    required this.onTap,
    required this.builder,
  });

  final String label;
  final bool chosen;
  final VoidCallback onTap;
  final Widget Function(bool showsFocus) builder;

  @override
  State<_DialButton> createState() => _DialButtonState();
}

final class _DialButtonState extends State<_DialButton> {
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
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    // Одна кнопка с готовым названием вместо подписей внутри:
    // https://api.flutter.dev/flutter/widgets/Semantics-class.html
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      selected: widget.chosen,
      label: widget.label,
      onTap: widget.onTap,
      child: InkWell(
        onTap: widget.onTap,
        customBorder: const StadiumBorder(),
        focusColor: Colors.transparent,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: DoableMetrics.tapMin,
            minHeight: DoableMetrics.tapMin,
          ),
          // Область нажатия равна содержимому, но не меньше `tap-min`.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: CustomPaint(
              foregroundPainter: showsFocus
                  ? _FocusRingPainter(ring: colors.accent, gap: colors.bg)
                  : null,
              child: widget.builder(showsFocus),
            ),
          ),
        ),
      ),
    );
  }
}

final class _HourButton extends StatelessWidget {
  const _HourButton({
    required this.text,
    required this.fontSize,
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final String text;
  final double fontSize;
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return SizedBox.square(
      dimension: DoableMetrics.tapMin,
      child: _DialButton(
        label: label,
        chosen: chosen,
        onTap: onTap,
        builder: (_) => Ink(
          width: _hourCircle,
          height: _hourCircle,
          decoration: BoxDecoration(
            color: chosen ? colors.accent : null,
            shape: BoxShape.circle,
          ),
          // Цифры крупного шрифта сжимаются, чтобы остаться в кружке.
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                style: DoableType.title.copyWith(
                  fontSize: fontSize,
                  fontWeight: chosen ? const FontWeight(650) : FontWeight.w500,
                  letterSpacing: 0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: chosen ? colors.onAccent : colors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _AllDayButton extends StatelessWidget {
  const _AllDayButton({
    required this.text,
    required this.label,
    required this.chosen,
    required this.maxWidth,
    required this.onTap,
  });

  final String text;
  final String label;
  final bool chosen;

  /// Свободное место между часами: пилюля не ложится на них.
  final double maxWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;
    return _DialButton(
      label: label,
      chosen: chosen,
      onTap: onTap,
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: DoableMetrics.controlHeightSm,
          maxWidth: maxWidth,
        ),
        child: Ink(
          decoration: BoxDecoration(
            color: chosen ? colors.accent : colors.raised,
            border: chosen ? null : Border.all(color: colors.hairline),
            borderRadius: BorderRadius.circular(DoableMetrics.radiusFull),
            boxShadow: chosen ? null : shadows.sm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DoableMetrics.space4,
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              // Крупный шрифт сжимает подпись, чтобы пилюля осталась
              // в центре.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  style: DoableType.section.copyWith(
                    color: chosen ? colors.onAccent : colors.ink,
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

/// `focus-ring` дизайн-системы вокруг скруглённой до круга области: зазор `bg`
/// в 2, затем `accent` в 2.
final class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({required this.ring, required this.gap});

  final Color ring;
  final Color gap;

  static const double _width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final area = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide / 2),
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
      ring != oldDelegate.ring || gap != oldDelegate.gap;
}
