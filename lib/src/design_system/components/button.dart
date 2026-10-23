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

  /// Второстепенное действие диалога подтверждения, например «Отмена»:
  /// плашка `fill` с текстом `ink` шириной по подписи.
  const Button.quiet({required this.label, required this.onPressed, super.key})
    : _kind = _ButtonKind.quiet,
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

  final String label;

  /// Доступное название; без него диктор объявляет [label].
  final String? semanticLabel;

  /// Без обработчика кнопка выключена: остаётся на своём месте плашкой
  /// `fill` с текстом `grip`, а текстовая — текстом `grip`, и объявляется
  /// недоступной.
  final VoidCallback? onPressed;

  final _ButtonKind _kind;

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
      _ButtonKind.quiet => _filled(
        colors,
        label,
        background: colors.fill,
        foreground: colors.ink,
        minimumSize: compact,
      ),
      _ButtonKind.danger => _filled(
        colors,
        label,
        background: colors.accent,
        foreground: colors.onAccent,
        minimumSize: compact,
      ),
      _ButtonKind.text => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          disabledForegroundColor: colors.grip,
          // Строка подписи 20 и отступы по 8 дают высоту control-height-sm.
          minimumSize: const Size(0, DoableMetrics.controlHeightSm),
          padding: const EdgeInsets.symmetric(
            horizontal: DoableMetrics.space2,
            vertical: DoableMetrics.space2,
          ),
          shape: const StadiumBorder(),
          textStyle: DoableType.section,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: label,
      ),
    };
  }

  Widget _filled(
    DoableColors colors,
    Widget label, {
    required Color background,
    required Color foreground,
    required Size minimumSize,
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
      padding: const EdgeInsets.symmetric(
        horizontal: DoableMetrics.space4,
        vertical: 10,
      ),
      shape: const StadiumBorder(),
      textStyle: DoableType.section,
      // Область нажатия выше плашки, как требует tap-min:
      // https://api.flutter.dev/flutter/material/MaterialTapTargetSize.html
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    child: label,
  );
}

enum _ButtonKind { primary, quiet, danger, text }
