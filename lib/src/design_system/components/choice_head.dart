import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';
import 'badge.dart';
import 'choice_check.dart';
import 'edge_overhang.dart';

/// Кнопка параметров шапки выбора: её нет, она доступна или временно
/// недоступна.
///
/// Временно недоступная кнопка остаётся на месте, поэтому раскладка шапки не
/// сдвигается. Название есть только у вариантов с кнопкой.
sealed class ChoiceHeadOptions {
  const ChoiceHeadOptions._();

  /// Кнопки нет, например над редактором описания.
  const factory ChoiceHeadOptions.none() = ChoiceHeadOptionsNone;

  /// Кнопка открывает параметры выбора.
  const factory ChoiceHeadOptions.available({
    required String label,
    required VoidCallback onOpen,
    Key? buttonKey,
  }) = ChoiceHeadOptionsAvailable;

  /// Кнопка на месте, но не принимает нажатие: диктор объявляет её
  /// недоступной.
  const factory ChoiceHeadOptions.unavailable({
    required String label,
    Key? buttonKey,
  }) = ChoiceHeadOptionsUnavailable;
}

final class ChoiceHeadOptionsNone extends ChoiceHeadOptions {
  const ChoiceHeadOptionsNone() : super._();
}

final class ChoiceHeadOptionsAvailable extends ChoiceHeadOptions {
  const ChoiceHeadOptionsAvailable({
    required this.label,
    required this.onOpen,
    this.buttonKey,
  }) : super._();

  /// Доступное название кнопки.
  final String label;

  final VoidCallback onOpen;

  /// Ключ кнопки.
  final Key? buttonKey;
}

final class ChoiceHeadOptionsUnavailable extends ChoiceHeadOptions {
  const ChoiceHeadOptionsUnavailable({required this.label, this.buttonKey})
    : super._();

  /// Доступное название кнопки.
  final String label;

  /// Ключ кнопки.
  final Key? buttonKey;
}

/// Шапка выбора в листе: флажок, исходное намерение, цепочка шагов пути,
/// выбранное действие и кнопка параметров.
///
/// Исходное намерение — `caption` цвета `muted`, действие — `headline` цвета
/// `ink`; оба переносятся и не обрезаются. У выполненного выбора оба
/// зачёркнуты, а действие `muted`. Тексты, метки архива, цепочку, доступные
/// названия и ключи кнопок задаёт потребитель.
///
/// Флажок стоит в области шириной `tap-min` на всю высоту шапки. Кольцо
/// начинается у левого края шапки, поэтому область выходит за него на 11, а
/// текст стоит в 34 от края. Область кнопки параметров выходит за правый край
/// на 14. Обе полосы за краем принимают касания, пока родитель шире шапки на
/// эти полосы, например поле содержимого листа с отступами.
final class ChoiceHead extends StatelessWidget {
  const ChoiceHead({
    required this.goal,
    required this.action,
    required this.priority,
    required this.chain,
    required this.checkLabel,
    this.done = false,
    this.onToggle,
    this.goalBadge,
    this.actionBadge,
    this.options = const ChoiceHeadOptions.none(),
    this.checkKey,
    super.key,
  });

  /// Исходное намерение пути.
  final String goal;

  /// Выбранное действие.
  final String action;

  /// Приоритет выбора: цвет кольца флажка.
  final DoablePriority priority;

  /// Цепочка шагов пути между исходным намерением и действием; её приоритет и
  /// признак выполнения потребитель согласует с шапкой.
  final Widget chain;

  /// Выбор выполнен.
  final bool done;

  /// Доступное название флажка.
  final String checkLabel;

  /// Переключает выполнение; без него флажок выключен.
  final VoidCallback? onToggle;

  /// Метка архива после исходного намерения: [Badge.archivedInline], поэтому
  /// строка исходного намерения не становится выше своего текста.
  final Widget? goalBadge;

  /// Метка архива после действия, своей высоты.
  final Widget? actionBadge;

  final ChoiceHeadOptions options;

  /// Ключ кнопки флажка.
  final Key? checkKey;

  /// Насколько область флажка выходит за левый край шапки: кольцо стоит по
  /// центру области шириной `tap-min` и начинается у самого края.
  static const double _checkOverhang =
      (DoableMetrics.tapMin - DoableMetrics.checkSize) / 2;

  /// Насколько область кнопки параметров выходит за правый край шапки.
  static const double _optionsOverhang = 14;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final actionBadge = this.actionBadge;
    final strike = done ? TextDecoration.lineThrough : null;
    final options = this.options;

    return EdgeOverhang(
      start: _checkOverhang,
      end: options is ChoiceHeadOptionsNone ? 0 : _optionsOverhang,
      // Отклик нажатия рисуется на плоскости шапки, а не под ней:
      // https://api.flutter.dev/flutter/material/InkWell-class.html
      child: Material(
        type: MaterialType.transparency,
        // Высоту задаёт текст, а кнопки растягиваются по ней. `IntrinsicHeight`
        // не подходит: `Wrap` не учитывает перенос длинного названия внутри
        // своего ребёнка и занижает высоту, поэтому колонка вылезла бы вниз.
        // Кольца фокуса лежат за краем кнопок, поэтому `Stack` не обрезает.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: DoableMetrics.tapMin + 1,
                end: options is ChoiceHeadOptionsNone
                    ? 0
                    : DoableMetrics.tapMin,
                top: DoableMetrics.space2,
                bottom: 10,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 2,
                children: [
                  Wrap(
                    spacing: DoableMetrics.space2,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        goal,
                        style: DoableType.caption.copyWith(
                          color: colors.muted,
                          decoration: strike,
                        ),
                      ),
                      ?goalBadge,
                    ],
                  ),
                  // Цепочка отстоит от действия на 5: 2 между элементами и 3
                  // в запас под цепочкой.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: chain,
                  ),
                  Wrap(
                    spacing: DoableMetrics.space2,
                    runSpacing: DoableMetrics.space1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        action,
                        style: DoableType.headline.copyWith(
                          color: done ? colors.muted : colors.ink,
                          decoration: strike,
                        ),
                      ),
                      ?actionBadge,
                    ],
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: DoableMetrics.tapMin,
              child: _Button(
                key: checkKey,
                label: checkLabel,
                checked: done,
                onTap: onToggle,
                builder: (showsFocus) => Center(
                  child: _FocusRing(
                    radius: DoableMetrics.checkSize / 2,
                    shown: showsFocus,
                    // Галочка в цвет листа под кольцом.
                    child: ChoiceCheck(
                      priority: priority,
                      done: done,
                      markColor: colors.raised,
                    ),
                  ),
                ),
              ),
            ),
            switch (options) {
              ChoiceHeadOptionsNone() => const SizedBox.shrink(),
              ChoiceHeadOptionsAvailable(
                :final label,
                :final onOpen,
                :final buttonKey,
              ) =>
                _optionsButton(
                  colors,
                  key: buttonKey,
                  label: label,
                  onTap: onOpen,
                ),
              ChoiceHeadOptionsUnavailable(:final label, :final buttonKey) =>
                _optionsButton(
                  colors,
                  key: buttonKey,
                  label: label,
                  onTap: null,
                ),
            },
          ],
        ),
      ),
    );
  }

  /// Три точки в квадрате `tap-min` у верхнего правого угла. Точки стоят
  /// против первой строки исходного намерения.
  Widget _optionsButton(
    DoableColors colors, {
    required Key? key,
    required String label,
    required VoidCallback? onTap,
  }) => PositionedDirectional(
    end: 0,
    top: 0,
    width: DoableMetrics.tapMin,
    height: DoableMetrics.tapMin,
    child: _Button(
      key: key,
      label: label,
      onTap: onTap,
      builder: (showsFocus) => _FocusRing(
        radius: DoableMetrics.tapMin / 2,
        shown: showsFocus,
        child: Padding(
          padding: const EdgeInsets.only(bottom: DoableMetrics.space2),
          child: Center(
            child: DoableIcon(
              DoableIconData.more,
              size: DoableMetrics.iconSize,
              color: colors.muted,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Кнопка шапки: одна область нажатия с названием для диктора. Кольцо фокуса
/// клавиатуры рисует содержимое по признаку, который получает от кнопки.
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
          borderRadius: BorderRadius.circular(DoableMetrics.tapMin / 2),
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
/// плоскость шапки.
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
