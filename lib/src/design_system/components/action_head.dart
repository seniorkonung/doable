import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_priority.dart';
import '../doable_type.dart';
import 'action_check.dart';
import 'badge.dart';
import 'edge_overhang.dart';

/// Кнопка шапки действия: её нет, она доступна или временно недоступна.
///
/// Временно недоступная кнопка остаётся на месте, поэтому раскладка шапки не
/// сдвигается. Название есть только у вариантов с кнопкой.
sealed class ActionHeadButton {
  const ActionHeadButton._();

  /// Кнопки нет, например над редактором описания.
  const factory ActionHeadButton.none() = ActionHeadButtonNone;

  /// Кнопка принимает нажатие.
  const factory ActionHeadButton.available({
    required String label,
    required VoidCallback onOpen,
    Key? buttonKey,
  }) = ActionHeadButtonAvailable;

  /// Кнопка на месте, но не принимает нажатие: диктор объявляет её
  /// недоступной.
  const factory ActionHeadButton.unavailable({
    required String label,
    Key? buttonKey,
  }) = ActionHeadButtonUnavailable;
}

final class ActionHeadButtonNone extends ActionHeadButton {
  const ActionHeadButtonNone() : super._();
}

final class ActionHeadButtonAvailable extends ActionHeadButton {
  const ActionHeadButtonAvailable({
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

final class ActionHeadButtonUnavailable extends ActionHeadButton {
  const ActionHeadButtonUnavailable({required this.label, this.buttonKey})
    : super._();

  /// Доступное название кнопки.
  final String label;

  /// Ключ кнопки.
  final Key? buttonKey;
}

/// Шапка действия в листе: флажок, корневое намерение пути, цепочка
/// намерений, название действия и кнопка параметров.
///
/// Корневое намерение — `caption` цвета `muted`, название — `headline` цвета
/// `ink`; оба переносятся и не обрезаются. У выполненного действия оба
/// зачёркнуты, а название `muted`. Тексты, метки «В архиве» и «Удалено»,
/// цепочку, доступные названия и ключи кнопок задаёт потребитель.
///
/// Корневое намерение с цепочкой — путь в свёрнутом виде, и [path] делает их
/// одной кнопкой; название становится кнопкой через [nameEdit]. Область
/// нажатия каждой из них занимает всю ширину колонки текста, а область пути
/// ещё и верхнее поле шапки.
///
/// Флажок стоит в области шириной `tap-min` на всю высоту шапки. Кольцо
/// начинается у левого края шапки, поэтому область выходит за него на 11, а
/// текст стоит в 34 от края. Область кнопки параметров выходит за правый край
/// на 14. Обе полосы за краем принимают касания, пока родитель шире шапки на
/// эти полосы, например поле содержимого листа с отступами.
final class ActionHead extends StatelessWidget {
  const ActionHead({
    required this.goal,
    required this.action,
    required this.priority,
    required this.chain,
    required this.checkLabel,
    this.done = false,
    this.onToggle,
    this.goalBadge,
    this.actionBadge,
    this.path = const ActionHeadButton.none(),
    this.nameEdit = const ActionHeadButton.none(),
    this.options = const ActionHeadButton.none(),
    this.checkKey,
    super.key,
  });

  /// Корневое намерение пути.
  final String goal;

  /// Название действия.
  final String action;

  /// Приоритет действия: цвет кольца флажка.
  final DoablePriority priority;

  /// Цепочка намерений пути между корневым намерением и названием; её
  /// приоритет и признак выполнения потребитель согласует с шапкой.
  final Widget chain;

  /// Действие выполнено.
  final bool done;

  /// Доступное название флажка.
  final String checkLabel;

  /// Переключает выполнение; без него флажок выключен.
  final VoidCallback? onToggle;

  /// Метка «В архиве» или «Удалено» после корневого намерения:
  /// [Badge.archivedInline] или [Badge.deletedInline], поэтому строка
  /// корневого намерения не становится выше своего текста.
  final Widget? goalBadge;

  /// Метка после названия, своей высоты.
  final Widget? actionBadge;

  /// Кнопка, которая открывает вкладку пути. Когда вкладка уже открыта,
  /// потребитель передаёт недоступный вариант: кнопка остаётся на месте, но
  /// ничего не делает, потому что путь виден ниже.
  final ActionHeadButton path;

  /// Кнопка, которая открывает изменение названия и описания.
  final ActionHeadButton nameEdit;

  /// Кнопка параметров действия.
  final ActionHeadButton options;

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
      end: options is ActionHeadButtonNone ? 0 : _optionsOverhang,
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
                end: options is ActionHeadButtonNone ? 0 : DoableMetrics.tapMin,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                // Цепочка отстоит от названия на 5: 2 между элементами и 3
                // в запас под цепочкой.
                spacing: 2,
                children: [
                  _textButton(
                    path,
                    // Верхнее поле шапки принадлежит кнопке пути.
                    child: Padding(
                      padding: const EdgeInsets.only(top: DoableMetrics.space2),
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
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: chain,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _textButton(
                    nameEdit,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
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
                    ),
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
                radius: DoableMetrics.tapMin / 2,
                builder: (showsFocus) => Center(
                  child: _FocusRing(
                    radius: DoableMetrics.checkSize / 2,
                    shown: showsFocus,
                    // Галочка в цвет листа под кольцом.
                    child: ActionCheck(
                      priority: priority,
                      done: done,
                      markColor: colors.raised,
                    ),
                  ),
                ),
              ),
            ),
            switch (options) {
              ActionHeadButtonNone() => const SizedBox.shrink(),
              ActionHeadButtonAvailable(
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
              ActionHeadButtonUnavailable(:final label, :final buttonKey) =>
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

  /// Текст шапки, который [button] делает кнопкой. Без кнопки это сам [child],
  /// поэтому раскладка не зависит от того, есть ли кнопка.
  Widget _textButton(
    ActionHeadButton button, {
    required Widget child,
  }) => switch (button) {
    ActionHeadButtonNone() => child,
    ActionHeadButtonAvailable(:final label, :final onOpen, :final buttonKey) =>
      _textButtonOf(key: buttonKey, label: label, onTap: onOpen, child: child),
    ActionHeadButtonUnavailable(:final label, :final buttonKey) =>
      _textButtonOf(key: buttonKey, label: label, onTap: null, child: child),
  };

  Widget _textButtonOf({
    required Key? key,
    required String label,
    required VoidCallback? onTap,
    required Widget child,
  }) => _Button(
    key: key,
    label: label,
    onTap: onTap,
    radius: DoableMetrics.radiusSm,
    builder: (showsFocus) => _FocusRing(
      radius: DoableMetrics.radiusSm,
      shown: showsFocus,
      child: child,
    ),
  );

  /// Три точки в квадрате `tap-min` у верхнего правого угла. Точки стоят
  /// против первой строки корневого намерения.
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
      radius: DoableMetrics.tapMin / 2,
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
    required this.radius,
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

  /// Радиус отклика нажатия и кольца фокуса области.
  final double radius;

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
          borderRadius: BorderRadius.circular(widget.radius),
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
