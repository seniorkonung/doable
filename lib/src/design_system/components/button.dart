import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Кнопка-пилюля, подпись которой называет действие нажатия.
final class Button extends StatelessWidget {
  /// Основное действие листа или экрана: плашка `ink` с текстом `bg`
  /// на всю ширину контейнера. Одна на плоскость.
  const Button.primary({
    required this.label,
    required this.onPressed,
    super.key,
  }) : _kind = _ButtonKind.primary,
       semanticLabel = null;

  /// Основное действие экрана правки справа в верхней панели, например
  /// «Сохранить»: плашка `ink` с текстом `bg` размера sm шириной по подписи.
  const Button.primarySmall({
    required this.label,
    required this.onPressed,
    super.key,
  }) : _kind = _ButtonKind.primarySmall,
       semanticLabel = null;

  /// Безопасный ответ диалога, который сохраняет данные, например
  /// «Продолжить правку» в диалоге отмены изменений или «Вернуть» в диалоге
  /// подтверждения: плашка `ink` с текстом `bg` размера md шириной по
  /// подписи.
  const Button.primaryCompact({
    required this.label,
    required this.onPressed,
    super.key,
  }) : _kind = _ButtonKind.primaryCompact,
       semanticLabel = null;

  /// Второстепенное действие диалога подтверждения, например «Отмена»:
  /// плашка `fill` с текстом `ink` шириной по подписи.
  const Button.quiet({required this.label, required this.onPressed, super.key})
    : _kind = _ButtonKind.quiet,
      semanticLabel = null;

  /// Второстепенное действие на всю ширину контейнера, например
  /// «Восстановить из архива» в шапке страницы: плашка `fill` с текстом `ink`.
  const Button.quietBlock({
    required this.label,
    required this.onPressed,
    super.key,
  }) : _kind = _ButtonKind.quietBlock,
       semanticLabel = null;

  /// Действие диалога подтверждения, которое необратимо удаляет или
  /// перезаписывает данные: плашка `accent` с текстом `on-accent` шириной по
  /// подписи.
  const Button.danger({required this.label, required this.onPressed, super.key})
    : _kind = _ButtonKind.danger,
      semanticLabel = null;

  /// Небольшое действие у края шапки, например «Сбросить» листа: текст
  /// `accent` без плашки размера sm шириной по подписи.
  const Button.text({
    required this.label,
    required String this.semanticLabel,
    required this.onPressed,
    super.key,
  }) : _kind = _ButtonKind.text;

  /// Выход рядом с основной кнопкой, например «Отменить» в диалоге отмены
  /// изменений: текст `accent` без плашки размера md шириной по подписи.
  const Button.textMedium({
    required this.label,
    required this.onPressed,
    super.key,
  }) : _kind = _ButtonKind.textMedium,
       semanticLabel = null;

  final String label;

  /// Доступное название; без него диктор объявляет [label].
  final String? semanticLabel;

  /// Без обработчика кнопка выключена: остаётся на своём месте плашкой
  /// `fill` с текстом `grip`, а текстовая — текстом `grip`, и объявляется
  /// недоступной.
  final VoidCallback? onPressed;

  final _ButtonKind _kind;

  static const double _smallVerticalPadding = 8;
  static const double _smallHorizontalPadding = 14;

  /// Высота плашки размера sm в масштабе [textScaler]: не ниже
  /// `control-height-sm`, а с крупным шрифтом растёт вместе с подписью.
  static double smallHeight(TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: DoableType.section),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    try {
      return math.max(
        DoableMetrics.controlHeightSm,
        painter.height + 2 * _smallVerticalPadding,
      );
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final label = Text(
      this.label,
      semanticsLabel: semanticLabel,
      textAlign: TextAlign.center,
    );
    const compact = Size(0, DoableMetrics.controlHeight);
    return switch (_kind) {
      _ButtonKind.primary => _filled(
        colors,
        label,
        background: colors.ink,
        foreground: colors.bg,
        minimumSize: const Size.fromHeight(DoableMetrics.controlHeight),
      ),
      _ButtonKind.primarySmall => _filled(
        colors,
        label,
        background: colors.ink,
        foreground: colors.bg,
        // Строка подписи 20 и отступы по 8 дают высоту control-height-sm.
        minimumSize: const Size(0, DoableMetrics.controlHeightSm),
        padding: const EdgeInsets.symmetric(
          horizontal: _smallHorizontalPadding,
          vertical: _smallVerticalPadding,
        ),
      ),
      _ButtonKind.primaryCompact => _filled(
        colors,
        label,
        background: colors.ink,
        foreground: colors.bg,
        minimumSize: compact,
      ),
      _ButtonKind.quiet => _filled(
        colors,
        label,
        background: colors.fill,
        foreground: colors.ink,
        minimumSize: compact,
      ),
      _ButtonKind.quietBlock => _filled(
        colors,
        label,
        background: colors.fill,
        foreground: colors.ink,
        minimumSize: const Size.fromHeight(DoableMetrics.controlHeight),
      ),
      _ButtonKind.danger => _filled(
        colors,
        label,
        background: colors.accent,
        foreground: colors.onAccent,
        minimumSize: compact,
      ),
      _ButtonKind.textMedium => _text(
        colors,
        label,
        minimumSize: compact,
        // Строка подписи 20 и отступы по 10 дают высоту control-height.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      _ButtonKind.text => _text(
        colors,
        label,
        // Строка подписи 20 и отступы по 8 дают высоту control-height-sm.
        minimumSize: const Size(0, DoableMetrics.controlHeightSm),
        padding: const EdgeInsets.symmetric(
          horizontal: DoableMetrics.space2,
          vertical: _smallVerticalPadding,
        ),
      ),
    };
  }

  Widget _text(
    DoableColors colors,
    Widget label, {
    required Size minimumSize,
    required EdgeInsetsGeometry padding,
  }) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: colors.accent,
      disabledForegroundColor: colors.grip,
      minimumSize: minimumSize,
      padding: padding,
      shape: const StadiumBorder(),
      textStyle: DoableType.section,
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    child: label,
  );

  Widget _filled(
    DoableColors colors,
    Widget label, {
    required Color background,
    required Color foreground,
    required Size minimumSize,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: DoableMetrics.space4,
      vertical: 10,
    ),
  }) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: colors.fill,
      disabledForegroundColor: colors.grip,
      // Строка подписи 20 и отступы по 10 дают высоту control-height,
      // а с крупным шрифтом плашка растёт вместе с текстом.
      minimumSize: minimumSize,
      padding: padding,
      shape: const StadiumBorder(),
      textStyle: DoableType.section,
      // Область нажатия выше плашки, как требует tap-min:
      // https://api.flutter.dev/flutter/material/MaterialTapTargetSize.html
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    child: label,
  );
}

enum _ButtonKind {
  primary,
  primarySmall,
  primaryCompact,
  quiet,
  quietBlock,
  danger,
  textMedium,
  text,
}
