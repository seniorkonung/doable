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
  }) : _kind = _ButtonKind.primary;

  /// Второстепенное действие диалога подтверждения, например «Отмена»:
  /// плашка `fill` с текстом `ink` шириной по подписи.
  const Button.quiet({required this.label, required this.onPressed, super.key})
    : _kind = _ButtonKind.quiet;

  /// Действие диалога подтверждения, которое необратимо удаляет или
  /// перезаписывает данные: плашка `accent` с текстом `on-accent` шириной по
  /// подписи.
  const Button.danger({required this.label, required this.onPressed, super.key})
    : _kind = _ButtonKind.danger;

  final String label;

  /// Без обработчика кнопка выключена: остаётся на своём месте плашкой
  /// `fill` с текстом `grip` и объявляется недоступной.
  final VoidCallback? onPressed;

  final _ButtonKind _kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final (background, foreground) = switch (_kind) {
      _ButtonKind.primary => (colors.ink, colors.bg),
      _ButtonKind.quiet => (colors.fill, colors.ink),
      _ButtonKind.danger => (colors.accent, colors.onAccent),
    };
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: colors.fill,
        disabledForegroundColor: colors.grip,
        // Строка подписи 20 и отступы по 10 дают высоту control-height,
        // а с крупным шрифтом плашка растёт вместе с текстом.
        minimumSize: switch (_kind) {
          _ButtonKind.primary => const Size.fromHeight(
            DoableMetrics.controlHeight,
          ),
          _ButtonKind.quiet ||
          _ButtonKind.danger => const Size(0, DoableMetrics.controlHeight),
        },
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
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

enum _ButtonKind { primary, quiet, danger }
